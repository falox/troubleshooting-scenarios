import json
import random
import sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

HISTORY_DAYS = 4
SLOT_MINUTES = 30
TARGET = "pipeline-intake.corp.net:443"


def record(event_time, result, batch_id, **fields):
    entry = {
        "event_time": event_time.isoformat().replace("+00:00", "Z"),
        "level": "INFO" if result == "success" else "ERROR",
        "component": "batch-processor",
        "event": "batch_submission",
        "batch_id": batch_id,
        "target": TARGET,
        "result": result,
    }
    entry.update(fields)
    return entry


def normal_record(event_time):
    batch_id = f"batch-{event_time.strftime('%m%d%H%M')}"
    generator = random.Random(int(event_time.timestamp()))
    return record(
        event_time,
        "success",
        batch_id,
        status_code=202,
        duration_ms=generator.randint(140, 620),
        records=generator.randint(120, 4800),
    )


def failed_record(event_time, sequence):
    batch_id = f"batch-{event_time.strftime('%m%d%H%M')}-{sequence}"
    return record(
        event_time,
        "timeout",
        batch_id,
        duration_ms=5000,
        error="connect timeout",
    )


def event_times(start, end):
    cursor = start.replace(
        minute=(start.minute // SLOT_MINUTES) * SLOT_MINUTES,
        second=0,
        microsecond=0,
    )
    while cursor <= end:
        if cursor >= start and not (
            cursor.hour == 3 and cursor.minute == 0
        ):
            yield cursor, 0
        cursor += timedelta(minutes=SLOT_MINUTES)

    day = start.date() - timedelta(days=1)
    last_day = end.date() + timedelta(days=1)
    while day <= last_day:
        for sequence, minute in enumerate((0, 2, 4), start=1):
            event_time = datetime(
                day.year,
                day.month,
                day.day,
                3,
                minute,
                tzinfo=timezone.utc,
            )
            if start <= event_time <= end:
                yield event_time, sequence
        day += timedelta(days=1)


def build_records(now):
    start = now - timedelta(days=HISTORY_DAYS)
    records = []
    for event_time, sequence in event_times(start, now):
        if event_time.hour == 3 and event_time.minute in (0, 2, 4):
            records.append(failed_record(event_time, sequence))
        else:
            records.append(normal_record(event_time))
    records.sort(key=lambda entry: entry["event_time"])
    return records


def write_records(records):
    for entry in records:
        print(json.dumps(entry, separators=(",", ":")), flush=True)


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path in ("/healthz", "/readyz"):
            payload = b'{"status":"ok"}'
            self.send_response(200)
        else:
            payload = b'{"status":"not_found"}'
            self.send_response(404)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, _format, *_args):
        return


def main():
    now = datetime.now(timezone.utc)
    write_records(build_records(now))
    server = ThreadingHTTPServer(("0.0.0.0", 8080), HealthHandler)
    server.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
