#!/usr/bin/env python3
"""
Update GitHub Release Notes retroactively or manually.
Usage:
  python3 scripts/update_github_release.py <version>
Example:
  python3 scripts/update_github_release.py 1.4.1
"""

import os
import sys
import json
import subprocess
import urllib.request
import urllib.error

from generate_release_notes import build_release_notes

REPO = "shoruvx/TourSplit"

def get_github_token():
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    try:
        res = subprocess.run(
            ['git', 'credential', 'fill'],
            input='protocol=https\nhost=github.com\n',
            capture_output=True, text=True, check=True
        )
        for line in res.stdout.splitlines():
            if line.startswith('password='):
                return line.split('=', 1)[1]
    except Exception:
        pass
    return None

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/update_github_release.py <version>")
        sys.exit(1)

    raw_ver = sys.argv[1]
    clean_ver = raw_ver.lstrip("v")
    tag = f"v{clean_ver}"
    
    token = get_github_token()
    if not token:
        print("Error: Could not retrieve GitHub token from GITHUB_TOKEN env or git credential helper.")
        sys.exit(1)

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    notes = build_release_notes(repo_root, clean_ver)

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "TourSplit-Release-Sync",
        "Content-Type": "application/json"
    }

    # 1. Find release by tag
    get_url = f"https://api.github.com/repos/{REPO}/releases/tags/{tag}"
    try:
        req = urllib.request.Request(get_url, headers=headers)
        with urllib.request.urlopen(req) as resp:
            rel = json.load(resp)
            release_id = rel["id"]
    except urllib.error.HTTPError as e:
        print(f"Error fetching release for tag {tag}: {e}")
        sys.exit(1)

    # 2. Update release name and body
    patch_url = f"https://api.github.com/repos/{REPO}/releases/{release_id}"
    payload = {
        "name": notes["title"],
        "body": notes["body"]
    }

    try:
        patch_req = urllib.request.Request(patch_url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="PATCH")
        with urllib.request.urlopen(patch_req) as resp:
            updated = json.load(resp)
            print(f"Successfully updated GitHub Release {tag} (ID: {release_id})!")
            print(f"Title: {updated['name']}")
            print("Preview:\n" + updated['body'][:200] + "...\n")
    except urllib.error.HTTPError as e:
        print(f"Error updating release {tag}: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
