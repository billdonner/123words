#!/usr/bin/env python3.11
"""Create a new editable App Store version (draft). Does NOT submit for review."""

import time, sys
from pathlib import Path
import jwt, requests

KEY_ID    = "MN6H2P6385"
ISSUER_ID = "69a6de6f-2572-47e3-e053-5b8c7c11a4d1"
KEY_PATH  = Path.home() / ".private_keys" / "AuthKey_MN6H2P6385.p8"
BUNDLE_ID = "com.123words.app"
BASE      = "https://api.appstoreconnect.apple.com/v1"
# Must match CFBundleShortVersionString (MARKETING_VERSION in project.yml)
NEW_VERSION = sys.argv[1] if len(sys.argv) > 1 else "1.1"

def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER_ID, "iat": now, "exp": now + 1200,
                        "aud": "appstoreconnect-v1"},
                       KEY_PATH.read_text(), algorithm="ES256",
                       headers={"kid": KEY_ID})

def h():
    return {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}

apps = requests.get(f"{BASE}/apps?filter[bundleId]={BUNDLE_ID}", headers=h()).json()["data"]
app_id = apps[0]["id"]
print(f"App ID: {app_id}")

versions = requests.get(f"{BASE}/apps/{app_id}/appStoreVersions", headers=h()).json()["data"]
for v in versions:
    a = v["attributes"]
    print(f"  existing: {a['versionString']}  {a['appStoreState']}")
    if a["versionString"] == NEW_VERSION and a["appStoreState"] not in ("READY_FOR_SALE", "REMOVED_FROM_SALE"):
        print(f"Version {NEW_VERSION} already editable: {v['id']}")
        sys.exit(0)

r = requests.post(f"{BASE}/appStoreVersions", headers=h(), json={"data": {
    "type": "appStoreVersions",
    "attributes": {"platform": "IOS", "versionString": NEW_VERSION},
    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}
}})
if not r.ok:
    sys.exit(f"Create failed {r.status_code}: {r.text[:400]}")
print(f"✅  Created draft version {NEW_VERSION}: {r.json()['data']['id']}")
