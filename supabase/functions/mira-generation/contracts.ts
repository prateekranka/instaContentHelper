import { z } from "npm:zod@4.6.7";
const text = z.string().max(12000);
const nonempty = z.string().min(1).max(5000);
const id = z.uuid();
export const profileSchema = z.object({
  name: text,
  themes: text,
  audience: text,
  language: z.enum(["English", "Hindi", "Hinglish"]),
  writingSystem: z.enum(["Devanagari", "Romanised"]),
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
export const shotSchema = z.object({
  id,
  purpose: nonempty,
  editedSeconds: z.number().int().positive().max(90),
  recordingSeconds: z.number().int().positive().max(180),
  location: nonempty,
  props: text,
  placement: nonempty,
  action: nonempty,
  words: text,
  voiceover: z.boolean(),
  onScreenText: text,
  simplerAlternative: text,
}).strict();
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
export const inputSchema = z.object({
  operation: z.enum([
    "ideas",
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
  idea: ideaSchema.nullish(),
  script: scriptSchema.nullish(),
  storyboard: boardSchema.nullish(),
  brief: briefSchema.nullish(),
  targetShotID: id.nullish(),
}).strict();
export type MiraInput = z.infer<typeof inputSchema>;
export const outputSchema = z.object({
  ideas: z.array(ideaSchema).length(3).optional(),
  script: scriptSchema.optional(),
  storyboard: boardSchema.optional(),
  brief: briefSchema.optional(),
  conflicts: z.array(nonempty).max(20),
}).strict();
export type MiraOutput = z.infer<typeof outputSchema>;
export function validateOutput(value: unknown, input: MiraInput): MiraOutput {
  const output = outputSchema.parse(value), op = input.operation;
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
      (script!.hook + " " + script!.spoken).trim().split(/\s+/u).length /
          script!.durationSeconds > 3.4
    ) fail("speech_density");
  } else if (op === "requirements") {
    const brief = output.brief;
    if (!brief || brief.original !== input.brief?.original) {
      fail("brief_source");
    }
    for (const r of brief!.requirements) {
      if (
        !brief!.original.includes(r.excerpt) ||
        !brief!.original.includes(r.value)
      ) fail("invented_excerpt_or_value");
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
    if (
      /(cure|treat|reverse|guarantee).{0,60}(diabet|cancer|disease|weight|health)/iu
        .test(brief!.original)
    ) {
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
    const shots = board!.shots;
    if (
      new Set(shots.map((x) => x.id)).size !== shots.length ||
      shots.some((x) => x.recordingSeconds < x.editedSeconds)
    ) fail("shot_identity_or_duration");
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
        m.shotIDs.some((id) => !shots.some((x) => x.id === id))
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
    if (op === "reviseShot") {
      if (
        !input.targetShotID ||
        !input.storyboard?.shots.some((x) => x.id === input.targetShotID)
      ) fail("invalid_shot_target");
      for (
        const previous of input.storyboard!.shots.filter((x) =>
          x.id !== input.targetShotID
        )
      ) {
        if (
          !shots.some((x) => JSON.stringify(x) === JSON.stringify(previous))
        ) fail("unrelated_shot_changed");
      }
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
