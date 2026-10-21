from .support import Finding, bodies, contains, scoped

HISTORY = [
    ("8ce636a^", ["CreatorContentOS/App/AppServices.swift"]),
    ("8ce636a^", ["CreatorContentOS/Data/TodayCacheStore.swift"]),
]


def synchronous_calls(file, source):
    if not file.startswith(("CreatorContentOS/App/", "CreatorContentOS/Features/")):
        return
    for stream, i, scope in scoped(source):
        token = stream[i]
        if token.value == "saveSnapshot" and i > 0 and stream[i - 1].value == "." and stream[i + 1].value == "(":
            yield (file, scope), token.line


def check(repository):
    findings = repository.added(synchronous_calls, "Use AppServices.persistDaySnapshot or queueDaySnapshot; await persistence before sending an intent. Do not call synchronous saveSnapshot from app flows.")
    file = "CreatorContentOS/Data/TodayCacheStore.swift"
    source = repository.sources.get(file, "")
    for body in bodies(source, "protocol", "TodayCacheStoring"):
        for token in body:
            if token.value == "saveSnapshot":
                findings.append(Finding(file, token.line, "Keep synchronous saveSnapshot off TodayCacheStoring. AppServices must use persistDaySnapshot and the required async saveSnapshotInBackground; setup can use concrete FileTodayCacheStore."))
    for body in bodies(source, "extension", "TodayCacheStoring"):
        for token in body:
            if token.value == "saveSnapshotInBackground":
                findings.append(Finding(file, token.line, "Remove the TodayCacheStoring default save fallback. Implement saveSnapshotInBackground explicitly on each store; FileTodayCacheStore uses its serial fileQueue."))
    implementations = list(bodies(source, "func", "saveSnapshotInBackground"))
    queued = [body for body in implementations if contains(body, ["Self", ".", "fileQueue", ".", "async", "{"])]
    if not queued or not all(contains(body, ["try", "saveSnapshotOnFileQueue", "("]) for body in queued):
        findings.append(Finding(file, 1, "FileTodayCacheStore must implement saveSnapshotInBackground on its serial fileQueue; use withCheckedThrowingContinuation and saveSnapshotOnFileQueue."))
    return findings
