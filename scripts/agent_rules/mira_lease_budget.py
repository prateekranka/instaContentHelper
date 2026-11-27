import re

from .support import Finding

FUNCTION = "supabase/functions/mira-generation/"
POLICY = FUNCTION + "job-policy.ts"
WORKER = FUNCTION + "index.ts"
PROVIDER = FUNCTION + "provider.ts"
ADAPTERS = FUNCTION + "adapters.ts"
PICTURES = FUNCTION + "shot-pictures.ts"
PICTURE_MIGRATION = "supabase/migrations/20261127200000_mira_steps_and_shot_pictures.sql"
MIGRATION = "supabase/migrations/20261127190000_mira_job_state_machine.sql"
HISTORY = [("725c646", [WORKER, PROVIDER, ADAPTERS])]
RECONSTRUCTED = "a provider call budget with less than 20 seconds of lease margin"


def number(source, name):
    match = re.search(rf"const {name}\s*=\s*([\d_]+);", source)
    return int(match[1].replace("_", "")) if match else 0


def check(repository):
    policy = (repository.root / POLICY).read_text()
    worker = (repository.root / WORKER).read_text()
    provider = (repository.root / PROVIDER).read_text()
    adapters = (repository.root / ADAPTERS).read_text()
    migration = (repository.root / MIGRATION).read_text()
    pictures = (repository.root / PICTURES).read_text()
    picture_migration = (repository.root / PICTURE_MIGRATION).read_text()
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
            'providerDeadline("shotPictures", row.lease_until)',
            'generatePicture(shot, env, signal, fetchFn)',
        ]) and len(re.findall(r"\bsignal,\s*body:", pictures)) == 1,
         "guard each picture provider request with the sized lease and pass its deadline to fetch"),
        (PICTURE_MIGRATION, "shotPictures: 100_000" in policy
         and "p_lease_seconds < 125 then" in picture_migration,
         "keep the picture SQL lease floor in sync with the 100-second call limit and its margins"),
        (MIGRATION, minimum == 90 and f"p_lease_seconds < {minimum} then" in migration
         and "public.mira_claim(p_id, 90)" in migration,
         "keep the SQL lease floor in sync with the worker and preserve the legacy 90-second claim"),
    ]
    return [Finding(file, 1, message) for file, valid, message in checks if not valid]


def reconstruct(root):
    path = root / POLICY
    source = path.read_text()
    path.write_text(re.sub(r"(const LEASE_MARGIN_MS\s*=\s*)[\d_]+", r"\g<1>19_999", source))
