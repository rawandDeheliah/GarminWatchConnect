"""
Garmin Connect FIT Downloader + Parser
=======================================
Downloads FIT files from Garmin Connect and parses
accelerometer + gyroscope data into CSV files.

Usage:
    pip install garminconnect fitparse
    python garmin_download_parse.py

Output:
    fit_files/   <- raw .fit files
    parsed/      <- one CSV per activity (acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z)
"""

import os
import csv
import json
import zipfile
import bisect
import getpass
from datetime import timedelta
from pathlib import Path

from fitparse import FitFile
from garminconnect import Garmin

# ── CONFIG ────────────────────────────────────────────────────────────────────
ACTIVITY_NAME_FILTER = "SensorLog"   # Only download activities with this name
                                      # Set to None to download all activities
MAX_ACTIVITIES       = 100            # Max activities to fetch per run
FIT_DIR              = Path("fit_files")
PARSED_DIR           = Path("parsed")
DOWNLOADED_LOG       = Path("downloaded.json")
# ──────────────────────────────────────────────────────────────────────────────


def mfa_prompt():
    """Called by the library when MFA code is needed."""
    return input("Enter Garmin MFA / 2FA code from your authenticator app: ").strip()


def login():
    """Log in to Garmin Connect, handling MFA and session token caching."""
    token_file = Path("garmin_token.json")

    email    = input("Garmin Connect email: ").strip()
    password = getpass.getpass("Garmin Connect password: ")

    client = Garmin(email, password, prompt_mfa=mfa_prompt)

    # Try cached token first to avoid rate limiting
    if token_file.exists():
        print("Found cached session — trying token login...")
        try:
            with open(token_file) as f:
                token_store = json.load(f)
            client.login(token_store)
            print("Token login successful.\n")
            return client
        except Exception:
            print("Cached token expired — logging in fresh...")

    # Full login (may ask for MFA code)
    try:
        client.login()
    except Exception as e:
        if "429" in str(e):
            print("\nERROR: Garmin is rate limiting your IP (429).")
            print("Solutions:")
            print("  1. Wait 15-30 minutes and try again")
            print("  2. Use a different network / VPN")
            print("  3. Log in from the Garmin Connect app on your phone first, then retry")
            raise SystemExit(1)
        raise

    # Cache the token so future runs skip the password prompt
    try:
        token_store = client.garth.dump()
        with open(token_file, "w") as f:
            json.dump(token_store, f)
        print("Session token cached to garmin_token.json (future runs won't need password)\n")
    except Exception:
        pass  # token caching is optional

    print("Login successful.\n")
    return client


def load_downloaded():
    """Load set of already-downloaded activity IDs."""
    if DOWNLOADED_LOG.exists():
        with open(DOWNLOADED_LOG) as f:
            return set(json.load(f))
    return set()


def save_downloaded(downloaded):
    with open(DOWNLOADED_LOG, "w") as f:
        json.dump(list(downloaded), f)


def download_fit_files(client, downloaded):
    """Fetch new FIT files from Garmin Connect."""
    FIT_DIR.mkdir(exist_ok=True)

    print(f"Fetching activity list (max {MAX_ACTIVITIES})...")
    activities = client.get_activities(0, MAX_ACTIVITIES)

    new_files = []
    for act in activities:
        act_id   = str(act["activityId"])
        act_name = act.get("activityName", "")
        act_date = act.get("startTimeLocal", "")[:10]

        # Filter by name if configured
        if ACTIVITY_NAME_FILTER and ACTIVITY_NAME_FILTER not in act_name:
            continue

        if act_id in downloaded:
            continue

        print(f"  Downloading: {act_date} — {act_name} (id={act_id})")

        try:
            zip_data = client.download_activity(
                act_id,
                dl_fmt=client.ActivityDownloadFormat.ORIGINAL
            )
        except Exception as e:
            print(f"    ERROR downloading {act_id}: {e}")
            continue

        # Save and extract the zip
        zip_path = FIT_DIR / f"{act_id}.zip"
        with open(zip_path, "wb") as f:
            f.write(zip_data)

        # Extract .fit file from zip
        try:
            with zipfile.ZipFile(zip_path, "r") as z:
                fit_names = [n for n in z.namelist() if n.lower().endswith(".fit")]
                if fit_names:
                    fit_name = fit_names[0]
                    fit_path = FIT_DIR / f"{act_id}.fit"
                    with z.open(fit_name) as src, open(fit_path, "wb") as dst:
                        dst.write(src.read())
                    new_files.append((act_id, fit_path, act_name, act_date))
                    downloaded.add(act_id)
        except zipfile.BadZipFile:
            # Sometimes Garmin returns a raw .fit not zipped
            fit_path = FIT_DIR / f"{act_id}.fit"
            with open(fit_path, "wb") as f:
                f.write(zip_data)
            new_files.append((act_id, fit_path, act_name, act_date))
            downloaded.add(act_id)

        zip_path.unlink(missing_ok=True)

    return new_files


def parse_sensor(fitfile, message_type, x_field, y_field, z_field):
    """Extract expanded per-sample rows from an IMU message type."""
    rows = []
    for msg in fitfile.get_messages(message_type):
        fields  = {f.name: f.value for f in msg}
        xs      = fields.get(x_field, ())
        ys      = fields.get(y_field, ())
        zs      = fields.get(z_field, ())
        offsets = fields.get("sample_time_offset", ())
        ts      = fields.get("timestamp")
        ts_ms   = fields.get("timestamp_ms", 0) or 0

        if not xs or ts is None:
            continue

        for i in range(len(xs)):
            offset_ms = offsets[i] if i < len(offsets) else 0
            sample_ts = ts + timedelta(milliseconds=ts_ms + offset_ms)
            rows.append({
                "timestamp": sample_ts.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
                "x": round(xs[i], 4) if xs[i] is not None else "",
                "y": round(ys[i], 4) if i < len(ys) and ys[i] is not None else "",
                "z": round(zs[i], 4) if i < len(zs) and zs[i] is not None else "",
            })
    return rows


def parse_fit_to_csv(fit_path, csv_path):
    """Parse a FIT file and write acc_x/y/z + gyro_x/y/z to CSV."""
    fitfile = FitFile(str(fit_path))

    accel_rows = parse_sensor(
        fitfile, "accelerometer_data",
        "calibrated_accel_x", "calibrated_accel_y", "calibrated_accel_z"
    )
    gyro_rows = parse_sensor(
        fitfile, "gyroscope_data",
        "calibrated_gyro_x", "calibrated_gyro_y", "calibrated_gyro_z"
    )

    if not accel_rows:
        print("    No accelerometer data found — skipping.")
        return 0

    # Merge accel + gyro into 6-column rows
    if len(accel_rows) == len(gyro_rows):
        merged = [
            {
                "timestamp": a["timestamp"],
                "acc_x": a["x"], "acc_y": a["y"], "acc_z": a["z"],
                "gyro_x": g["x"], "gyro_y": g["y"], "gyro_z": g["z"],
            }
            for a, g in zip(accel_rows, gyro_rows)
        ]
    else:
        # Unequal counts — match by nearest timestamp
        gyro_ts = [r["timestamp"] for r in gyro_rows]
        merged = []
        for a in accel_rows:
            idx = min(bisect.bisect_left(gyro_ts, a["timestamp"]), len(gyro_rows) - 1)
            g = gyro_rows[idx]
            merged.append({
                "timestamp": a["timestamp"],
                "acc_x": a["x"], "acc_y": a["y"], "acc_z": a["z"],
                "gyro_x": g["x"], "gyro_y": g["y"], "gyro_z": g["z"],
            })

    # Write CSV
    fieldnames = ["timestamp", "acc_x", "acc_y", "acc_z", "gyro_x", "gyro_y", "gyro_z"]
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(merged)

    return len(merged)


def main():
    PARSED_DIR.mkdir(exist_ok=True)
    downloaded = load_downloaded()

    # Login
    client = login()

    # Download new FIT files
    new_files = download_fit_files(client, downloaded)
    save_downloaded(downloaded)

    if not new_files:
        print("No new activities found.")
        return

    print(f"\nParsing {len(new_files)} new file(s)...\n")

    total_rows = 0
    for act_id, fit_path, act_name, act_date in new_files:
        csv_name = f"{act_date}_{act_id}.csv"
        csv_path = PARSED_DIR / csv_name

        rows = parse_fit_to_csv(fit_path, csv_path)
        if rows:
            print(f"  {csv_name} — {rows:,} samples")
            total_rows += rows

    print(f"\nDone. Total samples written: {total_rows:,}")
    print(f"CSVs saved to: {PARSED_DIR}/")


if __name__ == "__main__":
    main()