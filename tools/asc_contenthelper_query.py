#!/usr/bin/env python3
"""One-off ASC queries for ContentHelper (com.prateekranka.creatorcontenthelper)."""
import base64, json, time, urllib.error, urllib.request

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

BUNDLE = "com.prateekranka.creatorcontenthelper"
data = get("/v1/apps?filter[bundleId]=" + BUNDLE)
apps = data.get("data", [])
if not apps:
    print("NO APP RECORD for", BUNDLE)
    raise SystemExit(1)
app = apps[0]
app_id = app["id"]
print("APP:", app_id, app["attributes"]["name"], app["attributes"]["bundleId"])

groups = get(f"/v1/apps/{app_id}/betaGroups")
for g in groups.get("data", []):
    print("GROUP:", g["id"], g["attributes"]["name"], "testers=", g["attributes"].get("betaTesterCount"))

builds = get(f"/v1/builds?filter[app]={app_id}&limit=5&sort=-uploadedDate")
for b in builds.get("data", []):
    attrs = b["attributes"]
    print("BUILD:", b["id"], "version=", attrs.get("version"), "state=", attrs.get("processingState"), "uploaded=", attrs.get("uploadedDate", "")[:19])
