#!/usr/bin/env python3
"""
App Store Connect API helper for bin/release-ios.

Usage:
  uv run --with PyJWT,cryptography,requests bin/asc_api.py \\
      --key-id <KID> --issuer-id <ISS> --key-file <path.p8> \\
      <subcommand> [args]

Each subcommand prints its result to stdout (one value per line).
Errors are printed to stderr and the script exits non-zero.
"""

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com"


# ── JWT ────────────────────────────────────────────────────────────────────────

def make_token(key_id: str, issuer_id: str, key_file: str) -> str:
    key = Path(key_file).read_text()
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": key_id})


# ── HTTP helpers ───────────────────────────────────────────────────────────────

def get(token: str, path: str, params: dict | None = None) -> dict:
    r = requests.get(
        f"{BASE}{path}",
        headers={"Authorization": f"Bearer {token}"},
        params=params,
        timeout=30,
    )
    _check(r)
    return r.json()


def post(token: str, path: str, body: dict) -> dict:
    r = requests.post(
        f"{BASE}{path}",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json=body,
        timeout=30,
    )
    _check(r)
    return r.json()


def patch(token: str, path: str, body: dict) -> dict:
    r = requests.patch(
        f"{BASE}{path}",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json=body,
        timeout=30,
    )
    _check(r)
    return r.json()


def delete(token: str, path: str) -> None:
    r = requests.delete(
        f"{BASE}{path}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    if r.status_code not in (200, 204):
        _check(r)


def _check(r: requests.Response) -> None:
    if not r.ok:
        try:
            detail = json.dumps(r.json(), indent=2)
        except Exception:
            detail = r.text
        print(f"ASC API error {r.status_code} {r.url}:\n{detail}", file=sys.stderr)
        sys.exit(1)


def put_binary(url: str, data: bytes, content_type: str) -> None:
    r = requests.put(url, data=data, headers={"Content-Type": content_type}, timeout=120)
    if not r.ok:
        print(f"Upload error {r.status_code}: {r.text}", file=sys.stderr)
        sys.exit(1)


# ── Subcommands ────────────────────────────────────────────────────────────────

def cmd_get_app_id(token: str, args: argparse.Namespace) -> None:
    data = get(token, "/v1/apps", params={"filter[bundleId]": args.bundle_id})
    items = data.get("data", [])
    if not items:
        print(f"No app found for bundle ID {args.bundle_id}", file=sys.stderr)
        sys.exit(1)
    print(items[0]["id"])


def cmd_find_version(token: str, args: argparse.Namespace) -> None:
    data = get(token, f"/v1/apps/{args.app_id}/appStoreVersions", params={
        "filter[platform]": "IOS",
        "filter[versionString]": args.version,
    })
    items = data.get("data", [])
    if items:
        print(items[0]["id"])
    # empty output signals "not found"


def cmd_create_version(token: str, args: argparse.Namespace) -> None:
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": args.version,
                "releaseType": args.release_type,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": args.app_id}},
            },
        }
    }
    data = post(token, "/v1/appStoreVersions", body)
    print(data["data"]["id"])


def cmd_get_localization(token: str, args: argparse.Namespace) -> None:
    data = get(token, f"/v1/appStoreVersions/{args.version_id}/appStoreVersionLocalizations",
               params={"filter[locale]": args.locale})
    items = data.get("data", [])
    if not items:
        print(f"No localization found for locale {args.locale}", file=sys.stderr)
        sys.exit(1)
    print(items[0]["id"])


def cmd_update_localization(token: str, args: argparse.Namespace) -> None:
    attrs: dict = {}
    if args.whats_new:
        attrs["whatsNew"] = Path(args.whats_new).read_text().strip()
    if args.description:
        attrs["description"] = Path(args.description).read_text().strip()
    if args.keywords:
        attrs["keywords"] = Path(args.keywords).read_text().strip()
    if args.support_url:
        attrs["supportUrl"] = Path(args.support_url).read_text().strip()
    if args.marketing_url:
        attrs["marketingUrl"] = Path(args.marketing_url).read_text().strip()
    if not attrs:
        print("No localization fields supplied — nothing to update.", file=sys.stderr)
        return
    patch(token, f"/v1/appStoreVersionLocalizations/{args.loc_id}", {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": args.loc_id,
            "attributes": attrs,
        }
    })


def cmd_find_build(token: str, args: argparse.Namespace) -> None:
    data = get(token, "/v1/builds", params={
        "filter[app]": args.app_id,
        "filter[preReleaseVersion.version]": args.version,
        "filter[processingState]": "VALID",
        "sort": "-uploadedDate",
        "limit": "1",
    })
    items = data.get("data", [])
    if items:
        print(items[0]["id"])
    # empty output signals "not found"


def cmd_associate_build(token: str, args: argparse.Namespace) -> None:
    patch(token, f"/v1/appStoreVersions/{args.version_id}/relationships/build", {
        "data": {"type": "builds", "id": args.build_id}
    })


def cmd_upload_screenshots(token: str, args: argparse.Namespace) -> None:
    groups = []
    screenshots_dir = Path(args.screenshots_dir)
    iphone_files = sorted(screenshots_dir.glob("iphone-*.png"))
    ipad_files = sorted(screenshots_dir.glob("ipad-*.png"))

    if iphone_files:
        groups.append(("APP_IPHONE_67", iphone_files, 1320, 2868))
    if ipad_files:
        groups.append(("APP_IPAD_PRO_3GEN_129", ipad_files, 2752, 2064))

    if not groups:
        print("No screenshots found (iphone-*.png / ipad-*.png).", file=sys.stderr)
        sys.exit(1)

    for display_type, files, exp_w, exp_h in groups:
        _validate_dimensions(files, exp_w, exp_h, display_type)
        loc_id = args.loc_id
        set_id = _get_or_create_screenshot_set(token, loc_id, display_type)
        _clear_screenshot_set(token, set_id)
        for img_path in files:
            _upload_one_screenshot(token, set_id, img_path)
            print(f"  uploaded {img_path.name} → {display_type}")


def _validate_dimensions(files: list, exp_w: int, exp_h: int, display_type: str) -> None:
    import subprocess
    for f in files:
        result = subprocess.run(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(f)],
            capture_output=True, text=True, check=True,
        )
        w = h = 0
        for line in result.stdout.splitlines():
            if "pixelWidth" in line:
                w = int(line.split()[-1])
            elif "pixelHeight" in line:
                h = int(line.split()[-1])
        # Accept both portrait and landscape orientations
        dims = {(w, h), (h, w)}
        if (exp_w, exp_h) not in dims and (exp_h, exp_w) not in dims:
            print(
                f"Error: {f.name} is {w}×{h} px; expected {exp_w}×{exp_h} for {display_type}.",
                file=sys.stderr,
            )
            sys.exit(1)


def _get_or_create_screenshot_set(token: str, loc_id: str, display_type: str) -> str:
    # Check for existing set on this localization
    data = get(token, f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    for item in data.get("data", []):
        if item["attributes"].get("screenshotDisplayType") == display_type:
            return item["id"]
    # Create a new set
    body = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                }
            },
        }
    }
    result = post(token, "/v1/appScreenshotSets", body)
    return result["data"]["id"]


def _clear_screenshot_set(token: str, set_id: str) -> None:
    data = get(token, f"/v1/appScreenshotSets/{set_id}/appScreenshots")
    for item in data.get("data", []):
        delete(token, f"/v1/appScreenshots/{item['id']}")


def _upload_one_screenshot(token: str, set_id: str, img_path: Path) -> None:
    img_data = img_path.read_bytes()
    file_size = len(img_data)
    md5 = hashlib.md5(img_data).hexdigest()

    # Reserve upload slot
    reservation = post(token, "/v1/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileSize": file_size,
                "fileName": img_path.name,
            },
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}
                }
            },
        }
    })
    screenshot_id = reservation["data"]["id"]
    upload_ops = reservation["data"]["attributes"].get("uploadOperations", [])

    # Upload to Apple CDN
    for op in upload_ops:
        url = op["url"]
        offset = op.get("offset", 0)
        length = op.get("length", file_size)
        headers_list = op.get("requestHeaders", [])
        chunk = img_data[offset: offset + length]
        content_type = next(
            (h["value"] for h in headers_list if h["name"].lower() == "content-type"),
            "image/png",
        )
        put_binary(url, chunk, content_type)

    # Confirm upload
    patch(token, f"/v1/appScreenshots/{screenshot_id}", {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": md5,
            },
        }
    })


# ── CLI ────────────────────────────────────────────────────────────────────────

def main() -> None:
    root = argparse.ArgumentParser(description="App Store Connect API helper")
    root.add_argument("--key-id", required=True)
    root.add_argument("--issuer-id", required=True)
    root.add_argument("--key-file", required=True)
    sub = root.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("get-app-id")
    p.add_argument("--bundle-id", required=True)

    p = sub.add_parser("find-version")
    p.add_argument("--app-id", required=True)
    p.add_argument("--version", required=True)

    p = sub.add_parser("create-version")
    p.add_argument("--app-id", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--release-type", default="AFTER_APPROVAL",
                   choices=["AFTER_APPROVAL", "MANUAL", "SCHEDULED"])

    p = sub.add_parser("get-localization")
    p.add_argument("--version-id", required=True)
    p.add_argument("--locale", default="en-US")

    p = sub.add_parser("update-localization")
    p.add_argument("--loc-id", required=True)
    p.add_argument("--whats-new")
    p.add_argument("--description")
    p.add_argument("--keywords")
    p.add_argument("--support-url")
    p.add_argument("--marketing-url")

    p = sub.add_parser("find-build")
    p.add_argument("--app-id", required=True)
    p.add_argument("--version", required=True)

    p = sub.add_parser("associate-build")
    p.add_argument("--version-id", required=True)
    p.add_argument("--build-id", required=True)

    p = sub.add_parser("upload-screenshots")
    p.add_argument("--loc-id", required=True)
    p.add_argument("--screenshots-dir", required=True)

    args = root.parse_args()
    token = make_token(args.key_id, args.issuer_id, args.key_file)

    dispatch = {
        "get-app-id": cmd_get_app_id,
        "find-version": cmd_find_version,
        "create-version": cmd_create_version,
        "get-localization": cmd_get_localization,
        "update-localization": cmd_update_localization,
        "find-build": cmd_find_build,
        "associate-build": cmd_associate_build,
        "upload-screenshots": cmd_upload_screenshots,
    }
    dispatch[args.cmd](token, args)


if __name__ == "__main__":
    main()
