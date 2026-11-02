import argparse
import importlib
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from agent_rules.support import Repository, rules


def main():
    parser = argparse.ArgumentParser(description="Check creator-loop agent rules without running the app.")
    parser.add_argument("--class", dest="rule", choices=rules())
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    repository = Repository(args.source_root)
    failures = 0
    for name in [args.rule] if args.rule else rules():
        module = importlib.import_module(f"agent_rules.{name}")
        findings = module.check(repository)
        for finding in findings:
            print(f"{finding.file}:{finding.line}: error [{name}]: {finding.message}")
        failures += len(findings)
        print(f"{name}: {'FAIL' if findings else 'PASS'} ({len(findings)} violations)")
    return int(failures > 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print(f"scripts/check-agent-rules.py:1: error: {error}", file=sys.stderr)
        sys.exit(2)
