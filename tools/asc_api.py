#!/usr/bin/env python3
"""Generate an App Store Connect API JWT and call an endpoint."""
import base64, json, sys, time, urllib.error, urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

KEY_FILE = "/Users/prateekranka/.appstoreconnect/private_keys/AuthKey_P38CGMYKCV.p8"
KEY_ID = "P38CGMYKCV"
ISSUER = "50b76771-2e18-454c-81fd-845e94864820"

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

def get(path: str) -> dict:
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        headers={"Authorization": "Bearer " + jwt(), "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "apps"
    if which == "apps":
        for bundle in ["com.prateekranka.watchnote"]:
            data = get("/v1/apps?filter[bundleId]=" + bundle)
            apps = data.get("data", [])
            if apps:
                a = apps[0]
                print(f"APP EXISTS: {a['id']} name={a['attributes']['name']} bundle={a['attributes']['bundleId']}")
            else:
                print(f"NO APP RECORD for {bundle}")
    elif which == "bundleids":
        for bundle in ["com.prateekranka.watchnote", "com.prateekranka.watchnote.watchapp"]:
            data = get("/v1/bundleIds?filter[identifier]=" + bundle)
            ids = data.get("data", [])
            for b in ids:
                print(f"BUNDLE ID: {b['id']} {b['attributes']['identifier']} platform={b['attributes']['platform']}")
            if not ids:
                print(f"NO BUNDLE ID registered: {bundle}")
    elif which == "groups":
        app_id = sys.argv[2]
        data = get(f"/v1/apps/{app_id}/betaGroups")
        for g in data.get("data", []):
            print(f"GROUP: {g['id']} {g['attributes']['name']} testers={g['attributes'].get('betaTesterCount')}")
        if not data.get("data"):
            print("NO BETA GROUPS")
    elif which == "builds":
        app_id = sys.argv[2]
        data = get(f"/v1/builds?filter[app]={app_id}&limit=10")
        for b in data.get("data", []):
            a = b["attributes"]
            print(
                f"BUILD {a.get('version')}: id={b['id']} state={a.get('processingState')} "
                f"export={a.get('exportComplianceState')} encrypted={a.get('usesEncryptedExportCompliance')} "
                f"created={a.get('createdDate')}"
            )
        if not data.get("data"):
            print("NO BUILDS YET")
    elif which == "addtogroup":
        group_id, build_id = sys.argv[2], sys.argv[3]
        body = json.dumps({"data": [{"type": "builds", "id": build_id}]}).encode()
        req = urllib.request.Request(
            f"https://api.appstoreconnect.apple.com/v1/betaGroups/{group_id}/relationships/builds",
            data=body, method="POST",
            headers={
                "Authorization": "Bearer " + jwt(),
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                print(f"ADDED build {build_id} to group {group_id} (HTTP {resp.status})")
        except urllib.error.HTTPError as e:
            print(f"ADD TO GROUP ERROR {e.code}: {e.read().decode()[:400]}")
    elif which == "compliance":
        build_id, value = sys.argv[2], sys.argv[3].lower() == "true"
        body = json.dumps({
            "data": {
                "type": "builds",
                "id": build_id,
                "attributes": {"usesNonExemptEncryption": value},
            }
        }).encode()
        req = urllib.request.Request(
            f"https://api.appstoreconnect.apple.com/v1/builds/{build_id}",
            data=body, method="PATCH",
            headers={
                "Authorization": "Bearer " + jwt(),
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode())
            b = result["data"]["attributes"]
            print(f"COMPLIANCE SET: version={b.get('version')} state={b.get('processingState')} encrypted={b.get('usesEncryptedExportCompliance')} export={b.get('exportComplianceState')}")
        except urllib.error.HTTPError as e:
            print(f"COMPLIANCE ERROR {e.code}: {e.read().decode()[:400]}")
