import { z } from "npm:zod@4.6.7";
import {
  brandDocSchema,
  checklistSchema,
  hasUnsupportedHealthClaim,
  hasVerbatimSource,
  invalidOutput,
  isPhaseEInput,
  languageFields,
  phaseEInputSchemas,
  type PhaseEOutput,
  phaseEOutputSchemas,
  validatePhaseEOutput,
} from "./phase-e.ts";
const text = z.string().max(12000);
const nonempty = z.string().min(1).max(5000);
const id = z.uuid();
export const profileSchema = z.object({
  name: text,
  themes: text,
  audience: text,
  ...languageFields,
  tone: text,
  avoid: text,
  samples: text,
  solo: z.boolean(),
}).strict();
export const constraintsSchema = z.object({
  filmingMinutes: z.number().int().min(1).max(180),
  location: nonempty,
  style: z.enum(["Talking to camera", "Voiceover", "Either"]),
  reelSeconds: z.number().int().min(10).max(90),
  equipment: nonempty,
}).strict();
export const ideaSchema = z.object({
  id,
  title: nonempty,
  hook: nonempty,
  visual: nonempty,
  fit: nonempty,
  filmingMinutes: z.number().int().positive(),
  setup: nonempty,
}).strict();
export const scriptSchema = z.object({
  id,
  hook: nonempty,
  spoken: nonempty,
  caption: nonempty,
  durationSeconds: z.number().int().min(5).max(180),
  language: nonempty,
}).strict();
export const frameTypeSchema = z.enum([
  "face",
  "headShoulders",
  "halfBody",
  "fullBody",
  "side",
  "closeUp",
]);
export const shotSchema = z.object({
  id,
  purpose: nonempty,
  editedSeconds: z.number().int().positive().max(90),
  recordingSeconds: z.number().int().positive().max(180),
  location: nonempty,
  props: text,
  placement: nonempty,
  distance: z.string().trim().min(1).max(500),
  framing: z.string().trim().min(1).max(500),
  frameType: frameTypeSchema,
  action: nonempty,
  words: text,
  voiceover: z.boolean(),
  onScreenText: text,
  simplerAlternative: text,
}).strict();
const savedShotSchema = shotSchema.extend({
  distance: text.optional(),
  framing: text.optional(),
  frameType: frameTypeSchema.optional(),
});
export type MiraShot = z.infer<typeof savedShotSchema>;
export const requirementSchema = z.object({
  id,
  kind: nonempty,
  value: nonempty,
  excerpt: nonempty,
}).strict();
export const briefSchema = z.object({
  original: text,
  requirements: z.array(requirementSchema).max(40),
  unresolved: z.array(nonempty).max(30),
  confirmed: z.boolean(),
  revision: z.number().int().nonnegative(),
}).strict();
export const boardSchema = z.object({
  id,
  sourceScriptID: id,
  requirementsRevision: z.number().int().nonnegative(),
  shots: z.array(shotSchema).min(1).max(16),
  mappings: z.array(
    z.object({ requirementID: id, shotIDs: z.array(id), scriptExcerpt: text })
      .strict(),
  ).max(40),
}).strict();
const legacyInputSchema = z.object({
  operation: z.enum([
    "ideas",
    "todayIdea",
    "script",
    "storyboard",
    "reviseScript",
    "reviseShot",
    "reviseStoryboard",
    "requirements",
  ]),
  profile: profileSchema,
  constraints: constraintsSchema,
  request: text,
  recentIdeas: z.array(text).max(30),
  angle: nonempty.optional(),
  idea: ideaSchema.nullish(),
  script: scriptSchema.nullish(),
  storyboard: boardSchema.extend({
    shots: z.array(savedShotSchema).min(1).max(16),
  }).nullish(),
  brief: briefSchema.nullish(),
  targetShotID: id.nullish(),
}).strict();
const pickIdeaInputSchema = legacyInputSchema.pick({
  profile: true,
  constraints: true,
  request: true,
  recentIdeas: true,
  angle: true,
}).extend({
  operation: z.literal("pickIdea"),
  brandDoc: brandDocSchema.optional(),
  bestPostPatterns: z.array(z.string().trim().min(1).max(240)).max(8)
    .optional(),
  dealChecklist: z.object({
    revision: z.number().int().nonnegative(),
    items: checklistSchema,
  }).strict().optional(),
  avoid: z.array(z.string().trim().min(1).max(240)).max(30),
}).strict();
export const inputSchema = z.union([
  legacyInputSchema,
  pickIdeaInputSchema,
  ...Object.values(phaseEInputSchemas),
]);
export const operationSchema = z.union([
  legacyInputSchema.shape.operation,
  pickIdeaInputSchema.shape.operation,
  ...Object.values(phaseEInputSchemas).map((schema) => schema.shape.operation),
]);
export type MiraInput = z.infer<typeof inputSchema>;
export const outputSchema = z.object({
  ideas: z.array(ideaSchema).length(3).optional(),
  script: scriptSchema.optional(),
  storyboard: boardSchema.optional(),
  brief: briefSchema.optional(),
  conflicts: z.array(nonempty).max(20),
}).strict();
const reviseShotOutputSchema = outputSchema.extend({
  storyboard: boardSchema.extend({
    shots: z.array(shotSchema).length(1),
  })
    .optional(),
});
const todayIdeaOutputSchema = z.object({
  ideas: z.array(ideaSchema).length(1),
  script: scriptSchema,
  storyboard: boardSchema.extend({ shots: z.array(shotSchema).min(3).max(5) }),
  conflicts: z.array(nonempty).length(0),
}).strict();
const pickIdeaOutputSchema = todayIdeaOutputSchema.extend({
  reason: z.string().trim().min(1).max(240).regex(/^[^\r\n]+$/u),
});
export const todaySteps = [
  {
    field: "ideas",
    step: "idea_ready",
    schema: todayIdeaOutputSchema.shape.ideas,
  },
  {
    field: "script",
    step: "script_ready",
    schema: todayIdeaOutputSchema.shape.script,
  },
  {
    field: "storyboard",
    step: "storyboard_ready",
    schema: todayIdeaOutputSchema.shape.storyboard,
  },
] as const;
export type TodayStep = typeof todaySteps[number]["step"];

export function providerOutputSchema(operation: MiraInput["operation"]) {
  if (operation === "todayIdea") return todayIdeaOutputSchema;
  if (operation === "pickIdea") return pickIdeaOutputSchema;
  if (operation in phaseEOutputSchemas) {
    return phaseEOutputSchemas[operation as keyof typeof phaseEOutputSchemas];
  }
  return operation === "reviseShot" ? reviseShotOutputSchema : outputSchema;
}
type LegacyOutput = Omit<z.infer<typeof outputSchema>, "storyboard"> & {
  storyboard?: NonNullable<z.infer<typeof legacyInputSchema>["storyboard"]>;
};
export type MiraOutput =
  | LegacyOutput
  | z.infer<typeof pickIdeaOutputSchema>
  | PhaseEOutput;

function normalizeDialogue(text: string): string {
  return text.replace(/[‘’]/gu, "'").replace(/[“”]/gu, '"')
    .replace(/\s+/gu, " ").trim();
}

function scriptDialogue(script: z.infer<typeof scriptSchema>): string {
  const hook = normalizeDialogue(script.hook);
  const spoken = normalizeDialogue(script.spoken);
  return spoken.startsWith(hook) ? spoken : `${hook} ${spoken}`.trim();
}

export function validateOutput(value: unknown, input: MiraInput): MiraOutput {
  if (isPhaseEInput(input)) return validatePhaseEOutput(value, input);
  const op = input.operation;
  if (op === "todayIdea" || op === "pickIdea") {
    const output =
      (op === "pickIdea" ? pickIdeaOutputSchema : todayIdeaOutputSchema)
        .parse(value);
    const idea = output.ideas[0];
    if (input.operation === "pickIdea" && idea.hook !== output.script.hook) {
      invalidOutput("pick_script_hook_mismatch");
    }
    const avoid = input.operation === "pickIdea"
      ? [...input.recentIdeas, ...input.avoid]
      : input.recentIdeas;
    if (
      avoid.some((title) =>
        title.trim().toLowerCase() === idea.title.trim().toLowerCase()
      )
    ) {
      throw Error("invalid_output:repeated_idea");
    }
    if (idea.filmingMinutes > input.constraints.filmingMinutes) {
      throw Error("invalid_output:filming_time");
    }
    const brief = input.operation !== "pickIdea"
      ? input.brief
      : input.dealChecklist && {
        original: "",
        requirements: input.dealChecklist.items.map((
          { id, kind, text, excerpt },
        ) => ({
          id,
          kind,
          value: text,
          excerpt,
        })),
        unresolved: [],
        confirmed: true,
        revision: input.dealChecklist.revision,
      };
    const context = {
      profile: input.profile,
      constraints: input.constraints,
      request: input.request,
      recentIdeas: input.recentIdeas,
      brief,
    };
    validateOutput({ script: output.script, conflicts: [] }, {
      ...context,
      operation: "script",
    });
    validateOutput({ storyboard: output.storyboard, conflicts: [] }, {
      ...context,
      operation: "storyboard",
      script: output.script,
    });
    return output;
  }
  const output: LegacyOutput =
    (op === "reviseShot" ? reviseShotOutputSchema : outputSchema)
      .parse(value);
  const fail = (message: string): never => {
    throw new Error("invalid_output:" + message);
  };
  if (
    output.conflicts.length && !output.ideas && !output.script &&
    !output.storyboard && !output.brief
  ) return output;
  if (op === "ideas") {
    if (
      !output.ideas || new Set(output.ideas.map((x) =>
          x.title.toLowerCase()
        )).size !== 3 ||
      new Set(output.ideas.map((x) => x.id)).size !== 3
    ) fail("three_distinct_ideas");
    if (
      output.ideas!.some((x) =>
        x.filmingMinutes > input.constraints.filmingMinutes
      )
    ) fail("filming_time");
  } else if (op === "script" || op === "reviseScript") {
    const script = output.script;
    if (!script) fail("missing_script");
    if (
      script!.language !== input.profile.language ||
      script!.durationSeconds > input.constraints.reelSeconds + 5
    ) fail("language_or_duration");
    if (
      scriptDialogue(script!).split(" ").length /
          script!.durationSeconds > 3.4
    ) fail("speech_density");
  } else if (op === "requirements") {
    const brief = output.brief;
    if (!brief || brief.original !== input.brief?.original) {
      fail("brief_source");
    }
    for (const r of brief!.requirements) {
      if (!hasVerbatimSource(brief!.original, [r.excerpt, r.value])) {
        fail("invented_excerpt_or_value");
      }
    }
    if (
      /\bcode\b/iu.test(brief!.original) &&
      !brief!.requirements.some((r) => /code/iu.test(r.kind)) &&
      !brief!.unresolved.some((gap) => /code/iu.test(gap))
    ) {
      brief!.unresolved.push(
        "A code is mentioned but no explicit code was extracted. Confirm it with the brand.",
      );
    }
    if (hasUnsupportedHealthClaim(brief!.original)) {
      brief!.unresolved.push(
        "Unsupported health claim: correct the brief or obtain substantiation before using this claim.",
      );
    }
    brief!.confirmed = false;
  } else {
    const board = output.storyboard;
    if (!board || !input.script) fail("missing_storyboard_source");
    if (
      board!.sourceScriptID !== input.script!.id ||
      board!.requirementsRevision !== (input.brief?.revision ?? 0)
    ) fail("source_revision");
    if (op === "reviseShot") {
      const previous = input.storyboard;
      const revised = board!.shots[0];
      const target = input.targetShotID?.toLowerCase();
      if (!previous?.shots.some((shot) => shot.id.toLowerCase() === target)) {
        fail("invalid_shot_target");
      }
      if (revised.id.toLowerCase() !== target) fail("wrong_shot_target");
      board!.shots = previous!.shots.map((shot) =>
        shot.id.toLowerCase() === target ? { ...revised, id: shot.id } : shot
      );
    }
    const shots = board!.shots;
    if (
      new Set(shots.map((x) => x.id.toLowerCase())).size !== shots.length ||
      shots.some((x) => x.recordingSeconds < x.editedSeconds)
    ) fail("shot_identity_or_duration");
    const dialogue = shots.map((shot) => normalizeDialogue(shot.words))
      .filter(Boolean).join(" ");
    if (dialogue !== scriptDialogue(input.script!)) {
      fail("shot_words_script_coverage");
    }
    if (
      Math.abs(
          shots.reduce((a, x) => a + x.editedSeconds, 0) -
            input.script!.durationSeconds,
        ) > 5 ||
      shots.reduce((a, x) => a + x.recordingSeconds, 0) >
        input.constraints.filmingMinutes * 60
    ) fail("total_duration");
    const requirements = input.brief?.requirements ?? [];
    for (const m of board!.mappings) {
      if (
        !requirements.some((x) => x.id === m.requirementID) ||
        m.shotIDs.some((id) =>
          !shots.some((x) => x.id.toLowerCase() === id.toLowerCase())
        )
      ) fail("unknown_mapping");
      if (
        m.scriptExcerpt &&
        ![input.script!.hook, input.script!.spoken, input.script!.caption].some(
          (s) => s.includes(m.scriptExcerpt),
        )
      ) fail("invented_script_mapping");
    }
    for (const r of requirements) {
      if (
        !board!.mappings.some((x) =>
          x.requirementID === r.id && (x.shotIDs.length || x.scriptExcerpt)
        ) && !output.conflicts.length
      ) fail("unmapped_requirement");
    }
  }
  const expected = op === "ideas"
    ? "ideas"
    : op === "requirements"
    ? "brief"
    : op === "script" || op === "reviseScript"
    ? "script"
    : "storyboard";
  if (
    ["ideas", "script", "storyboard", "brief"].some((key) =>
      key !== expected && key in output
    )
  ) fail("unexpected_artifact");
  return output;
}
