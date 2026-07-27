#!/usr/bin/env python3.11
"""Upload App Store screenshots via ASC API."""

import hashlib, time, json, sys, os
from pathlib import Path
import jwt, requests

KEY_ID    = "MN6H2P6385"
ISSUER_ID = "69a6de6f-2572-47e3-e053-5b8c7c11a4d1"
KEY_PATH  = Path.home() / ".private_keys" / "AuthKey_MN6H2P6385.p8"
BUNDLE_ID = "com.123words.app"
BASE      = "https://api.appstoreconnect.apple.com/v1"

SCREENSHOTS = {
    "APP_IPHONE_67": Path("AppStore/Screenshots/iPhone"),
    "APP_IPAD_PRO_3GEN_129": Path("AppStore/Screenshots/iPad"),
}

def make_token():
    key = KEY_PATH.read_text()
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": KEY_ID})

def headers():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}

def get(path):
    r = requests.get(f"{BASE}{path}", headers=headers())
    r.raise_for_status()
    return r.json()

def post(path, body):
    r = requests.post(f"{BASE}{path}", headers=headers(), json=body)
    if not r.ok:
        print(f"  POST {path} failed {r.status_code}: {r.text[:300]}")
        r.raise_for_status()
    return r.json()

def patch(path, body):
    r = requests.patch(f"{BASE}{path}", headers=headers(), json=body)
    r.raise_for_status()
    return r.json()

def upload_bytes(url, data, content_type):
    r = requests.put(url, data=data, headers={"Content-Type": content_type})
    r.raise_for_status()

# ── 1. Find the app ──────────────────────────────────────────────────────────
print("Finding app…")
apps = get(f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
if not apps:
    sys.exit(f"No app found for {BUNDLE_ID}")
app_id = apps[0]["id"]
print(f"  App ID: {app_id}")

# ── 2. Find the editable app store version ───────────────────────────────────
print("Finding editable version…")
versions = get(f"/apps/{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION,WAITING_FOR_REVIEW,REJECTED,DEVELOPER_REJECTED,METADATA_REJECTED,INVALID_BINARY,READY_FOR_REVIEW")["data"]
if not versions:
    # Try any non-live version
    versions = get(f"/apps/{app_id}/appStoreVersions")["data"]
    versions = [v for v in versions if v["attributes"]["appStoreState"] not in ("READY_FOR_SALE", "REMOVED_FROM_SALE")]
if not versions:
    sys.exit("No editable version found. Create one in App Store Connect first.")
version = versions[0]
version_id = version["id"]
print(f"  Version ID: {version_id}  state: {version['attributes']['appStoreState']}")

# ── 3. Get localizations (en-US) ─────────────────────────────────────────────
print("Finding en-US localization…")
locs = get(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0])
loc_id = loc["id"]
print(f"  Localization ID: {loc_id}")

# ── 4. Delete existing screenshot sets so we start clean ─────────────────────
print("Clearing existing screenshot sets…")
existing = get(f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]
for ss in existing:
    dtype = ss["attributes"]["screenshotDisplayType"]
    if dtype in SCREENSHOTS:
        r = requests.delete(f"{BASE}/appScreenshotSets/{ss['id']}", headers=headers())
        print(f"  Deleted existing set: {dtype}")

# ── 5. Upload for each display type ──────────────────────────────────────────
for display_type, folder in SCREENSHOTS.items():
    files = sorted(folder.glob("0*.png"))
    if not files:
        print(f"  No files in {folder}, skipping.")
        continue

    print(f"\nCreating screenshot set: {display_type} ({len(files)} files)")
    ss_set = post("/appScreenshotSets", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": display_type},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}
    }})
    set_id = ss_set["data"]["id"]

    for i, filepath in enumerate(files):
        data = filepath.read_bytes()
        md5  = hashlib.md5(data).hexdigest()
        size = len(data)
        name = filepath.name

        print(f"  [{i+1}/{len(files)}] {name} ({size:,} bytes)")

        # Reserve
        res = post("/appScreenshots", {"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": name, "fileSize": size},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}
        }})
        sc_id = res["data"]["id"]
        ops   = res["data"]["attributes"]["uploadOperations"]

        # Upload each chunk
        for op in ops:
            offset = op["offset"]
            length = op["length"]
            chunk  = data[offset:offset+length]
            req_headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            r = requests.put(op["url"], data=chunk, headers=req_headers)
            r.raise_for_status()

        # Commit
        patch(f"/appScreenshots/{sc_id}", {"data": {
            "type": "appScreenshots",
            "id": sc_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": md5}
        }})
        print(f"    ✓ committed")

print("\n✅  All screenshots uploaded successfully.")
