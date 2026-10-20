#!/usr/bin/env python3
"""Read local Claude Code logs and push usage stats to the ESP over USB serial.

Line format: U,<weekday 0=Mon>,<d0..d6 tokens/day, today last>,<tokens last 5h>,<messages today>
Tokens = input + output + cache creation (cache reads excluded).
Usage: python3 tools/usage_push.py [--port /dev/cu.usbmodemXXXX] [--interval 30] [--once]
"""
import argparse, glob, json, os, sys, time, subprocess
from datetime import datetime, timedelta, timezone

PROJECTS = os.path.expanduser("~/.claude/projects")


def collect():
    now = datetime.now().astimezone()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    start = today - timedelta(days=6)
    five_h = now - timedelta(hours=5)
    days = [0] * 7
    h5 = 0
    msgs = 0
    seen = set()
    for path in glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True):
        try:
            if datetime.fromtimestamp(os.path.getmtime(path)).astimezone() < start:
                continue
            f = open(path, encoding="utf-8", errors="ignore")
        except OSError:
            continue
        with f:
            for line in f:
                if '"usage"' not in line:
                    continue
                try:
                    e = json.loads(line)
                    m = e.get("message") or {}
                    u = m.get("usage")
                    ts = e.get("timestamp")
                    if not u or not ts:
                        continue
                    key = (m.get("id"), e.get("requestId"))
                    if key != (None, None):
                        if key in seen:
                            continue
                        seen.add(key)
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
                except (ValueError, AttributeError):
                    continue
                if t < start:
                    continue
                tok = (u.get("input_tokens") or 0) + (u.get("output_tokens") or 0) \
                    + (u.get("cache_creation_input_tokens") or 0)
                idx = (t.replace(hour=0, minute=0, second=0, microsecond=0) - start).days
                if 0 <= idx < 7:
                    days[idx] += tok
                if idx == 6:
                    msgs += 1
                if t >= five_h:
                    h5 += tok
    return f"U,{now.weekday()}," + ",".join(map(str, days)) + f",{h5},{msgs}\n"


def open_port(port):
    subprocess.run(["stty", "-f", port, "115200", "raw", "-echo"], check=False)
    return os.open(port, os.O_WRONLY | os.O_NOCTTY)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("--interval", type=int, default=30)
    ap.add_argument("--once", action="store_true")
    a = ap.parse_args()
    if a.once and not a.port:
        print(collect(), end="")
        return
    port = a.port
    fd = None
    while True:
        try:
            if fd is None:
                port = a.port or (sorted(glob.glob("/dev/cu.usbmodem*")) or [None])[0]
                if not port:
                    raise OSError("no ESP found (/dev/cu.usbmodem*)")
                fd = open_port(port)
                time.sleep(2)  # board may reset when the port opens
            line = collect()
            os.write(fd, line.encode())
            print(time.strftime("%H:%M:%S"), line, end="", flush=True)
        except OSError as ex:
            print("serial error:", ex, file=sys.stderr)
            if fd is not None:
                os.close(fd)
            fd = None
        if a.once:
            break
        time.sleep(a.interval)


if __name__ == "__main__":
    main()
