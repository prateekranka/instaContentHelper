#!/usr/bin/env python3
import argparse
from pathlib import Path
import subprocess
import sys

AREA_FILES = {
    "MiraHomeFeed.swift": ("home", "reel", "insights", "deals"),
    "MiraTodayCardState.swift": ("home", "d2"),
    "MiraVoiceInputState.swift": ("home", "words", "deals"),
    "MiraWordsState.swift": ("words", "shots"),
    "MiraScriptView.swift": ("words", "shots"),
    "MiraStoryboardView.swift": ("words", "shots", "reel"),
    "MiraReelProgress.swift": ("home", "words", "shots", "reel"),
    "MiraTaskStep.swift": ("home", "words", "shots", "reel"),
    "MiraBriefState.swift": ("brand", "deals", "reel"),
    "MiraBrandView.swift": ("brand", "reel"),
    "MiraDealsView.swift": ("deals", "home"),
    "MiraDeliveryView.swift": ("reel", "shots"),
    "MiraInsightsService.swift": ("insights", "home"),
    "MiraInsightsState.swift": ("insights", "home"),
    "MiraInsightsView.swift": ("insights", "home"),
    "MiraAIConsentState.swift": ("consent",),
    "mira-consent.e2e.ts": ("consent",),
    "mira-live.e2e.ts": ("home", "d2"),
    "mira-d2-server.mjs": ("d2", "home", "shots"),
    "mira-recorded-today.json": ("d2", "home", "shots"),
    "shot-pictures.ts": ("d2", "shots"),
    "stream.ts": ("d2", "home"),
}
SCOPED_ROOTS = ("CreatorContentOS/Mira/", "tests/", "supabase/functions/mira-generation/")
DOC_FILES = {"README.md", "AGENTS.md", "CLAUDE.md"}

parser = argparse.ArgumentParser(description="Select Mira simulator tests for the current PR.")
parser.add_argument("--dry-run", action="store_true", help="Print the simulator command.")
args = parser.parse_args()

root = Path(__file__).resolve().parent.parent
diff = subprocess.run(
    ["git", "diff", "--no-renames", "--name-only", "-z", "origin/main...HEAD"],
    cwd=root, check=True, stdout=subprocess.PIPE, text=True,
)
files = [name for name in diff.stdout.split("\0") if name]
tags = {"@core"}
reasons = []
full = []
for name in files:
    if name.startswith(("docs/", "evidence/")) or name in DOC_FILES:
        continue
    areas = AREA_FILES.get(Path(name).name) if name.startswith(SCOPED_ROOTS) else None
    if areas is None:
        full.append(name)
    else:
        tags.update("@" + area for area in areas)
        reasons.append(f"{name} selects {', '.join('@' + area for area in areas)}.")

if full:
    print(f"Full simulator list for shared or unknown files: {', '.join(full)}.", file=sys.stderr)
    selection = ""
else:
    for reason in reasons:
        print(reason, file=sys.stderr)
    if reasons:
        print("Include @core with the changed areas.", file=sys.stderr)
    else:
        print("Only docs or evidence changed, or the branch has no diff. Select @core.", file=sys.stderr)
    selection = "--tag " + ",".join(sorted(tags))

if args.dry_run:
    print("scripts/mira-sim-pair.sh" + (f" {selection}" if selection else ""))
elif selection:
    print(selection)
