"""
Garmin Connect FIT Downloader + Server Pusher
==============================================
Downloads FIT files from Garmin Connect, parses accelerometer,
gyroscope and heart rate data, then pushes to the server in the
expected binary frame format.

Usage:
    pip install garminconnect fitparse aiohttp
    python garmin_push_server.py
"""

import asyncio
import base64
import bisect
import getpass
import json
import struct
import zipfile
from datetime import timedelta
from pathlib import Path

import aiohttp
from fitparse import FitFile
from garminconnect import Garmin

# Windows asyncio fix
asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

# ── CONFIG ─────────────────────────────────────────────────────────────────────
ACTIVITY_NAME_FILTER = "SensorLog"   # Filter by activity name. None = all
MAX_ACTIVITIES       = 100
FIT_DIR              = Path("fit_files")
DOWNLOADED_LOG       = Path("downloaded.json")

POST_URL  = "https://api.alphaomega-eng.com/ingest/imu" 
API_KEY   = "3HA1!AqE@3"

PATIENT_ID      = "11111111-1111-1111-1111-111111111111"
DEVICE_ID       = "BC:E8:FA:85:3D:6A"
DEVICE_MODEL    = "1.2"
FIRMWARE_VERSION= "2.3"
SCHEMA_VER      = "2.4"
DATA_SOURCE     = "cn"

ACC_FREQ_HZ     = 100                 # Hz of accelerometer in FIT file
GYRO_FREQ_HZ    = 100                 # Hz of gyroscope in FIT file
SAMPLES_PER_FRAME = 125               # samples per binary frame sent to server
# ───────────────────────────────────────────────────────────────────────────────


# ── LOGIN ──────────────────────────────────────────────────────────────────────

def mfa_prompt():
    return input("Enter Garmin MFA / 2FA code: ").strip()


def login():
    token_file = Path("garmin_token.json")
    email      = input("Garmin Connect email: ").strip()
    password   = getpass.getpass("Garmin Connect password: ")
    client     = Garmin(email, password, prompt_mfa=mfa_prompt)

    if token_file.exists():
        print("Found cached session — trying token login...")
        try:
            with open(token_file) as f:
                client.login(json.load(f))
            print("Token login successful.\n")
            return client
        except Exception:
            print("Token expired — logging in fresh...")

    try:
        client.login()
    except Exception as e:
        if "429" in str(e):
            print("ERROR: Rate limited (429). Wait 15-30 min and retry.")
            raise SystemExit(1)
        raise

    try:
        with open(token_file, "w") as f:
            json.dump(client.garth.dump(), f)
        print("Session token cached.\n")
    except Exception:
        pass

    print("Login successful.\n")
    return client


# ── DOWNLOAD ───────────────────────────────────────────────────────────────────

def load_downloaded():
    if DOWNLOADED_LOG.exists():
        with open(DOWNLOADED_LOG) as f:
            return set(json.load(f))
    return set()


def save_downloaded(downloaded):
    with open(DOWNLOADED_LOG, "w") as f:
        json.dump(list(downloaded), f)


def download_fit_files(client, downloaded):
    FIT_DIR.mkdir(exist_ok=True)
    print(f"Fetching activity list (max {MAX_ACTIVITIES})...")
    activities = client.get_activities(0, MAX_ACTIVITIES)
    new_files  = []

    for act in activities:
        act_id   = str(act["activityId"])
        act_name = act.get("activityName", "")
        act_date = act.get("startTimeLocal", "")[:10]

        if ACTIVITY_NAME_FILTER and ACTIVITY_NAME_FILTER not in act_name:
            continue
        if act_id in downloaded:
            continue

        print(f"  Downloading: {act_date} — {act_name} (id={act_id})")

        try:
            zip_data = client.download_activity(
                act_id, dl_fmt=client.ActivityDownloadFormat.ORIGINAL
            )
        except Exception as e:
            print(f"    ERROR: {e}")
            continue

        zip_path = FIT_DIR / f"{act_id}.zip"
        with open(zip_path, "wb") as f:
            f.write(zip_data)

        try:
            with zipfile.ZipFile(zip_path, "r") as z:
                fit_names = [n for n in z.namelist() if n.lower().endswith(".fit")]
                if fit_names:
                    fit_path = FIT_DIR / f"{act_id}.fit"
                    with z.open(fit_names[0]) as src, open(fit_path, "wb") as dst:
                        dst.write(src.read())
                    new_files.append((act_id, fit_path, act_name, act_date))
                    downloaded.add(act_id)
        except zipfile.BadZipFile:
            fit_path = FIT_DIR / f"{act_id}.fit"
            with open(fit_path, "wb") as f:
                f.write(zip_data)
            new_files.append((act_id, fit_path, act_name, act_date))
            downloaded.add(act_id)

        zip_path.unlink(missing_ok=True)

    return new_files


# ── PARSE ──────────────────────────────────────────────────────────────────────

def parse_imu(fitfile, msg_type, xf, yf, zf):
    """Return list of (timestamp_unix_ms, x, y, z) tuples."""
    rows = []
    for msg in fitfile.get_messages(msg_type):
        fields  = {f.name: f.value for f in msg}
        xs      = fields.get(xf, ())
        ys      = fields.get(yf, ())
        zs      = fields.get(zf, ())
        offsets = fields.get("sample_time_offset", ())
        ts      = fields.get("timestamp")
        ts_ms   = fields.get("timestamp_ms", 0) or 0
        if not xs or ts is None:
            continue
        base_unix_ms = ts.timestamp() * 1000
        for i in range(len(xs)):
            offset_ms = offsets[i] if i < len(offsets) else 0
            unix_ms   = base_unix_ms + ts_ms + offset_ms
            rows.append((
                unix_ms,
                xs[i] if xs[i] is not None else 0.0,
                ys[i] if i < len(ys) and ys[i] is not None else 0.0,
                zs[i] if i < len(zs) and zs[i] is not None else 0.0,
            ))
    return rows


def parse_hr(fitfile):
    """Return list of (timestamp_unix, hr_bpm) tuples from record messages."""
    rows = []
    for msg in fitfile.get_messages("record"):
        fields = {f.name: f.value for f in msg}
        ts = fields.get("timestamp")
        hr = fields.get("heart_rate")
        if ts is not None and hr is not None:
            rows.append((ts.timestamp(), int(hr)))
    return rows


def samples_to_binary(samples_xyz):
    """
    Convert list of (x, y, z) tuples to Base64-encoded binary.
    Each value packed as little-endian float32.
    Layout: x0,y0,z0, x1,y1,z1, ...
    """
    buf = bytearray()
    for x, y, z in samples_xyz:
        buf.extend(struct.pack("<f", float(x)))
        buf.extend(struct.pack("<f", float(y)))
        buf.extend(struct.pack("<f", float(z)))
    return base64.b64encode(bytes(buf)).decode("utf-8")


def build_frames(accel_rows, gyro_rows, hr_rows):
    """
    Chunk accel and gyro rows into SAMPLES_PER_FRAME frames.
    Attach nearest HR reading to each frame window.
    Returns list of request payloads ready to POST.
    """
    device_info = {
        "patient_id":       PATIENT_ID,
        "device_id":        DEVICE_ID,
        "device_model":     DEVICE_MODEL,
        "firmware_version": FIRMWARE_VERSION,
        "schema_ver":       SCHEMA_VER,
        "data_source":      DATA_SOURCE,
    }

    # Build HR lookup: sorted list of unix timestamps
    hr_ts_list  = [r[0] for r in hr_rows]
    hr_val_list = [r[1] for r in hr_rows]

    def nearest_hr(unix_ts):
        if not hr_ts_list:
            return None
        idx = bisect.bisect_left(hr_ts_list, unix_ts)
        idx = min(idx, len(hr_ts_list) - 1)
        return hr_val_list[idx]

    # Align gyro to accel by nearest timestamp
    gyro_ts_list = [r[0] for r in gyro_rows]

    def nearest_gyro(unix_ms):
        if not gyro_ts_list:
            return (0.0, 0.0, 0.0)
        idx = bisect.bisect_left(gyro_ts_list, unix_ms)
        idx = min(idx, len(gyro_rows) - 1)
        r = gyro_rows[idx]
        return (r[1], r[2], r[3])

    payloads = []
    total    = len(accel_rows)
    i        = 0

    while i < total:
        chunk      = accel_rows[i : i + SAMPLES_PER_FRAME]
        chunk_size = len(chunk)

        # Timestamps for this chunk
        start_unix_ms = chunk[0][0]
        start_unix_s  = start_unix_ms / 1000.0

        # Build xyz lists
        acc_xyz  = [(r[1], r[2], r[3]) for r in chunk]
        gyro_xyz = [nearest_gyro(r[0]) for r in chunk]

        hr_value = nearest_hr(start_unix_s)

        frames = [
            {
                "meta": {
                    "sensors":        "acc",
                    "sample_count":   chunk_size,
                    "unix_timestamp": start_unix_s,
                    "unit":           "m/s^2",
                    "scale":          1.0,
                    "freq_hz":        ACC_FREQ_HZ,
                },
                "bin": samples_to_binary(acc_xyz),
            },
            {
                "meta": {
                    "sensors":        "gyro",
                    "sample_count":   chunk_size,
                    "unix_timestamp": start_unix_s,
                    "unit":           "rad",
                    "scale":          1.0,
                    "freq_hz":        GYRO_FREQ_HZ,
                },
                "bin": samples_to_binary(gyro_xyz),
            },
        ]

        if hr_value is not None:
            frames.append({
                "meta": {
                    "sensors":        "hr",
                    "unix_timestamp": start_unix_s,
                    "hr":             hr_value,
                    "unit":           "bpm",
                },
            })

        payloads.append({**device_info, "frames": frames})
        i += SAMPLES_PER_FRAME

    return payloads


def parse_fit_to_payloads(fit_path):
    """Parse a FIT file and return list of server payloads."""
    fitfile = FitFile(str(fit_path))

    accel_rows = parse_imu(fitfile, "accelerometer_data",
        "calibrated_accel_x", "calibrated_accel_y", "calibrated_accel_z")
    gyro_rows  = parse_imu(fitfile, "gyroscope_data",
        "calibrated_gyro_x", "calibrated_gyro_y", "calibrated_gyro_z")
    hr_rows    = parse_hr(fitfile)

    if not accel_rows:
        print("    No accelerometer data — skipping.")
        return []

    print(f"    Accel: {len(accel_rows):,} samples")
    print(f"    Gyro:  {len(gyro_rows):,} samples")
    print(f"    HR:    {len(hr_rows):,} records")

    payloads = build_frames(accel_rows, gyro_rows, hr_rows)
    print(f"    Frames: {len(payloads)} x {SAMPLES_PER_FRAME} samples each")
    return payloads


# ── PUSH ───────────────────────────────────────────────────────────────────────

async def send_payload(session, url, payload, idx):
    try:
        async with session.post(url, json=payload) as resp:
            text = await resp.text()
            return {"idx": idx, "status": resp.status, "body": text}
    except Exception as e:
        return {"idx": idx, "status": 500, "body": str(e)}


BATCH_SIZE  = 10    # frames per batch
BATCH_DELAY = 2.0  # seconds between batches


async def push_payloads(payloads):
    if not POST_URL:
        print("  POST_URL is empty — skipping push (set POST_URL in CONFIG)")
        return

    headers = {"X-API-Key": API_KEY} if API_KEY else {}
    results = []
    total_batches = (len(payloads) + BATCH_SIZE - 1) // BATCH_SIZE

    async with aiohttp.ClientSession(headers=headers) as session:
        for batch_num in range(total_batches):
            batch = payloads[batch_num * BATCH_SIZE : (batch_num + 1) * BATCH_SIZE]
            offset = batch_num * BATCH_SIZE
            tasks = [
                asyncio.create_task(send_payload(session, POST_URL, p, offset + i))
                for i, p in enumerate(batch)
            ]
            batch_results = await asyncio.gather(*tasks)
            results.extend(batch_results)
            print(f"    Batch {batch_num + 1}/{total_batches} sent ({len(batch)} frames)")
            if batch_num < total_batches - 1:
                await asyncio.sleep(BATCH_DELAY)  # pause between batches

    ok  = sum(1 for r in results if r["status"] in (200, 202))
    err = len(results) - ok
    print(f"    Pushed {ok}/{len(results)} frames OK (200/202), {err} real errors")

    for r in results:
        if r["status"] not in (200, 202):
            print(f"      Frame {r['idx']} FAILED {r['status']}: {r['body'][:120]}")


# ── MAIN ───────────────────────────────────────────────────────────────────────

async def main_async():
    downloaded = load_downloaded()
    client     = login()
    new_files  = download_fit_files(client, downloaded)
    save_downloaded(downloaded)

    if not new_files:
        print("No new activities found.")
        return

    total_payloads = 0
    for act_id, fit_path, act_name, act_date in new_files:
        print(f"\nProcessing: {act_date} — {act_name}")
        payloads = parse_fit_to_payloads(fit_path)
        if payloads:
            await push_payloads(payloads)
            total_payloads += len(payloads)

    print(f"\nDone. Total frames pushed: {total_payloads}")


if __name__ == "__main__":
    asyncio.run(main_async())