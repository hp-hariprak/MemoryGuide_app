#!/usr/bin/env python3
"""Development trigger utility for demo day and local integration testing.

Allows triggering SOS help requests and simulated GPS fixes (inside or outside
the safe zone) as the seeded patient without moving a physical device or emulator.

Refuses to execute if ENVIRONMENT=production.
"""

import argparse
import sys
from pathlib import Path

# Add backend directory to path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import httpx
from app.core.config import get_settings

PATIENT_EMAIL = "patient.dev@example.com"
PATIENT_PASSWORD = "DevPass123!"


def main() -> None:
    settings = get_settings()
    if settings.is_production:
        print("ERROR: demo_trigger.py is strictly forbidden in production environments!", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(description="MemoryGuide Demo Trigger Helper")
    parser.add_argument(
        "--action",
        choices=["help", "inside", "outside", "custom", "set-zone"],
        required=True,
        help="Action: 'help' (SOS), 'inside' (home GPS), 'outside' (breach GPS), 'custom' (arbitrary lat/lon), 'set-zone' (configure safe zone)",
    )
    parser.add_argument(
        "--lat",
        type=float,
        default=None,
        help="Latitude for 'custom' or 'set-zone' action",
    )
    parser.add_argument(
        "--lon",
        type=float,
        default=None,
        help="Longitude for 'custom' or 'set-zone' action",
    )
    parser.add_argument(
        "--radius",
        type=int,
        default=150,
        help="Radius in metres for 'set-zone' action (default: 150)",
    )
    parser.add_argument(
        "--accuracy",
        type=float,
        default=5.0,
        help="GPS accuracy in metres (default: 5.0)",
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000/api/v1",
        help="Base URL of backend API (default: http://127.0.0.1:8000/api/v1)",
    )
    parser.add_argument(
        "--message",
        default="Demo SOS help requested from trigger script",
        help="Optional message for help request",
    )
    args = parser.parse_args()

    client = httpx.Client(base_url=args.base_url.rstrip("/"), timeout=10.0)

    print(f"\n[1/3] Authenticating as seeded patient ({PATIENT_EMAIL})...")
    login_res = client.post("/auth/login", json={"email": PATIENT_EMAIL, "password": PATIENT_PASSWORD})
    if login_res.status_code != 200:
        print(f"FAILED to log in: {login_res.status_code} - {login_res.text}", file=sys.stderr)
        sys.exit(1)

    token = login_res.json()["data"]["access_token"]
    user_id = login_res.json()["data"]["user"]["id"]
    headers = {"Authorization": f"Bearer {token}"}
    print(f"       Logged in! Patient ID: {user_id}")

    print("[2/3] Fetching patient safe-zone configuration...")
    settings_res = client.get(f"/patients/{user_id}/settings", headers=headers)
    safe_lat = 12.9716
    safe_lon = 77.5946
    if settings_res.status_code == 200:
        sdata = settings_res.json().get("data", {})
        if sdata.get("safe_zone_latitude") is not None and sdata.get("safe_zone_longitude") is not None:
            safe_lat = sdata["safe_zone_latitude"]
            safe_lon = sdata["safe_zone_longitude"]
            print(f"       Using configured safe zone center: ({safe_lat}, {safe_lon})")
        else:
            print(f"       No active safe zone set in settings. Using fallback center ({safe_lat}, {safe_lon})")

    print(f"[3/3] Executing requested action: '{args.action.upper()}'...")

    if args.action == "help":
        res = client.post(
            f"/patients/{user_id}/help",
            headers=headers,
            json={"latitude": safe_lat, "longitude": safe_lon, "message": args.message},
        )
        if res.status_code == 201:
            data = res.json()["data"]
            alert_id = data["alert"]["id"]
            notif = data["notification"]
            print("\n" + "=" * 50)
            print(" SUCCESS: SOS Help Request Dispatched!")
            print(f" Alert ID:             {alert_id}")
            print(f" Alert Status:         {data['alert']['status']}")
            print(f" Notification Status:  {notif['status']}")
            print(f" Delivered Count:      {notif['delivered_count']}")
            print(f" Firebase Configured:  {notif['firebase_configured']}")
            print("=" * 50 + "\n")
        elif res.status_code == 409:
            print("\n" + "!" * 50)
            print(" COOLDOWN ACTIVE (409): An open help request is already active for this patient.")
            print(f" Response: {res.text}")
            print("!" * 50 + "\n")
        else:
            print(f"ERROR: Failed to trigger help request: {res.status_code} {res.text}", file=sys.stderr)
            sys.exit(1)

    elif args.action == "inside":
        res = client.post(
            f"/patients/{user_id}/locations",
            headers=headers,
            json={
                "latitude": safe_lat,
                "longitude": safe_lon,
                "accuracy_meters": 5.0,
            },
        )
        if res.status_code == 201:
            print("\n" + "=" * 50)
            print(" SUCCESS: Location inside safe zone posted.")
            print(f" Coordinates: ({safe_lat}, {safe_lon})")
            print(" If patient was outside, this will auto-resolve the exit alert.")
            print("=" * 50 + "\n")
        else:
            print(f"ERROR: Failed to post location: {res.status_code} {res.text}", file=sys.stderr)
            sys.exit(1)

    elif args.action == "outside":
        # Shift coordinate ~5.5 km North to guarantee crossing safe-zone boundary
        outside_lat = safe_lat + 0.05
        outside_lon = safe_lon + 0.05
        res = client.post(
            f"/patients/{user_id}/locations",
            headers=headers,
            json={
                "latitude": outside_lat,
                "longitude": outside_lon,
                "accuracy_meters": args.accuracy,
            },
        )
        if res.status_code == 201:
            print("\n" + "=" * 50)
            print(" SUCCESS: Location OUTSIDE safe zone posted.")
            print(f" Coordinates: ({outside_lat}, {outside_lon})")
            print(" Backend will trigger a geofence_exit alert and send push notification to linked caregivers.")
            print("=" * 50 + "\n")
        else:
            print(f"ERROR: Failed to post location: {res.status_code} {res.text}", file=sys.stderr)
            sys.exit(1)

    elif args.action == "custom":
        if args.lat is None or args.lon is None:
            print("ERROR: --lat and --lon are required when using --action custom", file=sys.stderr)
            sys.exit(1)
        res = client.post(
            f"/patients/{user_id}/locations",
            headers=headers,
            json={
                "latitude": args.lat,
                "longitude": args.lon,
                "accuracy_meters": args.accuracy,
            },
        )
        if res.status_code == 201:
            print("\n" + "=" * 50)
            print(" SUCCESS: Custom Location Coordinates Posted!")
            print(f" Coordinates: ({args.lat}, {args.lon}) with accuracy ±{args.accuracy}m")
            # Fetch status
            status_res = client.get(f"/patients/{user_id}/status", headers=headers)
            if status_res.status_code == 200:
                s = status_res.json().get("data", {})
                inside = s.get("inside_safe_zone")
                print(f" Geofence Status: {'INSIDE Safe Zone' if inside is True else 'OUTSIDE Safe Zone' if inside is False else 'UNCERTAIN'}")
                print(f" Open Alert Count: {s.get('open_alert_count')}")
            print("=" * 50 + "\n")
        else:
            print(f"ERROR: Failed to post custom coordinates: {res.status_code} {res.text}", file=sys.stderr)
            sys.exit(1)

    elif args.action == "set-zone":
        target_lat = args.lat if args.lat is not None else safe_lat
        target_lon = args.lon if args.lon is not None else safe_lon
        res = client.put(
            f"/patients/{user_id}/settings",
            headers=headers,
            json={
                "safe_zone_enabled": True,
                "safe_zone_latitude": target_lat,
                "safe_zone_longitude": target_lon,
                "safe_zone_radius_meters": args.radius,
                "geofence_alerts_enabled": True,
                "tracking_enabled": True,
            },
        )
        if res.status_code == 200:
            print("\n" + "=" * 50)
            print(" SUCCESS: Patient Safe-Zone Perimeter Updated!")
            print(f" Home Center: ({target_lat}, {target_lon})")
            print(f" Radius:      {args.radius} metres")
            print("=" * 50 + "\n")
        else:
            print(f"ERROR: Failed to update safe zone: {res.status_code} {res.text}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
