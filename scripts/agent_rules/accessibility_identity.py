from collections import Counter

from .support import Finding, tokens

HISTORY = []
RECONSTRUCTED = "Step 4 operator correction: you.screen.account on both scaffold and identity child"


def identifiers(sources):
    found = []
    for file, source in sources.items():
        if not file.endswith(".swift"):
            continue
        stream = tokens(source)
        for i, token in enumerate(stream):
            if token.value == "accessibilityIdentifier" and i + 2 < len(stream):
                argument = stream[i + 2]
                if stream[i + 1].value == "(" and argument.kind == "string":
                    found.append((argument.value, file, token.line))
    return found


def check(repository):
    before = identifiers(repository.baseline)
    after = identifiers(repository.sources)
    allowed = Counter(value for value, file, line in before)
    seen = Counter()
    findings = []
    for value, file, line in after:
        seen[value] += 1
        if seen[value] > max(allowed[value], 1):
            findings.append(Finding(file, line, f"Identifier {value} gained another owner. Keep accessibilityIdentifier on one semantic element; use YouDestinationScaffold/YouAccountView for the account screen identifier."))
    for value, file, line in before:
        if value not in seen:
            findings.append(Finding(file, line, f"Restore accessibilityIdentifier({value}); preserve the existing identifier when moving its semantic element."))
    return findings


def reconstruct(root):
    file = root / "CreatorContentOS/Features/You/YouAccountView.swift"
    source = file.read_text()
    old = '.accessibilityIdentifier("you.account.identity")'
    new = old + '\n                .accessibilityIdentifier("you.screen.account")'
    if source.count(old) != 1:
        raise RuntimeError("Cannot reconstruct the supplied account identifier mistake.")
    file.write_text(source.replace(old, new))
