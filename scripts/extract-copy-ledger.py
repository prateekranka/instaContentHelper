#!/usr/bin/env python3
"""Extract user-facing copy from CreatorContentOS Swift sources."""
import re
import json
from pathlib import Path
from collections import Counter

ROOT = Path("/Users/prateekranka/Cowork/contenthelper/CreatorContentOS")
REPO = ROOT.parent
OUT_JSON = Path(__file__).resolve().parent.parent / ".scratch" / "copy-entries.json"

PATTERNS = [
    (r'Text\s*\(\s*"((?:\\.|[^"\\])*)"', "Text"),
    (r'Text\s*\(\s*verbatim:\s*"((?:\\.|[^"\\])*)"', "Text(verbatim)"),
    (r'Label\s*\(\s*"((?:\\.|[^"\\])*)"', "Label"),
    (r'Button\s*\(\s*"((?:\\.|[^"\\])*)"', "Button"),
    (r'\.accessibilityLabel\s*\(\s*"((?:\\.|[^"\\])*)"', "a11y"),
    (r'\.accessibilityHint\s*\(\s*"((?:\\.|[^"\\])*)"', "a11y-hint"),
    (r'\.accessibilityValue\s*\(\s*"((?:\\.|[^"\\])*)"', "a11y-value"),
    (r'\.navigationTitle\s*\(\s*"((?:\\.|[^"\\])*)"', "nav-title"),
    (r'\.alert\s*\(\s*"((?:\\.|[^"\\])*)"', "alert-title"),
    (r'placeholder:\s*"((?:\\.|[^"\\])*)"', "placeholder"),
    (r'title:\s*"((?:\\.|[^"\\])*)"', "title"),
    (r'subtitle:\s*"((?:\\.|[^"\\])*)"', "subtitle"),
    (r'message:\s*"((?:\\.|[^"\\])*)"', "message"),
    (r'\.confirmationDialog\s*\(\s*"((?:\\.|[^"\\])*)"', "confirm-dialog"),
    (r'Section\s*\(\s*header:\s*Text\s*\(\s*"((?:\\.|[^"\\])*)"', "section-header"),
    (r'Section\s*\(\s*"((?:\\.|[^"\\])*)"', "section"),
    (r'\.help\s*\(\s*"((?:\\.|[^"\\])*)"', "help"),
    (r'ProgressView\s*\(\s*"((?:\\.|[^"\\])*)"', "progress"),
    (r'return\s+"((?:\\.|[^"\\])*)"', "display-return"),
    (r'case\s+\w+\s*:\s*return\s+"((?:\\.|[^"\\])*")', "case-return"),
]

REWRITE_RULES = [
    ("Approve", "rewrite", "Make ready", "C1: action verb not status adjective"),
    (
        "Clicking this will add the card to the Today page.",
        "rewrite",
        "Remove or date-aware readiness wording",
        "C2: desktop Clicking; false Today claims",
    ),
    ("Keep the streak alive.", "cut", "", "C3: decorative subtitle"),
    ("Share the thought.", "cut", "", "C3: decorative subtitle"),
    (
        "Deep reasoning takes a couple of minutes",
        "rewrite",
        "Preparing your idea…",
        "C5: internal terminology",
    ),
    ("Mark posted", "rewrite", "Mark as posted", "C7: unify labels"),
    ("Generation inputs", "rewrite", "Idea settings", "C9: avoid backend term"),
    (
        "The server decides",
        "rewrite",
        "We'll sort what's usable and flag anything that needs your review.",
        "C10",
    ),
    (
        "the server re-checks",
        "rewrite",
        "we'll re-check everything when saving.",
        "C10",
    ),
    ("Resize scene column", "keep", "Resize scene column", "C14: keep VoiceOver control"),
    (
        "pre-race check-in",
        "rewrite",
        "low-key check-in about what I'm working on this week",
        "C13: HYROX example",
    ),
    (
        "Set up later",
        "rewrite (proposed)",
        "You can finish setup in You.",
        "C12: requires skip behavior change",
    ),
    ('Filter chip "Completed"', "rewrite", "Shot & posted", "C11: label ambiguity"),
]

ERROR_TITLE_NOUNS = {
    "Approve",
    "Unpublish",
    "Save edits",
    "Generation error",
    "Generation stopped",
}

UI_LINE_HINTS = (
    "Text",
    "Label",
    "Button",
    "title",
    "message",
    "subtitle",
    "accessibility",
    "Section",
    "alert",
    "placeholder",
    "return",
    "AdminSignal",
    "Toast",
    "header",
    "footer",
    "Pocket",
    "Empty",
    "Progress",
    "navigationTitle",
    "confirmationDialog",
    "help(",
    "Localized",
    "Prompt",
    "Chip",
)


def unescape(s: str) -> str:
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def is_debug_context(lines: list[str], line_idx: int) -> bool:
    start = max(0, line_idx - 40)
    chunk = "\n".join(lines[start : line_idx + 1])
    if "#if DEBUG" in chunk:
        after = chunk.rfind("#if DEBUG")
        before = chunk.rfind("#endif")
        if after > before:
            return True
    if "PreviewProvider" in chunk or "_Previews" in chunk:
        return True
    return False


def is_admin_shell(path: Path) -> bool:
    return "AdminShell" in str(path)


def guess_screen(filepath: Path) -> str:
    fp = str(filepath)
    mapping = [
        ("PlanHubView", "Plan/day detail"),
        ("TodayView", "Today"),
        ("YouView", "You hub"),
        ("YouAccountView", "You/account"),
        ("OnboardingFlowView", "Onboarding"),
        ("OnboardingStep", "Onboarding"),
        ("NotTodaySheet", "Not-today backup sheet"),
        ("ShootFolioView", "Shoot Folio"),
        ("GeneratedDayPlannedContent", "Today/Plan package"),
        ("ArchiveView", "Archive"),
        ("ReferenceImportView", "Reference import"),
        ("ReferenceImportPreviewView", "Reference import preview"),
        ("AppServices", "Error display"),
        ("SignInView", "Sign-in"),
        ("ContentTabView", "Tab shell"),
        ("CreatorVoiceView", "Creator voice"),
        ("ContentCategoriesView", "Content categories"),
        ("PlanDayIdeaLauncher", "Plan idea launcher"),
        ("PlanGenerationInputsSummary", "Plan generation inputs"),
        ("ReferenceWatchlistView", "References"),
        ("ProductionConstraintsView", "Production constraints"),
        ("CreatorContextView", "Creator context"),
        ("OnboardingViewModel", "Onboarding"),
        ("ReferenceImportErrorDisplay", "Reference import errors"),
        ("DayGenerationErrorDisplay", "Generation errors"),
        ("DayLifecycleErrorDisplay", "Lifecycle errors"),
        ("DayAvailabilityErrorDisplay", "Availability errors"),
    ]
    for key, value in mapping:
        if key in fp:
            return value
    if "Onboarding" in fp:
        return "Onboarding"
    return filepath.stem


def classify(text: str, filepath: Path, ptype: str, is_debug: bool) -> tuple:
    disposition = "keep"
    proposed = text
    evidence = ""

    for key, disp, prop, ev in REWRITE_RULES:
        if key in text:
            disposition = disp
            proposed = prop if prop else text
            evidence = ev
            break

    if "published" in text.lower() and "card" in text.lower() and disposition == "keep":
        disposition = "rewrite"
        proposed = re.sub(r"published", "ready", text, flags=re.I)
        evidence = evidence or "C8: Ready not published"

    if "the creator" in text.lower() and disposition == "keep":
        disposition = "rewrite"
        proposed = re.sub(r"the creator", "you", text, flags=re.I)
        evidence = evidence or "C6: third-person voice"

    if "society garden" in text.lower():
        disposition = "rewrite"
        proposed = (
            "You can shoot this at home or wherever makes the scene "
            "easiest to capture clearly and safely."
        )
        evidence = evidence or "C6: India/HYROX default location list"

    if ptype in ("title", "alert-title") and text in ERROR_TITLE_NOUNS:
        disposition = "cut"
        proposed = "(drop title; show message only)"
        evidence = evidence or "C4: duplicate error title"

    if text == "Completed" and "Archive" in str(filepath):
        disposition = "rewrite"
        proposed = "Shot & posted"
        evidence = "C11: Completed filter ambiguity"

    if "Clicking" in text and disposition == "keep":
        disposition = "rewrite"
        proposed = "Remove or replace"
        evidence = "C2"

    if is_debug or is_admin_shell(filepath):
        disposition = "DEBUG"
        evidence = (evidence + "; " if evidence else "") + "DEBUG/AdminShell context"

    tl = text.lower()
    if any(
        w in tl
        for w in [
            "error",
            "failed",
            "could not",
            "try again",
            "timed out",
            "stopped",
        ]
    ):
        job = "recovery/safety"
    elif any(w in tl for w in ["delete", "sign out", "cancel", "confirm", "overwrite"]):
        job = "action/safety"
    elif any(
        w in tl
        for w in ["loading", "drafting", "preparing", "generating", "approving"]
    ):
        job = "state"
    elif ptype.startswith("a11y"):
        job = "accessibility"
    elif ptype == "placeholder":
        job = "input guidance"
    elif ptype in ("Button", "Label"):
        job = "action"
    else:
        job = "information"

    return disposition, proposed, job, evidence


def should_skip_technical(text: str) -> bool:
    if not text.strip() or len(text) > 400:
        return True
    if re.match(r"^[a-z][a-z0-9_.]*$", text) and ("." in text or "/" in text):
        return True
    if text.startswith("http") or text.startswith("com."):
        return True
    if "/" in text and "." in text and " " not in text:
        return True
    if text in ("utf8", "json", "POST", "GET", "Bearer", "application/json"):
        return True
    if re.match(r"^[a-z][a-zA-Z0-9_]*$", text) and text[0].islower() and len(text) < 20:
        return True
    return False


def add_entry(entries, seen, rel, line_num, text, filepath, ptype, is_debug):
    key = (str(rel), line_num, text)
    if key in seen:
        return
    seen.add(key)
    disp, prop, job, ev = classify(text, filepath, ptype, is_debug)
    entries.append(
        {
            "id": f"COPY-{len(entries) + 1:04d}",
            "screen": guess_screen(filepath),
            "file": f"{rel}:{line_num}",
            "text": text,
            "disposition": disp,
            "proposed": prop,
            "job": job,
            "evidence": ev,
        }
    )


def main():
    entries: list[dict] = []
    seen: set = set()

    for swift in sorted(ROOT.rglob("*.swift")):
        rel = swift.relative_to(REPO)
        content = swift.read_text(encoding="utf-8", errors="replace")
        lines = content.splitlines()

        for i, line in enumerate(lines, 1):
            is_dbg = is_debug_context(lines, i - 1)
            for pat, ptype in PATTERNS:
                for m in re.finditer(pat, line):
                    text = unescape(m.group(1))
                    if should_skip_technical(text):
                        continue
                    add_entry(entries, seen, rel, i, text, swift, ptype, is_dbg)

    extra_pat = re.compile(r'"((?:\\.|[^"\\]){3,200})"')
    for swift in sorted(ROOT.rglob("*.swift")):
        rel = swift.relative_to(REPO)
        content = swift.read_text(encoding="utf-8", errors="replace")
        lines = content.splitlines()
        for i, line in enumerate(lines, 1):
            if not any(h in line for h in UI_LINE_HINTS):
                continue
            is_dbg = is_debug_context(lines, i - 1)
            for m in extra_pat.finditer(line):
                text = unescape(m.group(1))
                if should_skip_technical(text) or len(text) < 3:
                    continue
                add_entry(entries, seen, rel, i, text, swift, "string-literal", is_dbg)

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(entries, indent=2), encoding="utf-8")
    print("TOTAL", len(entries))
    print("DISPOSITIONS", dict(Counter(e["disposition"] for e in entries)))


if __name__ == "__main__":
    main()
