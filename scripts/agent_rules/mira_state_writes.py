from collections import Counter

from .support import Finding, git_source, scoped

STORE = "CreatorContentOS/Mira/Core/MiraStore.swift"
SPEECH = "CreatorContentOS/Mira/Services/MiraSpeechInput.swift"
INSIGHTS = "CreatorContentOS/Mira/Views/MiraInsightsView.swift"
BASELINE = "b1dc55c7d60e56d5f7821db12f943f823834c35a"
FIELDS = {
    "MiraStore": {"location", "library", "wordsStates", "requestStates"},
    "MiraSpeechInput": {"state"},
    "MiraSpeechInputService": {"state"},
    "MiraInsightsView": {"state"},
}
DISTINCT_FIELDS = {"wordsStates", "requestStates"}
FIELD_NAMES = set().union(*FIELDS.values())
MUTATING_METHODS = {"merge", "remove", "removeAll", "removeValue", "updateValue"}
HISTORY = []


def receiver_fields(values):
    bindings = {}
    for index, value in enumerate(values):
        if value not in FIELDS or not index:
            continue
        left = index - 1
        while left >= 0 and values[left] in {"(", "any", "some"}:
            left -= 1
        if left > 0 and values[left] in {":", "="}:
            bindings.setdefault(values[left - 1], set()).update(FIELDS[value])
    return bindings


def write_shape(values, index):
    end = index + 1
    if values[end:end + 2] in [["?", "["], ["!", "["]]:
        end += 1
    while values[end:end + 1] == ["["]:
        depth = 1
        end += 1
        while end < len(values) and depth:
            depth += (values[end] == "[") - (values[end] == "]")
            end += 1
    if (end + 2 < len(values) and values[end] == "." and values[end + 1] in MUTATING_METHODS
            and values[end + 2] in {"(", "{"}):
        return tuple(values[end:end + 2])
    operator = end
    while end < len(values) and values[end] in {"+", "-", "*", "/", "%", "&", "|", "^", "<", ">", "?"}:
        end += 1
    if values[end:end + 1] != ["="] or values[end + 1:end + 2] == ["="]:
        return None
    if values[operator:end] in [[">"], ["<"]]:
        return None
    return tuple(values[operator:end + 1] + values[end + 1:end + 4])


def occurrences(file, source):
    if not file.endswith(".swift"):
        return
    for stream, index, scope in scoped(source):
        if index == 0:
            values = [token.value for token in stream]
            bindings = receiver_fields(values)
        name = values[index]
        if name not in FIELD_NAMES:
            continue
        previous = values[index - 1] if index else ""
        if previous in {"var", "let", "case"}:
            continue
        owner = next(
            (part.split(":", 1)[1] for part in reversed(scope)
             if part.startswith(("class:", "struct:", "extension:", "actor:", "enum:"))),
            "",
        )
        if previous == ".":
            receiver = values[index - 2] if index >= 2 else ""
            if receiver in {"?", "!"}:
                receiver = values[index - 3] if index >= 3 else ""
            if receiver == "self":
                field_names = FIELDS.get(owner, set())
            else:
                field_names = bindings.get(receiver.lstrip("$"), set())
        else:
            field_names = FIELDS.get(owner, set())
        if name not in field_names and not (name in DISTINCT_FIELDS and previous == "."):
            continue
        shape = write_shape(values, index)
        if not shape:
            continue
        function = next((part for part in reversed(scope) if part.startswith(("func:", "init:"))), "")
        yield (file, owner, function, name, shape), stream[index].line


def check(repository):
    baseline = Counter(
        key for file in (STORE, SPEECH, INSIGHTS)
        for key, _ in occurrences(file, git_source(BASELINE, file))
    )
    findings = []
    for file, source in repository.sources.items():
        for key, line in occurrences(file, source):
            if baseline[key] > 0:
                baseline[key] -= 1
            else:
                message = f"Send an event through the existing handle path to change `{key[3]}`."
                findings.append(Finding(file, line, message))
    return findings


def write_in_store(root):
    with (root / STORE).open("a") as source:
        source.write("\nextension MiraStore { func bypass() { library = .unopened } }\n")


def write_from_view(root):
    target = root / "CreatorContentOS/Mira/Views/MiraRootView.swift"
    with target.open("a") as source:
        source.write("\nfunc bypass(_ owner: MiraStore) { owner.location = .today(.init()) }\n")


def write_request_entry(root):
    path = root / STORE
    source = path.read_text().replace(
        "requestStates[jobID] = next",
        "self.requestStates[jobID] = .done",
    )
    path.write_text(source)


def write_voice_state(root):
    with (root / SPEECH).open("a") as source:
        source.write("\nextension MiraSpeechInput { func bypass() { self.state = .denied } }\n")


RECONSTRUCTIONS = [
    ("a library write outside the store transition", write_in_store),
    ("a navigation write from a view", write_from_view),
    ("a request dictionary entry set without the handle result", write_request_entry),
    ("a voice state write outside the speech transition", write_voice_state),
]
