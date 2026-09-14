#!/usr/bin/env python3
"""
Broadcast TourSplit Update Notification to FCM topic 'app_updates'.
Can be executed in GitHub Actions or locally with a Firebase Service Account JSON.
Usage:
  python3 scripts/broadcast_update_notification.py <version> [release_notes]
"""

import os
import sys
import json
import urllib.request
import urllib.parse

PROJECT_ID = "tourexpensetracker-3da34"
TOPIC = "app_updates"

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/broadcast_update_notification.py <version> [release_notes]")
        sys.exit(1)

    version = sys.argv[1].lstrip("v")
    notes = sys.argv[2] if len(sys.argv) > 2 else f"TourSplit v{version} is now available."

    service_account_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT")
    service_account_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")

    creds = None
    if service_account_json:
        try:
            creds = json.loads(service_account_json)
        except Exception as e:
            print(f"Error parsing FIREBASE_SERVICE_ACCOUNT env var: {e}")
    elif service_account_path and os.path.exists(service_account_path):
        try:
            with open(service_account_path, "r") as f:
                creds = json.load(f)
        except Exception as e:
            print(f"Error reading {service_account_path}: {e}")

    if not creds:
        print("Notice: No FIREBASE_SERVICE_ACCOUNT found.")
        print("To automatically send FCM push notifications on release:")
        print("  1. In Firebase Console -> Project Settings -> Service accounts, generate a private key.")
        print("  2. Add the JSON content as secret 'FIREBASE_SERVICE_ACCOUNT' in your GitHub repo settings.")
        print(f"Update payload prepared for topic '{TOPIC}' with version v{version}.")
        sys.exit(0)

    try:
        import time
        import base64
        import hmac
        import hashlib

        # Create JWT for Google OAuth2
        now = int(time.time())
        header = {"alg": "RS256", "typ": "JWT"}
        payload = {
            "iss": creds["client_email"],
            "scope": "https://www.googleapis.com/auth/firebase.messaging",
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600
        }

        # Sign JWT using cryptography if available
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding

        private_key = serialization.load_pem_private_key(
            creds["private_key"].encode("utf-8"),
            password=None
        )

        b64_header = base64.urlsafe_b64encode(json.dumps(header).encode("utf-8")).decode("utf-8").rstrip("=")
        b64_payload = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8").rstrip("=")
        signing_input = f"{b64_header}.{b64_payload}".encode("utf-8")

        signature = private_key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
        b64_sig = base64.urlsafe_b64encode(signature).decode("utf-8").rstrip("=")
        jwt_token = f"{b64_header}.{b64_payload}.{b64_sig}"

        # Request Google OAuth token
        token_req = urllib.request.Request(
            "https://oauth2.googleapis.com/token",
            data=urllib.parse.urlencode({
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": jwt_token,
            }).encode("utf-8"),
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        with urllib.request.urlopen(token_req) as resp:
            token_data = json.loads(resp.read().decode("utf-8"))
            access_token = token_data["access_token"]

        # Send FCM Message
        fcm_payload = {
            "message": {
                "topic": TOPIC,
                "notification": {
                    "title": "TourSplit Update Available",
                    "body": f"Version v{version} is available. Tap to update with 1-click."
                },
                "data": {
                    "type": "app_update",
                    "version": version,
                    "release_notes": notes
                },
                "android": {
                    "priority": "high",
                    "notification": {
                        "channel_id": "tour_expense_tracker_channel",
                        "priority": "max",
                        "default_sound": True,
                        "default_vibrate_timings": True
                    }
                }
            }
        }

        fcm_req = urllib.request.Request(
            f"https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send",
            data=json.dumps(fcm_payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            }
        )
        with urllib.request.urlopen(fcm_req) as resp:
            print(f"FCM update broadcast sent successfully: {resp.read().decode('utf-8')}")

    except Exception as e:
        print(f"Failed to broadcast FCM message: {e}")

if __name__ == "__main__":
    main()
