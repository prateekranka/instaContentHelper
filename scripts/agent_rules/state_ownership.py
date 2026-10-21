from .support import scoped

HISTORY = [
    ("240eba8^", ["CreatorContentOS/App/AppServices.swift"]),
    ("92406c5^", ["CreatorContentOS/App/AppServices.swift"]),
]


def occurrences(file, source):
    if not file.startswith(("CreatorContentOS/App/", "CreatorContentOS/Features/")):
        return
    for stream, i, scope in scoped(source):
        token = stream[i]
        if any(part.startswith(("func:", "function:", "init:", "subscript:", "var:", "let:")) for part in scope):
            continue
        if token.value != "var" or i + 3 >= len(stream) or stream[i + 2].value != ":":
            continue
        name = stream[i + 1].value
        end = i + 3
        while end < len(stream) and stream[end].value not in {"{", "=", "}"} and stream[end].line == token.line:
            end += 1
        types = {t.value for t in stream[i + 3:end]}
        if not types.intersection({"DailyCard", "GeneratedDailyCardDraft", "ContentIntent", "UnsyncedTodayDecision", "PendingFirstIdeaHandoff", "AcceptedDayGeneration"}) and name not in {"shotSceneIDs", "pendingFirstIdea", "unsyncedTodayDecision"}:
            continue
        computed = end < len(stream) and stream[end].value == "{" and (end + 1 == len(stream) or stream[end + 1].value not in {"didSet", "willSet"})
        if not computed:
            yield (file, scope, name), token.line


def check(repository):
    return repository.added(occurrences, "Do not add a second mutable day or saved-work owner. Use DayStore.transition, DayStore.projection, and ContentIntent through AppServices.")
