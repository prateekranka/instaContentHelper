from .support import scoped

HISTORY = [
    ("ea5db00^", ["CreatorContentOS/Data/SupabaseDTOs.swift"]),
    ("8ce636a^", ["CreatorContentOS/Data/SupabaseDTOs.swift"]),
]


def occurrences(file, source):
    if not file.endswith(".swift"):
        return
    for stream, i, scope in scoped(source):
        token = stream[i]
        if token.value in {"DateFormatter", "ISO8601DateFormatter"} and i + 1 < len(stream) and stream[i + 1].value in {"(", "."}:
            if stream[i + 1].value == "." and [t.value for t in stream[i + 2:i + 4]] != ["init", "("]:
                continue
            yield (file, scope, token.value), token.line


def check(repository):
    return repository.added(occurrences, "Do not allocate another formatter at this call site. Use SupabaseDateFormatting and its mutex-protected withFormatter cache; add the required format operation there.")
