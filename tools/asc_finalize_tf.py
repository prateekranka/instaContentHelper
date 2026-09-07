#!/usr/bin/env python3
"""Finalize a ContentHelper TestFlight build: wait, compliance, add to group."""
from __future__ import annotations
import base64, json, sys, time, urllib.error, urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

KEY_FILE = "/Users/prateekranka/.appstoreconnect/private_keys/AuthKey_P38CGMYKCV.p8"
KEY_ID = "P38CGMYKCV"
ISSUER = "50b76771-2e18-454c-81fd-845e94864820"
APP_ID = "6777027653"
GROUP_ID = "4b5df874-e1e9-4b73-8e9e-74e1af89b1c5"  # "Esha and I testers"
VERSION = sys.argv[1] if len(sys.argv) > 1 else "2026081101"
TIMEOUT_S = int(sys.argv[2]) if len(sys.argv) > 2 else 900


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def jwt() -> str:
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    claims = {"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    payload = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + b64url(
        json.dumps(claims, separators=(",", ":")).encode()
    )
    with open(KEY_FILE, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    der_sig = key.sign(payload.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der_sig)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return payload + "." + b64url(raw)


def request(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + jwt(),
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:400]}


def find_build():
    status, data = request("GET", f"/v1/builds?filter[app]={APP_ID}&filter[version]={VERSION}&limit=1")
    builds = data.get("data", [])
    if not builds:
        return None
    b = builds[0]
    return b["id"], b["attributes"].get("processingState"), b["attributes"].get("betaState")


def beta_detail(build_id: str):
    status, data = request("GET", f"/v1/builds/{build_id}/buildBetaDetail")
    raw = data.get("data")
    if isinstance(raw, dict):
        attrs = raw.get("attributes", {})
        return attrs.get("internalBuildState"), attrs.get("externalBuildState")
    return None


def main():
    print(f"waiting for build {VERSION} ...")
    deadline = time.time() + TIMEOUT_S
    build_id = None
    while time.time() < deadline:
        found = find_build()
        if found:
            build_id, processing, beta_state = found
            print(f"  build={build_id} processing={processing} beta={beta_state}")
            if processing == "VALID" or beta_state:
                break
        else:
            print("  build not visible yet...")
        time.sleep(30)

    if not build_id:
        print("ERROR: build never appeared")
        raise SystemExit(1)

    internal, external = beta_detail(build_id)
    print(f"  betaDetail internal={internal} external={external}")

    if internal == "MISSING_EXPORT_COMPLIANCE":
        status, resp = request(
            "PATCH",
            f"/v1/builds/{build_id}",
            {"data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}},
        )
        print(f"  compliance PATCH -> {status} {str(resp)[:200]}")
        time.sleep(30)

    # Add to group with retries while beta processing runs.
    for attempt in range(12):
        status, resp = request(
            "POST",
            f"/v1/betaGroups/{GROUP_ID}/relationships/builds",
            {"data": [{"type": "builds", "id": build_id}]},
        )
        print(f"  addtogroup attempt {attempt + 1} -> {status}")
        if status == 204:
            print(f"DONE: build {VERSION} ({build_id}) is in group {GROUP_ID}")
            return
        time.sleep(60)

    print("ERROR: could not add build to group; inspect ASC manually")
    raise SystemExit(1)


if __name__ == "__main__":
    main()
