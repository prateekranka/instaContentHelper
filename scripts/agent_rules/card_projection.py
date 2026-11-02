from .support import scoped

HISTORY = [
    ("8ce636a^", ["CreatorContentOS/App/AppServices.swift"]),
    ("8ce636a^", ["CreatorContentOS/Data/TodayCacheStore.swift"]),
]


def occurrences(file, source):
    if not file.endswith(".swift") or file == "CreatorContentOS/Models/Models.swift":
        return
    for stream, i, scope in scoped(source):
        token = stream[i]
        if token.value != "dailyCard" or i == 0 or stream[i - 1].value != ".":
            continue
        receiver_index = i - 2
        if receiver_index >= 0 and stream[receiver_index].value in {"?", "!"}:
            receiver_index -= 1
        receiver = stream[receiver_index].value if receiver_index >= 0 else ""
        call = i + 1 < len(stream) and stream[i + 1].value == "("
        key_path = receiver == "\\"
        if call or key_path or receiver == "revision":
            yield (file, scope, receiver, call), token.line


def check(repository):
    return repository.added(occurrences, "Do not rebuild a card on a presentation read. Use DayStore.projection(for:revisionID:), DayStore.card(revisionID:), or DayStore.readyCards.")
