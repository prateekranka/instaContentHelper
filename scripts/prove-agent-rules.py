import argparse
import importlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from agent_rules.support import REPO, git_source, rules


def run_check(root, name=None):
    command = [sys.executable, str(REPO / "scripts/check-agent-rules.py"), "--source-root", str(root)]
    if name:
        command.extend(["--class", name])
    return subprocess.run(command, cwd=REPO, capture_output=True, text=True)


def copy_sources(root):
    for directory, pattern in [("CreatorContentOS", "*.swift"), ("tests", "*.ts")]:
        for source in (REPO / directory).rglob(pattern):
            target = root / source.relative_to(REPO)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)


def main():
    parser = argparse.ArgumentParser(description="Prove source checks against historical mistakes in isolated temporary copies.")
    parser.add_argument("--class", dest="rule", choices=rules())
    args = parser.parse_args()
    clean = run_check(REPO)
    print(clean.stdout, end="")
    if clean.returncode:
        print(clean.stderr, end="", file=sys.stderr)
        raise RuntimeError("Fix the current source check before proving historical failures.")
    total = 0
    for name in [args.rule] if args.rule else rules():
        module = importlib.import_module(f"agent_rules.{name}")
        cases = [(f"git {ref}: {', '.join(files)}", ref, files) for ref, files in module.HISTORY]
        if hasattr(module, "reconstruct"):
            cases.append((module.RECONSTRUCTED, None, []))
        if not cases:
            raise RuntimeError(f"{name} has no past-mistake proof.")
        for label, ref, files in cases:
            with tempfile.TemporaryDirectory(prefix=f"creator-loop-{name}-") as directory:
                root = Path(directory)
                copy_sources(root)
                for file in files:
                    target = root / file
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(git_source(ref, file))
                if ref is None:
                    module.reconstruct(root)
                result = run_check(root, name)
                diagnostics = [line for line in result.stdout.splitlines() if f"error [{name}]" in line]
                if result.returncode != 1 or not diagnostics:
                    print(result.stdout + result.stderr)
                    raise RuntimeError(f"{name} did not reject {label}; exit={result.returncode}.")
                print(f"PROVED {name}: {label}; exit=1; {len(diagnostics)} violations")
                for line in diagnostics:
                    print(line)
                total += 1
    print(f"PASS: {total} historical reproductions rejected; working tree source never replaced.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(f"scripts/prove-agent-rules.py:1: error: {error}", file=sys.stderr)
        sys.exit(1)
