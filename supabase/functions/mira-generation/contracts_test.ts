import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { inputSchema, type MiraInput, validateOutput } from "./contracts.ts";
import { handleMira } from "./index.ts";
import { generate } from "./provider.ts";
const uid = () => crypto.randomUUID();
function input(): MiraInput {
  return inputSchema.parse({
    operation: "ideas",
    profile: {
      name: "",
      themes: "Simple meals",
      audience: "",
      language: "English",
      writingSystem: "Romanised",
      tone: "Everyday",
      avoid: "Health promises",
      samples: "",
      solo: true,
    },
    constraints: {
      filmingMinutes: 10,
      location: "Home",
      style: "Either",
      reelSeconds: 30,
      equipment: "Phone, no tripod",
    },
    request: "Hindi request, English output",
    recentIdeas: [],
  });
}
const idea = (title: string) => ({
  id: uid(),
  title,
  hook: "A small routine",
  visual: "One familiar action",
  fit: "One home setup",
  filmingMinutes: 10,
  setup: "Phone on a stable shelf",
});

Deno.test("Mira unresolved codes and unsupported health claims require a choice without a provider call", async () => {
  const request = input();
  request.operation = "script";
  request.brief = {
    original: "Code to be supplied",
    requirements: [],
    unresolved: ["Code has not been supplied"],
    confirmed: true,
    revision: 1,
  };
  const env = { get: () => undefined };
  const noFetch: typeof fetch = () => {
    throw Error("A provider must not be called for this unresolved brief");
  };
  const missing = await generate(request, env, noFetch);
  assert(missing.conflicts.length > 0);
  request.brief.unresolved = ["Unsupported health claim: cures diabetes"];
  const health = await generate(request, env, noFetch);
  assert(health.conflicts.length > 0);
});
Deno.test("Mira contracts reject duplicate ideas, impossible timing, wrong language and extra artifacts", () => {
  const request = input();
  validateOutput({
    ideas: [idea("Breakfast"), idea("Mobility"), idea("Preparation")],
    conflicts: [],
  }, request);
  assertThrows(() =>
    validateOutput({
      ideas: [idea("Same"), idea("Same"), idea("Same")],
      conflicts: [],
    }, request)
  );
  assertThrows(() =>
    validateOutput({
      ideas: [{ ...idea("A"), filmingMinutes: 45 }, idea("B"), idea("C")],
      conflicts: [],
    }, request)
  );
  request.operation = "script";
  const script = {
    id: uid(),
    hook: "One thing",
    spoken: "I keep this simple.",
    caption: "Today at home.",
    durationSeconds: 30,
    language: "Hindi",
  };
  assertThrows(() => validateOutput({ script, conflicts: [] }, request));
  assertThrows(() =>
    validateOutput({
      script: { ...script, language: "English", durationSeconds: 0 },
      conflicts: [],
    }, request)
  );
  assertThrows(() =>
    validateOutput({
      script: { ...script, language: "English" },
      ideas: [idea("A"), idea("B"), idea("C")],
      conflicts: [],
    }, request)
  );
});
Deno.test("Mira brand extraction preserves missing fields and rejects invented source evidence", () => {
  const request = input();
  request.operation = "requirements";
  request.brief = {
    original: "Show the bottle. Code to be provided.",
    requirements: [],
    unresolved: [],
    confirmed: false,
    revision: 0,
  };
  const brief = {
    ...request.brief,
    requirements: [{
      id: uid(),
      kind: "visual",
      value: "Show the bottle",
      excerpt: "Show the bottle.",
    }],
    unresolved: ["Code has not been supplied"],
  };
  assertEquals(
    validateOutput({ brief, conflicts: [] }, request).brief?.unresolved.length,
    1,
  );
  assertThrows(() =>
    validateOutput({
      brief: {
        ...brief,
        requirements: [{
          id: uid(),
          kind: "code",
          value: "SAVE20",
          excerpt: "SAVE20",
        }],
      },
      conflicts: [],
    }, request)
  );
});
Deno.test("Mira storyboard validates source, mappings, durations and unchanged shot revision boundaries", () => {
  const request = input();
  request.operation = "reviseShot";
  request.script = {
    id: uid(),
    hook: "Today",
    spoken: "One everyday thing.",
    caption: "My routine",
    durationSeconds: 30,
    language: "English",
  };
  const shot = {
    id: uid(),
    purpose: "Opening",
    editedSeconds: 15,
    recordingSeconds: 25,
    location: "Home",
    props: "Phone",
    placement: "Stable shelf at eye level",
    action: "Speak to camera",
    words: "Today",
    voiceover: false,
    onScreenText: "",
    simplerAlternative: "Sit at a table",
  };
  const second = { ...shot, id: uid(), purpose: "Show routine" };
  const board = {
    id: uid(),
    sourceScriptID: request.script.id,
    requirementsRevision: 0,
    shots: [shot, second],
    mappings: [],
  };
  request.storyboard = board;
  request.targetShotID = shot.id;
  validateOutput({
    storyboard: {
      ...board,
      shots: [{ ...shot, placement: "Between heavy books on a table" }, second],
    },
    conflicts: [],
  }, request);
  assertThrows(() =>
    validateOutput({
      storyboard: { ...board, sourceScriptID: uid() },
      conflicts: [],
    }, request)
  );
  assertThrows(() =>
    validateOutput({
      storyboard: {
        ...board,
        shots: [shot, { ...second, action: "Unrelated edit" }],
      },
      conflicts: [],
    }, request)
  );
  assertThrows(() =>
    validateOutput({
      storyboard: {
        ...board,
        mappings: [{
          requirementID: uid(),
          shotIDs: [uid()],
          scriptExcerpt: "Made up words",
        }],
      },
      conflicts: [],
    }, request)
  );
});

Deno.test("Mira endpoint authenticates, scopes jobs, reconciles lost acknowledgements and cancels durably", async () => {
  // deno-lint-ignore no-explicit-any
  const rows: any[] = [];
  const member = uid(), workspace = uid(), creator = uid();
  let calls = 0;
  let allowed = true;
  class Query {
    filters: Record<string, unknown> = {};
    updateValue: Record<string, unknown> | undefined;
    statuses: string[] | undefined;
    constructor(public table: string) {}
    select() {
      return this;
    }
    eq(key: string, value: unknown) {
      this.filters[key] = value;
      return this;
    }
    update(value: Record<string, unknown>) {
      this.updateValue = value;
      return this;
    }
    in(_key: string, values: string[]) {
      this.statuses = values;
      return this;
    }
    result() {
      const source = this.table === "creators"
        ? (allowed ? [{ id: creator, workspace_id: workspace }] : [])
        : rows;
      const row = source.find((r) =>
        Object.entries(this.filters).every(([key, value]) =>
          r[key] === value
        ) && (!this.statuses || this.statuses.includes(r.status))
      );
      if (row && this.updateValue) Object.assign(row, this.updateValue);
      return { data: row ?? null, error: null };
    }
    maybeSingle() {
      return Promise.resolve(this.result());
    }
    then(resolve: (value: unknown) => void) {
      resolve(this.result());
    }
  }
  const admin = {
    from: (name: string) => new Query(name),
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "mira_enqueue") {
        const old = rows.find((x) => x.id === args.p_id);
        if (old) return { data: old, error: null };
        const row = {
          id: args.p_id,
          workspace_id: args.p_workspace,
          creator_id: args.p_creator,
          member_id: args.p_member,
          input_revision: args.p_revision,
          input: args.p_input,
          status: "queued",
          attempts: 0,
        };
        rows.push(row);
        return { data: row, error: null };
      }
      const row = rows.find((x) => x.id === args.p_id && x.status === "queued");
      if (!row) return { data: [], error: null };
      Object.assign(row, {
        status: "running",
        attempts: row.attempts + 1,
        lease_id: uid(),
      });
      return { data: [row], error: null };
    },
  };
  const env = { get: (_name: string) => "configured" };
  const verify = async () => ({
    session: {
      deviceInstallationID: uid(),
      workspaceID: workspace,
      memberID: member,
      role: "creator",
    },
  });
  const work: Promise<unknown>[] = [];
  const deps = {
    env,
    admin,
    verify,
    generate: async () => {
      calls++;
      return { ideas: [idea("A"), idea("B"), idea("C")], conflicts: [] };
    },
    defer: (p: Promise<unknown>) => {
      work.push(p);
    },
  };
  const id = uid(),
    body = {
      action: "start",
      id,
      creatorID: creator,
      inputRevision: 1,
      input: input(),
      consentVersion: 1,
    };
  const req = (body: unknown) =>
    new Request("https://example.test", {
      method: "POST",
      body: JSON.stringify(body),
    });
  const denied = await handleMira(req(body), {
    ...deps,
    verify: async () => ({ response: new Response("", { status: 401 }) }),
  });
  assertEquals(denied.status, 401);
  assertEquals(rows.length, 0);
  const first = await handleMira(req(body), deps);
  assertEquals(first.status, 200);
  await Promise.all(work);
  assertEquals(calls, 1);
  await handleMira(req(body), deps);
  assertEquals(rows.length, 1);
  assertEquals(calls, 1);
  const status = await handleMira(
    req({ action: "status", id, creatorID: creator }),
    deps,
  );
  assertEquals((await status.json()).job.state, "succeeded");
  rows[0].member_id = uid();
  assertEquals(
    (await handleMira(req({ action: "status", id, creatorID: creator }), deps))
      .status,
    404,
  );
  rows[0].member_id = member;
  allowed = false;
  assertEquals(
    (await handleMira(req({ action: "status", id, creatorID: creator }), deps))
      .status,
    404,
  );
  allowed = true;
  rows[0].status = "running";
  const cancelled = await handleMira(
    req({ action: "cancel", id, creatorID: creator }),
    deps,
  );
  assertEquals((await cancelled.json()).job.state, "cancelled");
  assert(rows[0].status === "cancelled");
});
