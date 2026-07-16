import {
  clearExistingDraftDailyCardsForFullGeneration,
  DAY_PLAN_CONTAINER_SELECT,
  DRAFT_DAILY_CARD_UPDATE_SELECT,
  findLatestDraftDayPlanContainer,
  generatedDailyCardValues,
  generationPersistFailure,
  insertGeneratedIdeas,
  insertThinDraftDayPlanContainer,
  postgrestErrorMessage,
  recoverConflictingDailyCardRow,
  recoverInsertedDailyCardRow,
  recoverWeeklyPlanIDFromExistingCards,
  replaceDailyCardReferences,
  updateExistingDraftDailyCard,
  upsertDailyCardRow,
  upsertDraftWeeklyPlan,
  upsertGeneratedDailyCards,
} from "./generation-persistence.ts";
import type {
  GeneratedDailyCard,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerationInputSnapshot,
} from "./generation.ts";
import { weekDates } from "./generation-validation.ts";

type CapturedOp = {
  table: string;
  operation: "select" | "insert" | "update" | "delete";
  values: unknown;
  filters: Record<string, unknown>;
  filterOrder: string[];
  selectColumns?: string;
  inFilters?: Record<string, unknown[]>;
  order?: { column: string; ascending?: boolean };
  limit?: number;
  terminal?: "single" | "maybeSingle";
};

type FakeState = {
  ops: CapturedOp[];
  weeklyPlans: Record<string, unknown>[];
  dailyCards: Record<string, unknown>[];
  references: Record<string, unknown>[];
  ideas: Record<string, unknown>[];
  selectError?: {
    message: string;
    details?: string;
    hint?: string;
    code?: string;
  };
  writeError?: {
    message: string;
    details?: string;
    hint?: string;
    code?: string;
  };
  insertReturnNull?: boolean;
  insertError?: { message: string };
  updateReturnNull?: boolean;
  clearReferenceError?: { message: string };
  insertReferenceError?: { message: string };
  ideasError?: { message: string };
  deleteError?: { message: string };
};

const WORKSPACE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CREATOR = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const PLAN = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const CARD = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const MEMBER = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const REF = "ffffffff-ffff-4fff-8fff-ffffffffffff";
const WEEK_START = "2026-06-08";

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(message ?? `Expected ${right}, got ${left}`);
  }
}

function sampleCard(
  overrides: Partial<GeneratedDailyCard> = {},
): GeneratedDailyCard {
  return {
    scheduled_date: "2026-06-08",
    format: "Reel",
    primary_surface: "instagram_reels",
    duration_seconds: 30,
    title: "Generated title",
    hook: "Generated hook",
    weekly_brief_anchor: "anchor",
    brief_alignment: "aligned",
    brief_context_tags: ["tag"],
    why_today: "why",
    growth_job: "growth",
    save_share_reason: "save",
    content_pillar: "lifestyle",
    shootability: "easy",
    estimated_shoot_minutes: 12,
    energy_required: "low",
    language_mode: "english",
    scene_list: [{
      number: 1,
      title: "open",
      duration: "0:00-0:02",
      symbol: "A",
    }],
    shot_timeline: [{
      timestamp: "0:00-0:02",
      detail: "open",
    }],
    script: "script",
    voiceover_timeline: [{
      timestamp: "0:00-0:02",
      video_portion: "open",
      voiceover: "line",
    }],
    no_voiceover_version: "silent",
    silent_version_timeline: [{
      timestamp: "0:00-0:02",
      detail: "open",
    }],
    on_screen_text: ["OST"],
    on_screen_text_timeline: [{
      timestamp: "0:00-0:02",
      text: "OST",
      placement: "center",
    }],
    caption: "caption",
    cta: "cta",
    hashtags: ["#a"],
    cover_text: "cover",
    post_instructions: "post instructions",
    brand_event_notes: "",
    backup_story: "backup story",
    backup_story_detail: [{
      timestamp: "0:00-0:01",
      detail: "backup",
    }],
    backup_caption_only: "backup caption",
    caption_backup_detail: "caption backup detail",
    audio_option_notes: "audio notes",
    creator_fit_score: 0.9,
    risk_notes: ["risk"],
    assumptions: ["assumption"],
    source_note: "source note",
    source_reference_ids: [REF],
    ...overrides,
  };
}

function sampleGenerated(
  overrides: Partial<GeneratedWeekOutput> = {},
): GeneratedWeekOutput {
  return {
    strategy_summary: "strategy",
    warnings: ["warn"],
    assumptions: ["assume"],
    daily_cards: [sampleCard()],
    idea_bank: [{
      title: "idea",
      summary: "summary",
      suggested_use: "use",
      shootability: "easy",
      tags: ["t"],
      fit_score: 0.8,
      source_note: "note",
      status: "saved",
    }],
    source_summary: "sources",
    ...overrides,
  };
}

function sampleRequest(
  overrides: Partial<GenerateWeekRequest> = {},
): GenerateWeekRequest {
  return {
    creator_id: CREATOR,
    week_start_date: WEEK_START,
    mode: "generate_draft",
    preserve_manual_edits: false,
    mock: true,
    response_mode: "sync",
    ...overrides,
  };
}

function sampleInput(): GenerationInputSnapshot {
  return {
    creator_id: CREATOR,
    week_start_date: WEEK_START,
    creator_profile: { id: "11111111-1111-4111-8111-111111111111" },
    weekly_setup: null,
    confirmed_references: [],
    reference_extractions: [],
    recent_archive: [],
    idea_bank: [],
    patterns: [],
    trends: [],
    audio_options: [],
    brand_briefs: [],
    key_moments: [],
  };
}

function fakeAdmin(state: FakeState) {
  return {
    from(table: string) {
      return new FakeQuery(table, state);
    },
  };
}

class FakeQuery implements PromiseLike<{ data: unknown; error: unknown }> {
  private operation: CapturedOp["operation"] = "select";
  private values: unknown = null;
  private filters: Record<string, unknown> = {};
  private filterOrder: string[] = [];
  private inFilters: Record<string, unknown[]> = {};
  private selectColumns?: string;
  private orderSpec?: { column: string; ascending?: boolean };
  private limitCount?: number;
  private terminal?: "single" | "maybeSingle";

  constructor(
    private readonly table: string,
    private readonly state: FakeState,
  ) {}

  select(columns?: string): FakeQuery {
    this.selectColumns = columns;
    return this;
  }

  insert(values: unknown): FakeQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  update(values: Record<string, unknown>): FakeQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  delete(): FakeQuery {
    this.operation = "delete";
    return this;
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    this.filterOrder.push(column);
    return this;
  }

  in(column: string, values: unknown[]): FakeQuery {
    this.inFilters[column] = values;
    this.filterOrder.push(column);
    return this;
  }

  order(column: string, options?: { ascending?: boolean }): FakeQuery {
    this.orderSpec = { column, ascending: options?.ascending };
    return this;
  }

  limit(count: number): FakeQuery {
    this.limitCount = count;
    return this;
  }

  single(): FakeQuery {
    this.terminal = "single";
    return this;
  }

  maybeSingle(): FakeQuery {
    this.terminal = "maybeSingle";
    return this;
  }

  then<TResult1 = { data: unknown; error: unknown }, TResult2 = never>(
    onfulfilled?:
      | ((value: { data: unknown; error: unknown }) =>
        | TResult1
        | PromiseLike<TResult1>)
      | null,
    onrejected?:
      | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
      | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve(this.execute()).then(onfulfilled, onrejected);
  }

  private execute(): { data: unknown; error: unknown } {
    const op: CapturedOp = {
      table: this.table,
      operation: this.operation,
      values: this.values,
      filters: { ...this.filters },
      filterOrder: [...this.filterOrder],
      selectColumns: this.selectColumns,
      inFilters: { ...this.inFilters },
      order: this.orderSpec,
      limit: this.limitCount,
      terminal: this.terminal,
    };
    this.state.ops.push(op);

    if (this.operation === "select" && this.state.selectError) {
      return { data: null, error: this.state.selectError };
    }
    if (
      (this.operation === "insert" || this.operation === "update" ||
        this.operation === "delete") &&
      this.state.writeError
    ) {
      return { data: null, error: this.state.writeError };
    }

    if (this.table === "weekly_plans") {
      return this.executeWeeklyPlans();
    }
    if (this.table === "daily_cards") {
      return this.executeDailyCards();
    }
    if (this.table === "daily_card_references") {
      return this.executeReferences();
    }
    if (this.table === "ideas") {
      return this.executeIdeas();
    }
    return { data: null, error: null };
  }

  private matches(row: Record<string, unknown>): boolean {
    for (const [key, value] of Object.entries(this.filters)) {
      if (row[key] !== value) return false;
    }
    for (const [key, values] of Object.entries(this.inFilters)) {
      if (!values.includes(row[key])) return false;
    }
    return true;
  }

  private executeWeeklyPlans(): { data: unknown; error: unknown } {
    if (this.operation === "select") {
      let rows = this.state.weeklyPlans.filter((row) => this.matches(row));
      if (this.orderSpec?.column === "updated_at") {
        rows = [...rows].sort((a, b) => {
          const left = String(a.updated_at ?? "");
          const right = String(b.updated_at ?? "");
          return this.orderSpec?.ascending === false
            ? right.localeCompare(left)
            : left.localeCompare(right);
        });
      }
      if (this.limitCount != null) {
        rows = rows.slice(0, this.limitCount);
      }
      if (this.terminal === "single" || this.terminal === "maybeSingle") {
        return { data: rows[0] ?? null, error: null };
      }
      return { data: rows, error: null };
    }
    if (this.operation === "insert") {
      const row = {
        ...(this.values as Record<string, unknown>),
      };
      this.state.weeklyPlans.push(row);
      return { data: { id: row.id }, error: null };
    }
    if (this.operation === "update") {
      const index = this.state.weeklyPlans.findIndex((row) =>
        this.matches(row)
      );
      if (index < 0) {
        return {
          data: null,
          error: this.terminal === "maybeSingle"
            ? null
            : { message: "not_found" },
        };
      }
      this.state.weeklyPlans[index] = {
        ...this.state.weeklyPlans[index],
        ...(this.values as Record<string, unknown>),
      };
      return { data: { id: this.state.weeklyPlans[index].id }, error: null };
    }
    return { data: null, error: null };
  }

  private executeDailyCards(): { data: unknown; error: unknown } {
    if (this.operation === "select") {
      const rows = this.state.dailyCards.filter((row) => this.matches(row));
      if (this.terminal === "single" || this.terminal === "maybeSingle") {
        return { data: rows[0] ?? null, error: null };
      }
      return { data: rows, error: null };
    }
    if (this.operation === "insert") {
      if (this.state.insertError) {
        return { data: null, error: this.state.insertError };
      }
      const row = { ...(this.values as Record<string, unknown>) };
      this.state.dailyCards.push(row);
      if (this.state.insertReturnNull) {
        return { data: null, error: null };
      }
      return {
        data: { id: row.id, scheduled_date: row.scheduled_date },
        error: null,
      };
    }
    if (this.operation === "update") {
      const index = this.state.dailyCards.findIndex((row) => this.matches(row));
      if (index < 0 || this.state.updateReturnNull) {
        return { data: null, error: null };
      }
      this.state.dailyCards[index] = {
        ...this.state.dailyCards[index],
        ...(this.values as Record<string, unknown>),
      };
      return {
        data: {
          id: this.state.dailyCards[index].id,
          scheduled_date: this.state.dailyCards[index].scheduled_date,
        },
        error: null,
      };
    }
    if (this.operation === "delete") {
      if (this.state.deleteError) {
        return { data: null, error: this.state.deleteError };
      }
      this.state.dailyCards = this.state.dailyCards.filter((row) =>
        !this.matches(row)
      );
      return { data: null, error: null };
    }
    return { data: null, error: null };
  }

  private executeReferences(): { data: unknown; error: unknown } {
    if (this.operation === "delete") {
      if (this.state.clearReferenceError) {
        return { data: null, error: this.state.clearReferenceError };
      }
      this.state.references = this.state.references.filter((row) =>
        !this.matches(row)
      );
      return { data: null, error: null };
    }
    if (this.operation === "insert") {
      if (this.state.insertReferenceError) {
        return { data: null, error: this.state.insertReferenceError };
      }
      const rows = Array.isArray(this.values) ? this.values : [this.values];
      this.state.references.push(...(rows as Record<string, unknown>[]));
      return { data: rows, error: null };
    }
    return { data: null, error: null };
  }

  private executeIdeas(): { data: unknown; error: unknown } {
    if (this.operation === "insert") {
      if (this.state.ideasError) {
        return { data: null, error: this.state.ideasError };
      }
      const rows = (Array.isArray(this.values) ? this.values : [this.values])
        .map((row, index) => ({
          id: `99999999-9999-4999-8999-99999999999${index}`,
          title: (row as Record<string, unknown>).title,
          summary: (row as Record<string, unknown>).summary,
          suggested_use: (row as Record<string, unknown>).suggested_use,
          shootability: (row as Record<string, unknown>).shootability,
          status: (row as Record<string, unknown>).status,
        }));
      this.state.ideas.push(...rows);
      return { data: rows, error: null };
    }
    return { data: null, error: null };
  }
}

Deno.test("generationPersistFailure returns truncated 500 body", async () => {
  const longDetail = "x".repeat(600);
  const result = generationPersistFailure("daily_card_upsert", {
    message: longDetail,
  });
  assertEquals(result.response.status, 500);
  const body = await result.response.json();
  assertEquals(body.error, "generation_persist_failed");
  assertEquals(body.step, "daily_card_upsert");
  assertEquals(body.detail, "x".repeat(500));
});

Deno.test("postgrestErrorMessage extracts message/details/hint/code", () => {
  assertEquals(postgrestErrorMessage({ message: "boom" }), "boom");
  assertEquals(postgrestErrorMessage({ details: "detail" }), "detail");
  assertEquals(postgrestErrorMessage({ hint: "hint" }), "hint");
  assertEquals(postgrestErrorMessage({ code: "23505" }), "23505");
  assertEquals(postgrestErrorMessage(new Error("err")), "err");
  assertEquals(postgrestErrorMessage("raw"), "raw");
  assertEquals(postgrestErrorMessage(null), "unknown_error");
});

Deno.test("generatedDailyCardValues maps nested fields and storyboard default", () => {
  const values = generatedDailyCardValues(sampleCard({
    brand_event_notes: "",
  }));
  assertEquals(values.status, "draft");
  assertEquals(values.storyboard_thumbnail_assets, []);
  assertEquals(values.brand_event_notes, null);
  assertEquals(
    (values.post_instructions as Record<string, unknown>).instructions,
    "post instructions",
  );
  assertEquals(
    (values.post_instructions as Record<string, unknown>).audio_option_notes,
    "audio notes",
  );
  assertEquals(
    (values.post_instructions as Record<string, unknown>).caption_backup_detail,
    "caption backup detail",
  );
  assertEquals(
    (values.backup_story as Record<string, unknown>).line,
    "backup story",
  );
  assertEquals(
    (values.backup_caption_only as Record<string, unknown>).detail,
    "caption backup detail",
  );
});

Deno.test("clearExistingDraftDailyCardsForFullGeneration scopes delete and soft-fails", async () => {
  const state: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [{
      id: CARD,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
    }],
    references: [],
    ideas: [],
  };
  const admin = fakeAdmin(state) as never;
  const ok = await clearExistingDraftDailyCardsForFullGeneration(
    admin,
    WORKSPACE,
    CREATOR,
    PLAN,
  );
  assert("ok" in ok);
  assertEquals(state.dailyCards.length, 0);
  assertEquals(state.ops[0].operation, "delete");
  assertEquals(state.ops[0].filters, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_plan_id: PLAN,
  });

  const failState: FakeState = {
    ...state,
    ops: [],
    deleteError: { message: "clear failed" },
  };
  const failed = await clearExistingDraftDailyCardsForFullGeneration(
    fakeAdmin(failState) as never,
    WORKSPACE,
    CREATOR,
    PLAN,
  );
  assert("response" in failed);
  const body = await failed.response.json();
  assertEquals(body.step, "daily_cards_clear_existing");
});

Deno.test("upsertDraftWeeklyPlan soft-locks with 409", async () => {
  const state: FakeState = {
    ops: [],
    weeklyPlans: [{
      id: PLAN,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      week_start_date: WEEK_START,
      status: "draft",
      is_soft_locked: true,
      updated_at: "2026-06-08T10:00:00.000Z",
    }],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const result = await upsertDraftWeeklyPlan(
    fakeAdmin(state) as never,
    WORKSPACE,
    sampleRequest(),
    MEMBER,
    null,
    sampleInput(),
    sampleGenerated(),
  );
  assert("response" in result);
  assertEquals(result.response.status, 409);
  assertEquals(
    await result.response.json(),
    { error: "existing_published_week_locked" },
  );
});

Deno.test("upsertDraftWeeklyPlan inserts when absent and updates when present", async () => {
  const insertState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const inserted = await upsertDraftWeeklyPlan(
    fakeAdmin(insertState) as never,
    WORKSPACE,
    sampleRequest(),
    MEMBER,
    { id: "22222222-2222-4222-8222-222222222222" },
    sampleInput(),
    sampleGenerated(),
  );
  assert("weeklyPlanID" in inserted);
  assert(typeof inserted.weeklyPlanID === "string");
  assertEquals(
    insertState.ops.find((op) => op.operation === "insert")?.table,
    "weekly_plans",
  );

  const updateState: FakeState = {
    ops: [],
    weeklyPlans: [{
      id: PLAN,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      week_start_date: WEEK_START,
      status: "draft",
      is_soft_locked: false,
      updated_at: "2026-06-08T10:00:00.000Z",
    }],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const updated = await upsertDraftWeeklyPlan(
    fakeAdmin(updateState) as never,
    WORKSPACE,
    sampleRequest(),
    MEMBER,
    null,
    sampleInput(),
    sampleGenerated(),
  );
  assert("weeklyPlanID" in updated);
  assertEquals(updated.weeklyPlanID, PLAN);
  assert(
    updateState.ops.some((op) =>
      op.table === "weekly_plans" && op.operation === "update"
    ),
  );
});

Deno.test("upsertDraftWeeklyPlan recovers duplicate plan id from seven matching cards", async () => {
  const recoveredPlan = "12121212-1212-4121-8121-121212121212";
  const dates = weekDates(WEEK_START);
  const state: FakeState = {
    ops: [],
    weeklyPlans: [{
      id: recoveredPlan,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      week_start_date: WEEK_START,
      // Outside draft/reviewed lookup, so recovery path is used.
      status: "published",
      is_soft_locked: false,
      updated_at: "2026-06-08T10:00:00.000Z",
    }],
    dailyCards: dates.map((scheduled_date, index) => ({
      id: `33333333-3333-4333-8333-33333333333${index}`,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: recoveredPlan,
      scheduled_date,
    })),
    references: [],
    ideas: [],
  };
  const result = await upsertDraftWeeklyPlan(
    fakeAdmin(state) as never,
    WORKSPACE,
    sampleRequest(),
    MEMBER,
    null,
    sampleInput(),
    sampleGenerated(),
  );
  assert("weeklyPlanID" in result);
  assertEquals(result.weeklyPlanID, recoveredPlan);
  assert(
    state.ops.some((op) =>
      op.table === "weekly_plans" && op.operation === "update"
    ),
    "recovered plan should update rather than insert",
  );
});

Deno.test("recoverWeeklyPlanIDFromExistingCards requires all seven dates and one UUID", async () => {
  const planID = "14141414-1414-4141-8141-141414141414";
  const dates = weekDates(WEEK_START);
  const fullState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: dates.map((scheduled_date, index) => ({
      id: `15151515-1515-4151-8151-15151515151${index}`,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: planID,
      scheduled_date,
    })),
    references: [],
    ideas: [],
  };
  assertEquals(
    await recoverWeeklyPlanIDFromExistingCards(
      fakeAdmin(fullState) as never,
      WORKSPACE,
      CREATOR,
      WEEK_START,
    ),
    planID,
  );

  const incomplete = {
    ...fullState,
    dailyCards: fullState.dailyCards.slice(0, 6),
    ops: [],
  };
  assertEquals(
    await recoverWeeklyPlanIDFromExistingCards(
      fakeAdmin(incomplete) as never,
      WORKSPACE,
      CREATOR,
      WEEK_START,
    ),
    undefined,
  );

  const mixed = {
    ...fullState,
    dailyCards: fullState.dailyCards.map((row, index) => ({
      ...row,
      weekly_plan_id: index === 0
        ? "16161616-1616-4161-8161-161616161616"
        : planID,
    })),
    ops: [],
  };
  assertEquals(
    await recoverWeeklyPlanIDFromExistingCards(
      fakeAdmin(mixed) as never,
      WORKSPACE,
      CREATOR,
      WEEK_START,
    ),
    undefined,
  );
});

Deno.test("insertGeneratedIdeas writes contract and returns empty bank on failure", async () => {
  const okState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const ok = await insertGeneratedIdeas(
    fakeAdmin(okState) as never,
    WORKSPACE,
    CREATOR,
    sampleGenerated(),
  );
  assert("ideaBank" in ok);
  assertEquals(ok.ideaBank.length, 1);
  const insert = okState.ops.find((op) => op.operation === "insert");
  assert(insert);
  assertEquals(insert.table, "ideas");
  assertEquals(
    insert.selectColumns,
    "id,title,summary,suggested_use,shootability,status",
  );
  const row = (insert.values as Record<string, unknown>[])[0];
  assertEquals(row.workspace_id, WORKSPACE);
  assertEquals(row.creator_id, CREATOR);
  assertEquals(row.title, "idea");
  assertEquals(row.notes, "note");
  assertEquals(row.status, "saved");

  const failState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
    ideasError: { message: "ideas failed" },
  };
  const failed = await insertGeneratedIdeas(
    fakeAdmin(failState) as never,
    WORKSPACE,
    CREATOR,
    sampleGenerated(),
  );
  assert("ideaBank" in failed);
  assertEquals(failed.ideaBank, []);
});

Deno.test("replaceDailyCardReferences clear/insert contracts continue on warnings", async () => {
  const state: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [{
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      daily_card_id: CARD,
      source_reference_id: "00000000-0000-4000-8000-000000000000",
    }],
    ideas: [],
  };
  const ok = await replaceDailyCardReferences(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    CARD,
    sampleCard(),
  );
  assert("ok" in ok);
  assertEquals(state.ops[0].operation, "delete");
  assertEquals(state.ops[0].filters, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    daily_card_id: CARD,
  });
  assertEquals(state.ops[1].operation, "insert");
  assertEquals(state.ops[1].values, [{
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    daily_card_id: CARD,
    source_reference_id: REF,
    reason: "source note",
  }]);

  const warnState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
    clearReferenceError: { message: "clear failed" },
    insertReferenceError: { message: "insert failed" },
  };
  const warned = await replaceDailyCardReferences(
    fakeAdmin(warnState) as never,
    WORKSPACE,
    CREATOR,
    CARD,
    sampleCard(),
  );
  assert("ok" in warned);
});

Deno.test("upsertGeneratedDailyCards preserves manual edits and chooses update vs insert", async () => {
  const existingID = "17171717-1717-4171-8171-171717171717";
  const state: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [{
      id: existingID,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
      title: "Manual title",
      why_today: "Manual why",
      shootability: "manual shoot",
      estimated_shoot_minutes: 9,
      scene_list: [{
        number: 1,
        title: "manual",
        duration: "0:00-0:02",
        symbol: "M",
      }],
      caption: "Manual caption",
      backup_story: { line: "Manual backup" },
      backup_caption_only: { line: "Manual caption backup" },
    }],
    references: [],
    ideas: [],
  };
  const result = await upsertGeneratedDailyCards(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    PLAN,
    [sampleCard()],
    true,
  );
  assert("dailyCards" in result);
  assertEquals(result.dailyCards[0].title, "Manual title");
  assertEquals(result.dailyCards[0].caption, "Manual caption");
  assertEquals(result.dailyCards[0].id, existingID);
  assert(
    state.ops.some((op) =>
      op.table === "daily_cards" && op.operation === "update" &&
      op.filters.id === existingID
    ),
  );

  const insertOnly: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const inserted = await upsertGeneratedDailyCards(
    fakeAdmin(insertOnly) as never,
    WORKSPACE,
    CREATOR,
    PLAN,
    [sampleCard({ scheduled_date: "2026-06-09", source_reference_ids: [] })],
    false,
  );
  assert("dailyCards" in inserted);
  assert(
    insertOnly.ops.some((op) =>
      op.table === "daily_cards" && op.operation === "insert"
    ),
  );
});

Deno.test("upsertGeneratedDailyCards reference clear/insert warnings are non-fatal", async () => {
  const state: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
    clearReferenceError: { message: "clear refs failed" },
    insertReferenceError: { message: "insert refs failed" },
  };
  const result = await upsertGeneratedDailyCards(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    PLAN,
    [sampleCard()],
    false,
  );
  assert("dailyCards" in result);
  assertEquals(result.dailyCards.length, 1);
});

Deno.test("upsertDailyCardRow recovers insert-no-row and conflicting scheduled-date", async () => {
  const row = {
    id: CARD,
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_plan_id: PLAN,
    scheduled_date: "2026-06-08",
    title: "generated",
    status: "draft",
  };

  const noRowState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
    insertReturnNull: true,
  };
  // Seed after insert path writes the row with null return.
  const noRowAdmin = fakeAdmin(noRowState) as never;
  const recoveredInserted = await upsertDailyCardRow(noRowAdmin, row);
  assert("id" in recoveredInserted);
  assertEquals(recoveredInserted.id, CARD);

  const conflictID = "18181818-1818-4181-8181-181818181818";
  const conflictState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [{
      id: conflictID,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
      title: "existing",
    }],
    references: [],
    ideas: [],
    insertError: { message: "duplicate key" },
  };
  const recoveredConflict = await upsertDailyCardRow(
    fakeAdmin(conflictState) as never,
    { ...row, id: "19191919-1919-4191-8191-191919191919", title: "new" },
  );
  assert("id" in recoveredConflict);
  assertEquals(recoveredConflict.id, conflictID);
  assertEquals(
    conflictState.dailyCards.find((card) => card.id === conflictID)?.title,
    "new",
  );
});

Deno.test("recoverInsertedDailyCardRow and recoverConflictingDailyCardRow filters", async () => {
  const row = {
    id: CARD,
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_plan_id: PLAN,
    scheduled_date: "2026-06-08",
    title: "value",
  };
  const insertedState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [{ ...row }],
    references: [],
    ideas: [],
  };
  const inserted = await recoverInsertedDailyCardRow(
    fakeAdmin(insertedState) as never,
    row,
  );
  assertEquals(inserted, { id: CARD, scheduledDate: "2026-06-08" });
  assertEquals(insertedState.ops[0].filters, {
    id: CARD,
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_plan_id: PLAN,
    scheduled_date: "2026-06-08",
  });

  const conflictState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [{
      id: "20202020-2020-4202-8202-202020202020",
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
      title: "old",
    }],
    references: [],
    ideas: [],
  };
  const conflict = await recoverConflictingDailyCardRow(
    fakeAdmin(conflictState) as never,
    row,
  );
  assertEquals(conflict?.id, "20202020-2020-4202-8202-202020202020");
  assert(
    conflictState.ops.some((op) =>
      op.operation === "update" &&
      op.filters.id === "20202020-2020-4202-8202-202020202020"
    ),
  );
});

Deno.test("findLatestDraftDayPlanContainer uses draft-only lookup chain", async () => {
  const state: FakeState = {
    ops: [],
    weeklyPlans: [{
      id: PLAN,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      week_start_date: WEEK_START,
      status: "draft",
      is_soft_locked: false,
      updated_at: "2026-06-08T12:00:00.000Z",
    }, {
      id: "21212121-2121-4121-8121-212121212121",
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      week_start_date: WEEK_START,
      status: "draft",
      is_soft_locked: false,
      updated_at: "2026-06-08T10:00:00.000Z",
    }, {
      id: "22222222-2222-4222-8222-222222222222",
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      week_start_date: WEEK_START,
      status: "reviewed",
      is_soft_locked: false,
      updated_at: "2026-06-08T13:00:00.000Z",
    }],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const result = await findLatestDraftDayPlanContainer(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    WEEK_START,
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.[0]?.id, PLAN);
  const op = state.ops[0];
  assertEquals(op.table, "weekly_plans");
  assertEquals(op.operation, "select");
  assertEquals(op.selectColumns, DAY_PLAN_CONTAINER_SELECT);
  assertEquals(op.filters, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    week_start_date: WEEK_START,
  });
  assertEquals(op.filterOrder, [
    "workspace_id",
    "creator_id",
    "week_start_date",
    "status",
  ]);
  assertEquals(op.inFilters, { status: ["draft"] });
  assertEquals(op.order, { column: "updated_at", ascending: false });
  assertEquals(op.limit, 1);
  assertEquals(op.terminal, undefined);

  const failState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
    selectError: { message: "lookup failed" },
  };
  const failed = await findLatestDraftDayPlanContainer(
    fakeAdmin(failState) as never,
    WORKSPACE,
    CREATOR,
    WEEK_START,
  );
  assertEquals(failed.data, null);
  assertEquals((failed.error as { message: string }).message, "lookup failed");
});

Deno.test("insertThinDraftDayPlanContainer writes exact thin draft payload", async () => {
  const row = {
    id: PLAN,
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_setup_id: null,
    creator_profile_id: null,
    week_start_date: WEEK_START,
    status: "draft" as const,
    strategy_summary: "Day-at-a-time container week.",
    warnings: [],
    assumptions: ["Created automatically for single-day generation."],
    is_soft_locked: false as const,
    created_by_member_id: MEMBER,
  };
  const state: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const result = await insertThinDraftDayPlanContainer(
    fakeAdmin(state) as never,
    row,
  );
  assertEquals(result.error, null);
  assertEquals(result.data, { id: PLAN });
  const op = state.ops[0];
  assertEquals(op.table, "weekly_plans");
  assertEquals(op.operation, "insert");
  assertEquals(op.values, row);
  assertEquals(op.selectColumns, "id");
  assertEquals(op.terminal, "single");

  const failState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
    writeError: { message: "insert failed" },
  };
  const failed = await insertThinDraftDayPlanContainer(
    fakeAdmin(failState) as never,
    row,
  );
  assertEquals(failed.data, null);
  assertEquals((failed.error as { message: string }).message, "insert failed");

  const nullState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const nullAdmin = {
    from(table: string) {
      return {
        insert(values: unknown) {
          nullState.ops.push({
            table,
            operation: "insert",
            values,
            filters: {},
            filterOrder: [],
            selectColumns: "id",
            terminal: "single",
          });
          return {
            select() {
              return {
                single() {
                  return Promise.resolve({ data: null, error: null });
                },
              };
            },
          };
        },
      };
    },
  };
  const noRow = await insertThinDraftDayPlanContainer(
    nullAdmin as never,
    row,
  );
  assertEquals(noRow.data, null);
  assertEquals(noRow.error, null);
});

Deno.test("updateExistingDraftDailyCard uses exact payload filters and maybeSingle", async () => {
  const card = sampleCard();
  const values = generatedDailyCardValues(card);
  const state: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [{
      id: CARD,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
      status: "draft",
      title: "old",
    }],
    references: [],
    ideas: [],
  };
  const result = await updateExistingDraftDailyCard(
    fakeAdmin(state) as never,
    values,
    {
      id: CARD,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
    },
  );
  assertEquals(result.error, null);
  assertEquals(result.data, { id: CARD, scheduled_date: "2026-06-08" });
  assertEquals(state.dailyCards[0].title, "Generated title");
  const op = state.ops[0];
  assertEquals(op.table, "daily_cards");
  assertEquals(op.operation, "update");
  assertEquals(op.values, values);
  assertEquals(op.selectColumns, DRAFT_DAILY_CARD_UPDATE_SELECT);
  assertEquals(op.terminal, "maybeSingle");
  assertEquals(op.filters, {
    id: CARD,
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_plan_id: PLAN,
    scheduled_date: "2026-06-08",
    status: "draft",
  });
  assertEquals(op.filterOrder, [
    "id",
    "workspace_id",
    "creator_id",
    "weekly_plan_id",
    "scheduled_date",
    "status",
  ]);

  const missingState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [],
    references: [],
    ideas: [],
  };
  const missing = await updateExistingDraftDailyCard(
    fakeAdmin(missingState) as never,
    values,
    {
      id: CARD,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
    },
  );
  assertEquals(missing.data, null);
  assertEquals(missing.error, null);

  const failState: FakeState = {
    ops: [],
    weeklyPlans: [],
    dailyCards: [{
      id: CARD,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
      status: "draft",
    }],
    references: [],
    ideas: [],
    writeError: { message: "update failed" },
  };
  const failed = await updateExistingDraftDailyCard(
    fakeAdmin(failState) as never,
    values,
    {
      id: CARD,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      weekly_plan_id: PLAN,
      scheduled_date: "2026-06-08",
    },
  );
  assertEquals(failed.data, null);
  assertEquals((failed.error as { message: string }).message, "update failed");
});
