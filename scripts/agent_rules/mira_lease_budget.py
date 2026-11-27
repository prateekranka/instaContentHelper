import re

from .support import Finding

FUNCTION = "supabase/functions/mira-generation/"
POLICY = FUNCTION + "job-policy.ts"
WORKER = FUNCTION + "index.ts"
PROVIDER = FUNCTION + "provider.ts"
ADAPTERS = FUNCTION + "adapters.ts"
PICTURES = FUNCTION + "shot-pictures.ts"
MIGRATIONS = "supabase/migrations"
HISTORY = [("725c646", [WORKER, PROVIDER, ADAPTERS])]
RECONSTRUCTED = "a provider call budget with less than 20 seconds of lease margin"

DEFINITION = re.compile(
    r"create\s+(?:or\s+replace\s+)?function\s+public\.(?P<name>\w+)"
    r"\s*\((?P<args>[^)]*)\)[^;]*?\bas\s+(?P<tag>\$\w*\$)"
    r"(?P<body>.*?)(?P=tag)\s*;",
    re.IGNORECASE | re.DOTALL,
)


def latest_functions(root):
    definitions = {}
    for migration in sorted((root / MIGRATIONS).glob("*mira*.sql")):
        for match in DEFINITION.finditer(migration.read_text()):
            count = len(match["args"].split(",")) if match["args"].strip() else 0
            definitions[match["name"].lower(), count] = (
                str(migration.relative_to(root)), match["body"]
            )
    return definitions


def number(source, name):
    match = re.search(rf"const {name}\s*=\s*([\d_]+);", source)
    return int(match[1].replace("_", "")) if match else 0


def check(repository):
    policy = (repository.root / POLICY).read_text()
    worker = (repository.root / WORKER).read_text()
    provider = (repository.root / PROVIDER).read_text()
    adapters = (repository.root / ADAPTERS).read_text()
    pictures = (repository.root / PICTURES).read_text()
    functions = latest_functions(repository.root)
    claim_file, claim = functions.get(("mira_claim", 2), (MIGRATIONS, ""))
    transition_file, transition = functions.get(("mira_enforce_job_transition", 0), (MIGRATIONS, ""))
    legacy_file, legacy = functions.get(("mira_claim", 1), (MIGRATIONS, ""))
    picture_file, picture_claim = functions.get(("mira_claim_shot_pictures", 3), (MIGRATIONS, ""))
    tracked_file, tracked_claim = functions.get(("mira_claim_shot_pictures", 4), (MIGRATIONS, ""))
    minimum = number(policy, "MIN_LEASE_SECONDS")
    checks = [
        (POLICY, number(policy, "LEASE_MARGIN_MS") >= 20_000,
         "reserve at least 20 seconds after the provider deadline"),
        (POLICY, all(part in policy for part in [
            "const timeoutMs = operation ? AI_TIMEOUT_MS[operation] : TEXT_TIMEOUT_MS;",
            "const timeoutMs = AI_TIMEOUT_MS[operation];",
            "MIN_LEASE_SECONDS,",
            "Math.ceil((timeoutMs + LEASE_MARGIN_MS + CLAIM_BUFFER_MS) / 1_000)",
            "Date.parse(leaseUntil) - Date.now() >= timeoutMs + LEASE_MARGIN_MS",
            "AbortSignal.timeout(timeoutMs)",
        ]), "size and check the lease with the same timeout used for the provider deadline"),
        (WORKER, all(part in worker for part in [
            "leaseSeconds(operation.data)", "p_lease_seconds: claimLeaseSeconds",
            "const signal = providerDeadline(input.operation, row.lease_until);",
            "generator(input, env, signal, undefined, onStep)",
        ]), "request the sized lease and check the returned expiry before generation"),
        (PROVIDER, re.search(r"generateJson\(\{\s*system,\s*input,\s*schema,\s*signal,", provider),
         "pass the worker deadline to the provider adapter"),
        (ADAPTERS, len(re.findall(r"\bsignal,\s*body:", adapters)) == len(re.findall(r"\b(?:fetchFn|fetch)\s*\(", adapters)) > 0
         and not re.search(r"\bsignal\s*:|AbortSignal\.timeout", adapters.replace("signal: AbortSignal;", "")),
         "every provider fetch must use the worker signal"),
        (PICTURES, all(part in pictures for part in [
            'p_lease_seconds: leaseSeconds("shotPictures")',
            'p_track_dispatch: true',
            'providerDeadline("shotPictures", row.lease_until)',
            'generatePicture(shot, env, signal, fetchFn)',
        ]) and len(re.findall(r"\bsignal,\s*body:", pictures)) == 1,
         "guard each picture provider request with the sized lease and pass its deadline to fetch"),
        (picture_file, re.search(
            r"public\.mira_claim_shot_pictures\(\s*p_job_id\s*,\s*p_lease_id\s*,\s*p_lease_seconds\s*,\s*false\s*\)",
            picture_claim, re.IGNORECASE),
         "preserve the legacy picture lease and reservation accounting"),
        (tracked_file, "shotPictures: 100_000" in policy
         and re.search(r"p_lease_seconds\s*<\s*125\s+then", tracked_claim, re.IGNORECASE),
         "keep the picture SQL lease floor in sync with the 100-second call limit and its margins"),
        (claim_file, minimum == 90
         and re.search(rf"p_lease_seconds\s*<\s*{minimum}\s+then", claim, re.IGNORECASE),
         "keep the SQL lease floor in sync with the worker"),
        (transition_file, re.search(
            rf"new\.lease_until\s*>=\s*clock_timestamp\(\)\s*\+\s*interval\s+'{minimum} seconds'",
            transition, re.IGNORECASE),
         "apply the same lease floor to direct claim transitions"),
        (legacy_file, re.search(r"public\.mira_claim\(\s*p_id\s*,\s*90\s*\)", legacy, re.IGNORECASE),
         "preserve the legacy 90-second claim"),
    ]
    return [Finding(file, 1, message) for file, valid, message in checks if not valid]


def reconstruct(root):
    path = root / POLICY
    source = path.read_text()
    path.write_text(re.sub(r"(const LEASE_MARGIN_MS\s*=\s*)[\d_]+", r"\g<1>19_999", source))


def weaken_latest_sql_floor(root):
    file, body = latest_functions(root)["mira_claim", 2]
    path = root / file
    changed = re.sub(r"(p_lease_seconds\s*<\s*)90(\s+then)", r"\g<1>89\2", body, flags=re.IGNORECASE)
    if changed == body:
        raise RuntimeError("The latest Mira text claim has no 90-second floor to weaken.")
    path.write_text(path.read_text().replace(body, changed, 1))


RECONSTRUCTIONS = [("a weakened lease floor in the newest Mira claim migration", weaken_latest_sql_floor)]
