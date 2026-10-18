#!/usr/bin/env python3
"""Build copy-ledger.md and copy-ledger-summary.md from CreatorContentOS Swift sources."""
from __future__ import annotations

import re
import textwrap
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path("/Users/prateekranka/Cowork/contenthelper/CreatorContentOS")
REPO = ROOT.parent
AUDIT = Path("/Users/prateekranka/Documents/Codex/2026-06-19/contenthelper-ui-audit")

# Files/dirs whose string literals are model/fixture content, not UI chrome
EXCLUDE_PATH_PARTS = {
    "Fixtures/",
    "CreatorContentOSTests",
}

# Files with sample model content — skip unless line matches presentation wrapper
MODEL_CONTENT_FILES = {
    "Models/Models.swift",
    "Models/GeneratedStoryboardBreakdown.swift",
}

UI_PATTERNS = [
    (r'Text\s*\(\s*"((?:\\.|[^"\\])*)"', "Text"),
    (r'Text\s*\(\s*verbatim:\s*"((?:\\.|[^"\\])*)"', "Text"),
    (r'Label\s*\(\s*"((?:\\.|[^"\\])*)"', "Label"),
    (r'Button\s*\(\s*"((?:\\.|[^"\\])*)"', "Button"),
    (r'\.accessibilityLabel\s*\(\s*"((?:\\.|[^"\\])*)"', "a11y-label"),
    (r'\.accessibilityHint\s*\(\s*"((?:\\.|[^"\\])*)"', "a11y-hint"),
    (r'\.accessibilityValue\s*\(\s*"((?:\\.|[^"\\])*)"', "a11y-value"),
    (r'\.navigationTitle\s*\(\s*"((?:\\.|[^"\\])*)"', "nav-title"),
    (r'\.alert\s*\(\s*"((?:\\.|[^"\\])*)"', "alert"),
    (r'\.confirmationDialog\s*\(\s*"((?:\\.|[^"\\])*)"', "confirm-dialog"),
    (r'placeholder:\s*"((?:\\.|[^"\\])*)"', "placeholder"),
    (r'(?<![\w])title:\s*"((?:\\.|[^"\\])*)"', "title"),
    (r'subtitle:\s*"((?:\\.|[^"\\])*)"', "subtitle"),
    (r'message:\s*"((?:\\.|[^"\\])*)"', "message"),
    (r'Section\s*\(\s*header:\s*Text\s*\(\s*"((?:\\.|[^"\\])*)"', "section-header"),
    (r'Section\s*\(\s*"((?:\\.|[^"\\])*)"', "section"),
    (r'\.help\s*\(\s*"((?:\\.|[^"\\])*)"', "help"),
    (r'ProgressView\s*\(\s*"((?:\\.|[^"\\])*)"', "progress"),
    (r'toastMessage\s*=\s*"((?:\\.|[^"\\])*)"', "toast"),
    (r'PocketSheetPrimaryAction\s*\(\s*title:\s*"((?:\\.|[^"\\])*)"', "primary-action"),
    (r'PocketSheetSecondaryAction\s*\(\s*title:\s*"((?:\\.|[^"\\])*)"', "secondary-action"),
    (r'PocketSheetBlock\s*\(\s*header:\s*"((?:\\.|[^"\\])*)"', "block-header"),
    (r'AdminSignalBlock\s*\(\s*title:\s*"((?:\\.|[^"\\])*)"', "admin-signal-title"),
    (r'title:\s*cancelled\s*\?\s*"((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"', "admin-signal-ternary"),
    (r'\?\?\s*"((?:\\.|[^"\\])*)"', "fallback-string"),
    (r'map\s*\{\s*_\s+in\s+"((?:\\.|[^"\\])*)"', "map-fallback"),
    (r'\?\s*"((?:\\.|[^"\\])*)"\s*\n\s*:\s*"((?:\\.|[^"\\])*)"', "ternary-string"),
    (r'ReviewActionButton\s*\(\s*title:\s*"((?:\\.|[^"\\])*)"', "review-action"),
    (r'reviewPill\s*\(\s*title:\s*"((?:\\.|[^"\\])*)"', "review-pill"),
    (r'EmptyStateView\s*\([^)]*title:\s*"((?:\\.|[^"\\])*)"', "empty-title"),
    (r'EmptyStateView\s*\([^)]*message:\s*"((?:\\.|[^"\\])*)"', "empty-message"),
    (r'\.searchable\s*\([^)]*prompt:\s*Text\s*\(\s*"((?:\\.|[^"\\])*)"', "search-prompt"),
    (r'case\s+\.\w+(?:\([^)]*\))?:\s*\n?\s*"((?:\\.|[^"\\])*)"', "switch-case"),
    (r'case\s+\w+\s*=\s*"((?:\\.|[^"\\])*)"', "enum-raw"),
    (r'LocalizedError\s*\{[^}]*errorDescription[^"]*"((?:\\.|[^"\\])*)"', "localized-error"),
    (r'errorDescription:\s*String\?\s*\{\s*"((?:\\.|[^"\\])*)"', "error-desc"),
    (r'errorDescription:\s*String\?\s*\{\s*\n\s*"((?:\\.|[^"\\])*)"', "error-desc-multiline"),
]

# Error map pattern in AppServices and similar
ERROR_MAP_PATTERN = re.compile(
    r'"([a-z_]+)":\s*"((?:\\.|[^"\\])*)"'
)

ERROR_TITLE_NOUNS = {
    "Approve",
    "Unpublish",
    "Save edits",
    "Generation error",
    "Generation stopped",
}


@dataclass
class Row:
    id: str
    screen: str
    file_line: str
    text: str
    disposition: str
    proposed: str
    job: str
    evidence: str


def unescape(s: str) -> str:
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def rel_path(path: Path) -> str:
    return str(path.relative_to(REPO))


def should_skip_file(path: Path) -> bool:
    rp = rel_path(path)
    for part in EXCLUDE_PATH_PARTS:
        if part in rp:
            return True
    return False


def is_model_content_file(path: Path) -> bool:
    rp = rel_path(path)
    return any(rp.endswith(m) or m in rp for m in MODEL_CONTENT_FILES)


def is_debug_block(lines: list[str], idx: int) -> bool:
    start = max(0, idx - 50)
    chunk = "\n".join(lines[start : idx + 1])
    if "#if DEBUG" in chunk:
        after = chunk.rfind("#if DEBUG")
        before = chunk.rfind("#endif")
        if after > before:
            return True
    if "PreviewProvider" in chunk or "_Previews" in chunk:
        return True
    return False


def is_admin_shell(path: Path) -> bool:
    return "AdminShellView.swift" in str(path)


def guess_screen(path: Path, line: str) -> str:
    rp = rel_path(path)
    rules = [
        ("PlanHubView", "Plan / day detail"),
        ("PlanDayIdeaLauncher", "Plan / idea launcher"),
        ("PlanCalendarSheet", "Plan / calendar sheet"),
        ("PlanGenerationInputsSummary", "Plan / idea settings summary"),
        ("GeneratedDayPlannedContent", "Today or Plan / package detail"),
        ("TodayView", "Today"),
        ("NotTodaySheet", "Today / backup sheet"),
        ("ShootFolioView", "Shoot Folio"),
        ("YouView", "You / hub"),
        ("YouAccountView", "You / account"),
        ("YouCreatorVoiceView", "You / creator voice"),
        ("YouContentCategoriesView", "You / content categories"),
        ("YouProductionPreferencesView", "You / production preferences"),
        ("YouCurrentContextView", "You / current context"),
        ("YouReferencesView", "You / references"),
        ("DayGenerationBenchmarkView", "You / benchmark (DEBUG-adjacent)"),
        ("OnboardingFlowView", "Onboarding"),
        ("OnboardingContextQuestions", "Onboarding / context"),
        ("OnboardingProductionForm", "Onboarding / production"),
        ("OnboardingSelectionComponents", "Onboarding / selection"),
        ("OnboardingViewModel", "Onboarding / toast"),
        ("ArchiveView", "Archive"),
        ("ReferenceImportView", "References / import"),
        ("ReferenceImportPreviewView", "References / import preview"),
        ("ReferenceReviewEditSheet", "References / review sheet"),
        ("IntelligenceHomeView", "Intelligence"),
        ("SignInView", "Sign-in"),
        ("AuthenticationService", "Sign-in / auth errors"),
        ("AppServices.swift", "Global / error display"),
        ("AdminShellView", "Admin shell (DEBUG)"),
        ("PackageFolderTabs", "Package / folder tabs"),
        ("PocketSheetComponents", "Design system"),
        ("DesignSystem.swift", "Design system"),
    ]
    for key, val in rules:
        if key in rp:
            return val
    if "Onboarding" in rp:
        return "Onboarding"
    if "ErrorDisplay" in line or "userFacingMessages" in line:
        return "Error display"
    return Path(rp).stem


def classify(text: str, path: Path, ptype: str, is_debug: bool, line: str) -> tuple[str, str, str, str]:
    disposition = "keep"
    proposed = text
    evidence = ""

    # C4 error tile titles (before C1 Approve verb rewrite)
    if ptype == "admin-signal-title" and text in ERROR_TITLE_NOUNS:
        disposition = "cut"
        proposed = "(drop title; show human message only)"
        evidence = "C4: error tile title duplicates message noun"
    elif text in ("Approve", "Approving…") and "PlanHubView" in str(path) and ptype in (
        "primary-action",
        "title-ternary",
    ):
        disposition = "rewrite"
        proposed = "Make ready" if text == "Approve" else "Making ready…"
        evidence = "C1: action verb; lifecycle unchanged"
    elif "Clicking this will add the card to the Today page." in text:
        disposition = "rewrite"
        proposed = "Remove or use date-aware readiness wording"
        evidence = "C2: desktop Clicking; future dates must not promise immediate Today"
    elif text in ("Keep the streak alive.", "Share the thought.", "Save for tomorrow"):
        if text in ("Keep the streak alive.", "Share the thought."):
            disposition = "cut"
            proposed = ""
            evidence = "C3: decorative backup subtitles"
        elif text == "Save for tomorrow":
            disposition = "keep"
            proposed = text
            evidence = "Backup option label; keep"
    elif "Deep reasoning takes a couple of minutes" in text:
        disposition = "rewrite"
        proposed = "Preparing your idea…"
        evidence = "C5: remove internal reasoning/validation jargon"
    elif text == "Mark posted":
        disposition = "rewrite"
        proposed = "Mark as posted"
        evidence = "C7: unify with Shoot Folio"
    elif "published card" in text.lower():
        disposition = "rewrite"
        proposed = re.sub(r"published", "ready", text, flags=re.I).replace(
            "The app is loading the latest ready card.", "Getting your latest card…"
        )
        evidence = "C8: Ready package vocabulary; avoid machine voice"
    elif text == "Generation inputs":
        disposition = "rewrite"
        proposed = "Idea settings"
        evidence = "C9: avoid backend term generation"
    elif "The server decides" in text or "the server re-checks" in text:
        disposition = "rewrite"
        if "decides" in text:
            proposed = "Paste handles, reel links, audio links, or a CSV. We'll sort what's usable and flag anything that needs your review."
        else:
            proposed = text.replace("the server re-checks", "we'll re-check")
        evidence = "C10: server is architecture jargon"
    elif text == "Completed" and "ArchiveView" in str(path):
        disposition = "rewrite"
        proposed = "Shot & posted"
        evidence = "C11: Completed contradicts Skipped sibling filter"
    elif "Set up later" in text and "ask again next launch" in text:
        disposition = "rewrite (proposed)"
        proposed = "You can finish setup in You."
        evidence = "C12: proposed until skippable-setup behavior lands"
    elif "pre-race check-in" in text:
        disposition = "rewrite"
        proposed = "e.g. A low-key check-in about what I'm working on this week…"
        evidence = "C13: HYROX-flavored placeholder example"
    elif text == "Resize scene column":
        disposition = "keep"
        proposed = text
        evidence = "C14: keep working VoiceOver resize control"
    elif "the creator" in text.lower() or "society garden" in text.lower():
        disposition = "rewrite"
        proposed = "You can shoot this at home or wherever makes the scene easiest to capture clearly and safely."
        evidence = "C6: third-person + India/HYROX default in client fallback"

    if ptype in ("admin-signal-title", "title") and text in ERROR_TITLE_NOUNS:
        if disposition == "keep":
            disposition = "cut"
            proposed = "(drop title; show human message only)"
            evidence = evidence or "C4: error tile title duplicates message noun"

    if ptype == "admin-signal-ternary" and text in ERROR_TITLE_NOUNS:
        disposition = "cut"
        proposed = "(drop title; show human message only)"
        evidence = evidence or "C4: error tile title duplicates message noun"

    if "Approve could not" in text or "Tap Approve again" in text:
        disposition = "rewrite"
        proposed = text.replace("Approve", "Make ready").replace("approve", "make ready")
        evidence = evidence or "C1/C4: align error copy with Make ready verb"

    if is_debug or is_admin_shell(path):
        if disposition == "keep":
            disposition = "DEBUG"
        evidence = (evidence + "; " if evidence else "") + "AdminShell or DEBUG-only surface"

    tl = text.lower()
    if any(w in tl for w in ["error", "failed", "could not", "try again", "timed out", "stopped", "missing", "invalid", "expired"]):
        job = "recovery / safety"
    elif any(w in tl for w in ["delete", "sign out", "cancel", "confirm", "overwrite", "skip"]):
        job = "action / safety"
    elif any(w in tl for w in ["loading", "drafting", "preparing", "generating", "approving", "syncing"]):
        job = "state"
    elif ptype.startswith("a11y"):
        job = "accessibility"
    elif ptype in ("placeholder", "search-prompt"):
        job = "input guidance"
    elif ptype in ("Button", "Label", "review-action", "review-pill", "title"):
        job = "action"
    elif ptype == "toast":
        job = "feedback"
    else:
        job = "information"

    return disposition, proposed, job, evidence


def is_technical_string(text: str) -> bool:
    if not text.strip() or len(text) > 350:
        return True
    if "\\(" in text or text.startswith("\\("):
        return True  # Swift interpolation fragment, not static copy
    if re.match(r"^[a-z][a-z0-9_.-]*$", text) and ("." in text or "/" in text):
        return True
    if text.startswith("http") or text.startswith("com."):
        return True
    if text in {"utf8", "json", "POST", "GET", "Bearer", "application/json", "All", "Backups", "Skipped"}:
        return False  # All/Backups/Skipped are UI
    if re.match(r"^[a-z_]+$", text) and len(text) < 30:
        return True
    return False


def extract_error_maps(path: Path, rows: list[Row], counter: list[int]) -> None:
    content = path.read_text(encoding="utf-8", errors="replace")
    lines = content.splitlines()
    in_map = False
    map_name = ""
    for i, line in enumerate(lines, 1):
        if "userFacingMessages" in line and "=" in line:
            in_map = True
            map_name = line.strip()
            continue
        if in_map:
            if line.strip().startswith("]"):
                in_map = False
                continue
            m = re.match(r'\s*"[^"]+":\s*"((?:\\.|[^"\\])*)"', line)
            if m:
                text = unescape(m.group(1))
                counter[0] += 1
                disp, prop, job, ev = classify(text, path, "error-map", False, line)
                rows.append(
                    Row(
                        id=f"COPY-{counter[0]:04d}",
                        screen=guess_screen(path, line),
                        file_line=f"{rel_path(path)}:{i}",
                        text=text,
                        disposition=disp,
                        proposed=prop,
                        job=job,
                        evidence=ev or f"Error map: {map_name[:60]}",
                    )
                )


def extract_file(path: Path, rows: list[Row], counter: list[int]) -> None:
    if should_skip_file(path):
        return
    content = path.read_text(encoding="utf-8", errors="replace")
    lines = content.splitlines()
    model_file = is_model_content_file(path)

    if model_file:
        return  # sample/model body text excluded; presentation wrappers extracted elsewhere

    # Multiline AdminSignalBlock titles
    for m in re.finditer(
        r'AdminSignalBlock\s*\(\s*title:\s*(?:cancelled\s*\?\s*)?"((?:\\.|[^"\\])*)"(?:\s*:\s*"((?:\\.|[^"\\])*)")?',
        content,
        re.MULTILINE,
    ):
        line_num = content[: m.start()].count("\n") + 1
        for g in m.groups():
            if not g:
                continue
            text = unescape(g)
            if is_technical_string(text):
                continue
            counter[0] += 1
            disp, prop, job, ev = classify(text, path, "admin-signal-title", False, "")
            rows.append(
                Row(
                    id=f"COPY-{counter[0]:04d}",
                    screen=guess_screen(path, ""),
                    file_line=f"{rel_path(path)}:{line_num}",
                    text=text,
                    disposition=disp,
                    proposed=prop,
                    job=job,
                    evidence=ev,
                )
            )

    for i, line in enumerate(lines, 1):
        if model_file:
            continue

        is_dbg = is_debug_block(lines, i - 1)

        # PocketSheet action titles may wrap to the next line (ternary)
        pocket_context = line
        if i > 1 and "PocketSheetPrimaryAction" in lines[i - 2]:
            pocket_context = lines[i - 2] + " " + line
        if i > 1 and "PocketSheetSecondaryAction" in lines[i - 2]:
            pocket_context = lines[i - 2] + " " + line
        if any(
            k in pocket_context
            for k in ("PocketSheetPrimaryAction", "PocketSheetSecondaryAction")
        ) and '"' in line:
            for m in re.finditer(r'"((?:\\.|[^"\\])*)"', line):
                text = unescape(m.group(1))
                if is_technical_string(text) or len(text) < 4:
                    continue
                counter[0] += 1
                disp, prop, job, ev = classify(text, path, "title-ternary", is_dbg, line)
                rows.append(
                    Row(
                        id=f"COPY-{counter[0]:04d}",
                        screen=guess_screen(path, line),
                        file_line=f"{rel_path(path)}:{i}",
                        text=text,
                        disposition=disp,
                        proposed=prop,
                        job=job,
                        evidence=ev,
                    )
                )

        for pat, ptype in UI_PATTERNS:
            for m in re.finditer(pat, line, re.MULTILINE):
                groups = m.groups()
                texts = [unescape(g) for g in groups if g]
                for text in texts:
                    if is_technical_string(text):
                        continue
                    counter[0] += 1
                    disp, prop, job, ev = classify(text, path, ptype, is_dbg, line)
                    rows.append(
                        Row(
                            id=f"COPY-{counter[0]:04d}",
                            screen=guess_screen(path, line),
                            file_line=f"{rel_path(path)}:{i}",
                            text=text,
                            disposition=disp,
                            proposed=prop,
                            job=job,
                            evidence=ev,
                        )
                    )

        # Ternary labels on PocketSheet action bars only
        if any(k in line for k in ("PocketSheetPrimaryAction", "PocketSheetSecondaryAction", "PocketSheetCommandBar")) and '"' in line:
            for m in re.finditer(r'"((?:\\.|[^"\\])*)"', line):
                text = unescape(m.group(1))
                if is_technical_string(text) or len(text) < 4:
                    continue
                counter[0] += 1
                disp, prop, job, ev = classify(text, path, "title-ternary", is_dbg, line)
                rows.append(
                    Row(
                        id=f"COPY-{counter[0]:04d}",
                        screen=guess_screen(path, line),
                        file_line=f"{rel_path(path)}:{i}",
                        text=text,
                        disposition=disp,
                        proposed=prop,
                        job=job,
                        evidence=ev,
                    )
                )

    if path.name == "AppServices.swift":
        extract_error_maps(path, rows, counter)

    if path.name == "ShootFolioView.swift":
        for m in re.finditer(
            r'"((?:In Bombay, )?The creator can shoot this at home, in the society garden, or in the gym[^"]*)"',
            content,
        ):
            line_num = content[: m.start()].count("\n") + 1
            text = unescape(m.group(1))
            counter[0] += 1
            disp, prop, job, ev = classify(text, path, "presentation-wrapper", False, "")
            rows.append(
                Row(
                    id=f"COPY-{counter[0]:04d}",
                    screen="Shoot Folio / scene example wrapper",
                    file_line=f"{rel_path(path)}:{line_num}",
                    text=text,
                    disposition=disp,
                    proposed=prop,
                    job=job,
                    evidence=ev,
                )
            )
        for m in re.finditer(
            r'case\s+\.\w+(?:\([^)]*\))?:\s*\n\s*"((?:\\.|[^"\\])*)"',
            content,
        ):
            line_num = content[: m.start()].count("\n") + 1
            text = unescape(m.group(1))
            if is_technical_string(text):
                continue
            counter[0] += 1
            disp, prop, job, ev = classify(text, path, "switch-case", False, "")
            rows.append(
                Row(
                    id=f"COPY-{counter[0]:04d}",
                    screen="Shoot Folio / empty state",
                    file_line=f"{rel_path(path)}:{line_num}",
                    text=text,
                    disposition=disp,
                    proposed=prop,
                    job=job,
                    evidence=ev,
                )
            )


def md_escape(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


def write_ledger(rows: list[Row]) -> None:
    # Deduplicate identical file_line + text (multiple patterns may match)
    deduped: list[Row] = []
    seen_keys: set[tuple[str, str]] = set()
    for r in rows:
        key = (r.file_line, r.text)
        if key in seen_keys:
            continue
        seen_keys.add(key)
        deduped.append(r)
    for idx, r in enumerate(deduped, 1):
        r.id = f"COPY-{idx:04d}"
    rows = deduped
    ledger_path = AUDIT / "copy-ledger.md"
    summary_path = AUDIT / "copy-ledger-summary.md"

    header = textwrap.dedent(
        """\
        # ContentHelper static copy ledger

        Pinned source: `20766cd90fd6338592d8fb7792395f566eda1205` on branch `cursor/today-ui-prototype-cea4`.
        Scope: `CreatorContentOS/` Swift UI chrome only. Excludes HTML prototype, fixture seed data, and model-generated script/caption/scene body text (presentation wrappers included).
        Product note: launch bar = first useful package after Apple sign-in; sharing is separate. Do not call a generated card a shared post.

        Columns: `ID | screen/state | file:line | existing text | keep/cut/rewrite | proposed text | information/action/safety job | evidence`

        """
    )

    with ledger_path.open("w", encoding="utf-8") as f:
        f.write(header)
        f.write("| ID | screen/state | file:line | existing text | disposition | proposed text | job | evidence |\n")
        f.write("| --- | --- | --- | --- | --- | --- | --- | --- |\n")
        for r in rows:
            f.write(
                f"| {r.id} | {md_escape(r.screen)} | `{r.file_line}` | {md_escape(r.text)} | {r.disposition} | {md_escape(r.proposed)} | {r.job} | {md_escape(r.evidence)} |\n"
            )

    counts = Counter(r.disposition for r in rows)
    rewrite_rows = [r for r in rows if r.disposition.startswith("rewrite")]
    cut_rows = [r for r in rows if r.disposition == "cut"]
    debug_rows = [r for r in rows if r.disposition == "DEBUG"]

    blockers = [
        "Bobby launch decision unresolved: actual shared post within 60s vs time-to-first-useful-package (blocks C12 implementation, not ledger).",
        "C12 skip toast marked rewrite (proposed) until skippable-setup onboarding behavior lands.",
        "C1 Approve→Make ready requires error-map alignment (Tap Approve again, Approve could not…).",
        "Copy-only pass cannot restore Today main-package copy controls (separate implementation ledger).",
        "AdminShell strings retained as DEBUG; not shipped in Release consumer path.",
    ]

    high_impact = []
    seed_order = [
        "C1",
        "C2",
        "C3",
        "C4",
        "C5",
        "C6",
        "C7",
        "C8",
        "C9",
        "C10",
        "C11",
        "C12",
        "C13",
        "C14",
    ]
    for cid in seed_order:
        matches = [r for r in rows if re.search(rf"\b{cid}\b", r.evidence)]
        if not matches:
            continue
        # Prefer non-DEBUG, non-duplicate C1/C4 rows
        preferred = next((r for r in matches if r.disposition != "DEBUG"), matches[0])
        if cid == "C1":
            preferred = next(
                (r for r in matches if "487" in r.file_line and r.disposition == "rewrite"),
                next((r for r in matches if "487" in r.file_line), preferred),
            )
        if cid == "C4":
            preferred = next(
                (r for r in matches if "PlanHubView" in r.file_line and "Generation error" in r.text),
                next((r for r in matches if "Generation error" in r.text), preferred),
            )
        high_impact.append((cid, preferred))

    with summary_path.open("w", encoding="utf-8") as f:
        f.write("# Copy ledger summary\n\n")
        f.write(f"**Total rows:** {len(rows)}\n\n")
        f.write("## Disposition counts\n\n")
        for k in ["keep", "rewrite", "rewrite (proposed)", "cut", "DEBUG"]:
            if counts.get(k):
                f.write(f"- **{k}:** {counts[k]}\n")
        f.write("\n## Blockers\n\n")
        for b in blockers:
            f.write(f"- {b}\n")
        f.write("\n## High-impact rewrite rows (seed candidates)\n\n")
        f.write("| ID | file:line | existing | proposed | evidence |\n")
        f.write("| --- | --- | --- | --- | --- |\n")
        for cid, r in high_impact:
            f.write(
                f"| {r.id} | `{r.file_line}` | {md_escape(r.text[:100])} | {md_escape(r.proposed[:100])} | {md_escape(r.evidence)} |\n"
            )

    print(f"Wrote {ledger_path} ({len(rows)} rows)")
    print(f"Wrote {summary_path}")
    print(dict(counts))


def main() -> None:
    rows: list[Row] = []
    counter = [0]
    for swift in sorted(ROOT.rglob("*.swift")):
        extract_file(swift, rows, counter)
    write_ledger(rows)


if __name__ == "__main__":
    main()
