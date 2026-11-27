import { z } from "npm:zod@4.6.7";

const line = z.string().trim().min(1).max(240).regex(/^[^\r\n]+$/u);
const exact = z.string().min(1).max(1000).refine((value) =>
  value.trim() !== ""
);
const id = z.uuid();
const blank = z.literal("");
const count = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
export const languageFields = {
  language: z.enum(["English", "Hindi", "Hinglish"]),
  writingSystem: z.enum(["Devanagari", "Romanised"]),
};

export const brandDocSchema = z.object({
  pillars: z.array(line).min(3).max(5),
  tone: line,
  audience: line,
  dos: z.array(line).max(6),
  donts: z.array(line).max(6),
  goals: z.array(line).min(1).max(3),
}).strict();

const postSchema = z.object({
  caption: z.string().max(2200),
  views: count.optional(),
  reach: count.optional(),
  likes: count.optional(),
  comments: count.optional(),
  saves: count.optional(),
  shares: count.optional(),
}).strict();

const snapshotSchema = z.object({
  followers: count.optional(),
  reach7d: count.optional(),
  saves7d: count.optional(),
  topPosts: z.array(postSchema).max(5).optional(),
}).strict();

const itemKind = z.enum(["caption", "onScreenText", "script", "shot", "other"]);
const textField = z.enum(["caption", "onScreenText", "script"]);
const fixField = z.enum(["caption", "onScreenText"]);
const checklistItem = z.object({
  id,
  kind: itemKind,
  text: line,
  excerpt: exact,
  requiredText: exact.optional(),
}).strict();
function hasRequiredText(source: string, required: string): boolean {
  const escaped = required.replace(/[.*+?^$(){}|[\]\\]/g, "\\$&");
  const word = "[\\p{L}\\p{M}\\p{N}_]";
  return new RegExp("(?<!" + word + ")" + escaped + "(?!" + word + ")", "u")
    .test(source);
}

export const checklistSchema = z.array(checklistItem).min(1).max(40).refine(
  (items) =>
    new Set(items.map((item) => item.id)).size === items.length &&
    items.every((item) =>
      !item.requiredText || hasRequiredText(item.excerpt, item.requiredText)
    ),
  "Duplicate checklist ID or required text outside its source excerpt",
);

const openItems = z.array(z.object({ id, title: line }).strict()).max(20)
  .refine((items) =>
    new Set(items.map((item) => item.id)).size === items.length
  );

export const phaseEInputSchemas = {
  brandDoc: z.object({
    operation: z.literal("brandDoc"),
    ...languageFields,
    answers: z.string().min(1).max(8000).refine((value) => value.trim() !== ""),
    instagramSummary: snapshotSchema.pick({ followers: true, topPosts: true })
      .optional(),
    oldBrandDoc: brandDocSchema.optional(),
  }).strict(),
  dealBrief: z.object({
    operation: z.literal("dealBrief"),
    ...languageFields,
    briefText: z.string().min(1).max(12000).refine((value) =>
      value.trim() !== ""
    ),
  }).strict(),
  briefCheck: z.object({
    operation: z.literal("briefCheck"),
    ...languageFields,
    checklist: checklistSchema,
    caption: z.string().max(4400),
    onScreenText: z.string().max(6000),
    script: z.string().max(6000),
    shots: z.array(line).max(24),
  }).strict(),
  brandNote: z.object({
    operation: z.literal("brandNote"),
    ...languageFields,
    brand: line,
    itemsDone: z.array(line).max(40),
    postLink: z.url({ protocol: /^https$/ }).max(1000).optional(),
  }).strict(),
  dailyNote: z.object({
    operation: z.literal("dailyNote"),
    ...languageFields,
    snapshots: z.array(snapshotSchema).max(2),
    openReels: openItems,
    openDeals: openItems,
  }).strict(),
};

const dealSchema = z.object({
  brand: z.union([blank, exact]),
  fee: z.union([blank, exact]),
  deadline: z.union([blank, z.iso.date()]),
  deadlineExcerpt: z.union([blank, exact]),
  checklist: checklistSchema.or(z.tuple([])),
  disclosures: z.array(exact).max(20),
  codes: z.array(exact).max(20),
  unresolved: z.array(line).max(30),
}).strict();

const checksSchema = z.array(z.discriminatedUnion("status", [
  z.object({
    itemID: id,
    status: z.literal("met"),
    evidence: z.object({ field: textField, excerpt: exact }).strict(),
  }).strict(),
  z.object({ itemID: id, status: z.literal("missing") }).strict(),
  z.object({
    itemID: id,
    status: z.literal("can-fix"),
    fix: z.object({ field: fixField, text: exact }).strict(),
  }).strict(),
])).min(1).max(40);

const actionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("makeIdea") }).strict(),
  z.object({ type: z.literal("continueReel"), id }).strict(),
  z.object({ type: z.literal("openDeal"), id }).strict(),
  z.object({ type: z.literal("none") }).strict(),
]);

const dailySchema = z.object({
  noticed: line,
  action: actionSchema,
  buttonText: z.union([blank, line]),
}).strict();

export const phaseEOutputSchemas = {
  brandDoc: z.object({ brandDoc: brandDocSchema }).strict(),
  dealBrief: z.object({ deal: dealSchema }).strict(),
  briefCheck: z.object({ checks: checksSchema }).strict(),
  brandNote: z.object({ message: z.string().trim().min(1).max(600) }).strict(),
  dailyNote: z.object({ dailyNote: dailySchema }).strict(),
};

type PhaseEOperation = keyof typeof phaseEInputSchemas;
type PhaseEInput = z.infer<(typeof phaseEInputSchemas)[PhaseEOperation]>;
export type PhaseEOutput = z.infer<
  (typeof phaseEOutputSchemas)[PhaseEOperation]
>;

export function isPhaseEInput<T extends { operation: string }>(
  input: T,
): input is Extract<T, PhaseEInput> {
  return Object.hasOwn(phaseEInputSchemas, input.operation);
}

export function invalidOutput(reason: string): never {
  throw Error("invalid_output:" + reason);
}

export function hasVerbatimSource(source: string, values: string[]): boolean {
  return values.every((value) => source.includes(value));
}

export function hasUnsupportedHealthClaim(source: string): boolean {
  return /(cure|treat|reverse|guarantee).{0,60}(diabet|cancer|disease|weight|health)/iu
    .test(source);
}

const months = [
  ["january", "jan", "जनवरी"],
  ["february", "feb", "फ़रवरी", "फरवरी"],
  ["march", "mar", "मार्च"],
  ["april", "apr", "अप्रैल"],
  ["may", "मई"],
  ["june", "jun", "जून"],
  ["july", "jul", "जुलाई"],
  ["august", "aug", "अगस्त"],
  ["september", "sep", "sept", "सितंबर", "सितम्बर"],
  ["october", "oct", "अक्टूबर", "अक्तूबर"],
  ["november", "nov", "नवंबर", "नवम्बर"],
  ["december", "dec", "दिसंबर", "दिसम्बर"],
];

function asciiDigits(text: string): string {
  return text.normalize("NFKC").replace(
    /[०-९]/gu,
    (digit) => String(digit.codePointAt(0)! - 0x0966),
  );
}

function sourceDates(source: string): Set<string> {
  const text = asciiDigits(source);
  const dates = new Set([...text.matchAll(/\b\d{4}-\d{2}-\d{2}\b/gu)].map(
    (match) => match[0],
  ));
  const add = (year: string, month: string | number, day: string) => {
    const monthNumber = typeof month === "number"
      ? month
      : months.findIndex((names) => names.includes(month.toLowerCase())) + 1;
    if (monthNumber >= 1 && monthNumber <= 12) {
      dates.add(
        [year, String(monthNumber).padStart(2, "0"), day.padStart(2, "0")].join(
          "-",
        ),
      );
    }
  };
  for (
    const [, day, month, year] of text.matchAll(
      /\b(\d{1,2})(?:st|nd|rd|th)?\s+([\p{L}\p{M}]+)\.?\s+(\d{4})\b/giu,
    )
  ) {
    add(year, month, day);
  }
  for (
    const [, month, day, year] of text.matchAll(
      /([\p{L}\p{M}]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/giu,
    )
  ) {
    add(year, month, day);
  }
  for (
    const [, first, , second, year] of text.matchAll(
      /\b(\d{1,2})([/.\-])(\d{1,2})\2(\d{4})\b/gu,
    )
  ) {
    if (Number(first) > 12 || Number(first) === Number(second)) {
      add(year, Number(second), first);
    } else if (Number(second) > 12) {
      add(year, Number(first), second);
    }
  }
  return dates;
}

function checkDeal(deal: z.infer<typeof dealSchema>, source: string) {
  const quotes = [
    deal.brand,
    deal.fee,
    deal.deadlineExcerpt,
    ...deal.disclosures,
    ...deal.codes,
    ...deal.checklist.map((item) => item.excerpt),
  ];
  if (
    !hasVerbatimSource(source, quotes) ||
    deal.codes.some((code) => !hasRequiredText(source, code))
  ) {
    invalidOutput("invented_brief_excerpt_or_value");
  }
  if (deal.deadline) {
    const dates = sourceDates(deal.deadlineExcerpt);
    if (dates.size !== 1 || !dates.has(deal.deadline)) {
      invalidOutput("deadline_not_supported_by_source");
    }
  } else if (!deal.unresolved.length) {
    invalidOutput("missing_deadline_note");
  }
  if (
    /\bcode\b/iu.test(source) && !deal.codes.length && !deal.unresolved.length
  ) {
    invalidOutput("missing_code_note");
  }
  if (hasUnsupportedHealthClaim(source) && !deal.unresolved.length) {
    invalidOutput("missing_health_claim_note");
  }
}

function checkBrief(
  checks: z.infer<typeof checksSchema>,
  input: z.infer<typeof phaseEInputSchemas.briefCheck>,
) {
  const items = new Map(input.checklist.map((item) => [item.id, item]));
  for (const check of checks) {
    const item = items.get(check.itemID);
    if (!item) invalidOutput("unknown_or_duplicate_check");
    items.delete(check.itemID);
    if (
      check.status === "met" && (item.kind !== check.evidence.field ||
        !item.requiredText ||
        !hasRequiredText(check.evidence.excerpt, item.requiredText) ||
        !hasRequiredText(input[check.evidence.field], check.evidence.excerpt))
    ) invalidOutput("unverified_check_evidence");
    if (
      check.status === "can-fix" && (item.kind !== check.fix.field ||
        (item.requiredText &&
          !hasRequiredText(check.fix.text, item.requiredText)))
    ) {
      invalidOutput("unsupported_check_fix");
    }
  }
  if (items.size) invalidOutput("missing_check");
}

function numberMentions(text: string) {
  return (asciiDigits(text).match(/[-−]?\d+(?:,\d{2,3})*(?:\.\d+)?[%％]?/gu) ??
    [])
    .map((number) => number.replaceAll(",", ""));
}

function snapshotNumbers(snapshots: z.infer<typeof snapshotSchema>[]) {
  const values = new Set<string>();
  for (const { topPosts = [], ...account } of snapshots) {
    for (const value of Object.values(account)) values.add(String(value));
    for (const { caption: _caption, ...metrics } of topPosts) {
      for (const value of Object.values(metrics)) values.add(String(value));
    }
  }
  return values;
}

export function validatePhaseEOutput(
  value: unknown,
  input: PhaseEInput,
): PhaseEOutput {
  switch (input.operation) {
    case "brandDoc": {
      const output = phaseEOutputSchemas.brandDoc.parse(value);
      const pillars = output.brandDoc.pillars.map((pillar) =>
        pillar.toLowerCase()
      );
      if (new Set(pillars).size !== pillars.length) {
        invalidOutput("repeated_brand_pillar");
      }
      if (numberMentions(JSON.stringify(output.brandDoc)).length) {
        invalidOutput("brand_doc_numeric_claim");
      }
      return output;
    }
    case "dealBrief": {
      const output = phaseEOutputSchemas.dealBrief.parse(value);
      checkDeal(output.deal, input.briefText);
      return output;
    }
    case "briefCheck": {
      const output = phaseEOutputSchemas.briefCheck.parse(value);
      checkBrief(output.checks, input);
      return output;
    }
    case "brandNote": {
      const output = phaseEOutputSchemas.brandNote.parse(value);
      const links: string[] =
        output.message.match(/(?:https?:\/\/|www\.)[^\s<>]+/giu) ??
          [];
      if (
        (input.postLink && !links.includes(input.postLink)) ||
        links.some((link) => link !== input.postLink)
      ) invalidOutput("unexpected_post_link");
      return output;
    }
    case "dailyNote": {
      const output = phaseEOutputSchemas.dailyNote.parse(value);
      const { noticed, action, buttonText } = output.dailyNote;
      if (
        (action.type === "continueReel" &&
          !input.openReels.some((reel) => reel.id === action.id)) ||
        (action.type === "openDeal" &&
          !input.openDeals.some((deal) => deal.id === action.id)) ||
        (action.type === "none") !== (buttonText === "")
      ) invalidOutput("invalid_daily_action");
      const values = snapshotNumbers(input.snapshots);
      if (
        [...numberMentions(noticed), ...numberMentions(buttonText)].some(
          (number) => !values.has(number),
        )
      ) invalidOutput("daily_note_numeric_claim");
      return output;
    }
  }
}

export const phaseEPrompts = {
  brandDoc:
    "Build My Brand from the interview, the optional previous document and any supplied Instagram summary. Prefer the new answers if they disagree. Write 3 to 5 distinct pillars and 1 to 3 goals with a short tone, audience, dos and don'ts. Use plain words. Do not include numerical claims or invent personal history. Work with interview answers alone if needed.",
  dealBrief:
    "Extract the deal. Copy the brand, fee, disclosures and exact codes as written. Leave brand or fee empty if absent. Use one short checklist item per obligation with a unique UUID, the closest kind and an exact source excerpt. Include requiredText only when the excerpt has exact text to use, such as a code or disclosure, and copy it verbatim. Put missing values, unclear disclosures or codes, unsupported health claims and unclear dates in unresolved. Only normalize an unambiguous deadline with an explicit year. Use an ISO date, a named English or Hindi month with day and year, or a numeric date with only one possible reading. Copy the exact deadline clause into deadlineExcerpt, or use empty strings for the deadline and its excerpt if absent. Never invent terms.",
  briefCheck:
    "Check every supplied checklist ID once, in order. Use met only for a text item whose requiredText is present in the caption, onScreenText or script. Return an exact supporting excerpt from that field that includes requiredText. Treat the shot list as unverified context. Mark visual, publishing, timing and other unverifiable items missing. Use can-fix only for a caption or onScreenText item. Its fix must be the exact text to add or use. If the item has requiredText, copy it into the fix. Use only supplied facts and exact brand wording. Do not suggest a script or video edit or claim to have seen a video.",
  brandNote:
    "Write a short, polite WhatsApp draft to the brand using only the completed items supplied. Do not say a Reel is live unless a post link is supplied. If the postLink is present, place it verbatim on its own line. Do not add any other link or invented outcome. The creator sends the draft herself.",
  dailyNote:
    "Write one short Mira noticed sentence and one next action. Snapshots are older first, then newer. Only cite supplied metrics with their exact numbers. Do not calculate new numbers, infer trends, or infer metrics from captions. If there are no metrics, use open work or a simple observation about the available context. For continueReel or openDeal use one ID from the matching list. Use an empty buttonText for none, and a short buttonText for other actions.",
} satisfies Record<PhaseEOperation, string>;
