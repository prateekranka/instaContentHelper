from collections import Counter

from .support import Finding, tokens

HISTORY = []
RECONSTRUCTED = "Step 4 operator correction: you.screen.account on both scaffold and identity child"
CONTAINER_IDENTIFIERS = ('"plan.package.panel.', '"plan.script.timeline"')


def container_findings(sources):
    findings = []
    containment = [".", "accessibilityElement", "(", "children", ":", ".", "contain", ")", "."]
    for file, source in sources.items():
        if not file.endswith(".swift"):
            continue
        stream = tokens(source)
        for i, token in enumerate(stream):
            if token.value != "accessibilityIdentifier" or i + 2 >= len(stream):
                continue
            argument = stream[i + 2]
            if stream[i + 1].value != "(" or argument.kind != "string":
                continue
            if argument.value.startswith(CONTAINER_IDENTIFIERS):
                preceding = [item.value for item in stream[max(0, i - len(containment)):i]]
                if preceding != containment:
                    findings.append(Finding(file, token.line, f"Container {argument.value} must put .accessibilityElement(children: .contain) immediately before its identifier so child controls keep their identifiers."))
    return findings


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
    findings = container_findings(repository.sources)
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
