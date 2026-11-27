import argparse
import re
import sys
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True

from agent_rules.support import REPO, bodies, contains, tokens


def case_names(body):
    depth = 0
    index = 0
    while index < len(body):
        value = body[index].value
        if value in {"(", "[", "{"}:
            depth += 1
        elif value in {")", "]", "}"}:
            depth -= 1
        elif value == "case" and depth == 0:
            while True:
                index += 1
                yield body[index].value
                if index + 1 < len(body) and body[index + 1].value == "(":
                    index += 2
                    parentheses = 1
                    while parentheses:
                        parentheses += (body[index].value == "(") - (body[index].value == ")")
                        index += 1
                    index -= 1
                if index + 1 == len(body) or body[index + 1].value != ",":
                    break
                index += 1
        index += 1


def main():
    parser = argparse.ArgumentParser(description="Check the state tables against the Swift enum cases.")
    parser.add_argument("--source-root", type=Path, default=REPO)
    root = parser.parse_args().source_root
    machine_dir = root / "CreatorContentOS/Mira/Core/StateMachines"
    doc = root / "docs/state-machines.md"
    tables = {}
    section = None
    for line in doc.read_text().splitlines():
        if line.startswith("#"):
            heading = re.fullmatch(r"#{2,6} `(\w+)`", line)
            section = tables.setdefault(heading[1], Counter()) if heading else None
        row = re.match(r"\| `(\w+)` \|", line)
        if section is not None and row:
            section[row[1]] += 1

    machine_names = set()
    states = failures = 0
    for path in sorted(machine_dir.glob("*.swift")):
        source = path.read_text()
        stream = tokens(source)
        names = [name.value for keyword, name in zip(stream, stream[1:]) if keyword.value == "enum"]
        for name in names:
            for body in bodies(source, "enum", name):
                if name != "MiraLocation" and not contains(body, ["func", "handle"]):
                    continue
                expected = Counter(case_names(body))
                actual = tables.get(name, Counter())
                machine_names.add(name)
                states += len(expected)
                missing = sorted((expected - actual).elements())
                extra = sorted((actual - expected).elements())
                if missing or extra:
                    print(f"{doc}: {name}: missing {missing}; unknown or repeated {extra}")
                    failures += 1
    for name in sorted(tables.keys() - machine_names):
        print(f"{doc}: {name}: no matching Swift state enum")
        failures += 1
    if not machine_names:
        print(f"{machine_dir}: no Swift state machines found")
        return 1
    print(f"State tables: {len(machine_names)} Swift enums, {states} cases, {failures} mismatches")
    return int(failures > 0)


if __name__ == "__main__":
    sys.exit(main())
