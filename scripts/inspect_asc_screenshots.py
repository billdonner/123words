#!/usr/bin/env python3.11
"""Read-only App Store Connect screenshot inventory for 123 Words.

This script deliberately implements GET only. It prints the editable 1.12
en-US screenshot sets, their slot order, dimensions, checksums, and delivery
state so a local candidate can be compared without mutating ASC.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import jwt
import requests


KEY_ID = "MN6H2P6385"
ISSUER_ID = "69a6de6f-2572-47e3-e053-5b8c7c11a4d1"
KEY_PATH = Path.home() / ".private_keys" / f"AuthKey_{KEY_ID}.p8"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.123words.app"
VERSION = "1.12"
LOCALE = "en-US"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(),
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def get(path: str, parameters: dict[str, str] | None = None) -> dict[str, Any]:
    suffix = f"?{urlencode(parameters)}" if parameters else ""
    response = requests.get(
        f"{BASE_URL}{path}{suffix}",
        headers={"Authorization": f"Bearer {token()}"},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def main() -> None:
    apps = get("/apps", {"filter[bundleId]": BUNDLE_ID, "limit": "1"})["data"]
    if not apps:
        raise SystemExit(f"No ASC app found for {BUNDLE_ID}")
    app = apps[0]

    versions = get(
        f"/apps/{app['id']}/appStoreVersions",
        {"filter[platform]": "IOS", "limit": "200"},
    )["data"]
    version = next(
        (entry for entry in versions if entry["attributes"]["versionString"] == VERSION),
        None,
    )
    if version is None:
        raise SystemExit(f"No iOS version {VERSION} found for {BUNDLE_ID}")

    localizations = get(
        f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
        {"limit": "200"},
    )["data"]
    localization = next(
        (entry for entry in localizations if entry["attributes"]["locale"] == LOCALE),
        None,
    )
    if localization is None:
        raise SystemExit(f"No {LOCALE} localization found for iOS {VERSION}")

    sets = get(
        f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets",
        {"limit": "200"},
    )["data"]
    inventory: list[dict[str, Any]] = []
    for screenshot_set in sets:
        screenshots = get(
            f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots",
            {"limit": "200"},
        )["data"]
        slots = []
        for position, screenshot in enumerate(screenshots, start=1):
            attributes = screenshot["attributes"]
            image_asset = attributes.get("imageAsset") or {}
            delivery = attributes.get("assetDeliveryState") or {}
            slots.append(
                {
                    "position": position,
                    "id": screenshot["id"],
                    "fileName": attributes.get("fileName"),
                    "fileSize": attributes.get("fileSize"),
                    "sourceFileChecksum": attributes.get("sourceFileChecksum"),
                    "width": image_asset.get("width"),
                    "height": image_asset.get("height"),
                    "deliveryState": delivery.get("state"),
                    "deliveryWarnings": delivery.get("warnings", []),
                    "deliveryErrors": delivery.get("errors", []),
                }
            )
        inventory.append(
            {
                "displayType": screenshot_set["attributes"]["screenshotDisplayType"],
                "setID": screenshot_set["id"],
                "slotCount": len(slots),
                "slots": slots,
            }
        )

    result = {
        "observedAtUnix": int(time.time()),
        "app": {"id": app["id"], "bundleId": BUNDLE_ID, "name": app["attributes"]["name"]},
        "version": {
            "id": version["id"],
            "versionString": VERSION,
            "platform": version["attributes"]["platform"],
            "state": version["attributes"]["appStoreState"],
        },
        "locale": LOCALE,
        "sets": sorted(inventory, key=lambda entry: entry["displayType"]),
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
