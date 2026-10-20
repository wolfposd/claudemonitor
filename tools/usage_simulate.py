#!/usr/bin/env python3
"""Simulate rising limit usage on the ESP display (no real data needed).

Both bars rise by --step percent every --interval seconds (weekly at half speed) and wrap around
after 100 %. Tokens are faked too. Stop usage_push.py first, only one program may use the port.
Usage: python3 tools/usage_simulate.py [--port /dev/cu.usbmodemXXXX] [--step 5] [--interval 1]
"""
import argparse, glob, os, subprocess, time
from datetime import datetime


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("--step", type=float, default=5)
    ap.add_argument("--interval", type=float, default=1)
    a = ap.parse_args()
    port = a.port or (sorted(glob.glob("/dev/cu.usbmodem*")) or [None])[0]
    if not port:
        raise SystemExit("no ESP found (/dev/cu.usbmodem*)")
    subprocess.run(["stty", "-f", port, "115200", "raw", "-echo"], check=False)
    fd = os.open(port, os.O_WRONLY | os.O_NOCTTY)
    time.sleep(2)  # board may reset when the port opens

    wd = datetime.now().weekday()
    days = [120_000, 450_000, 80_000, 900_000, 300_000, 650_000, 0]
    pct = 0.0
    try:
        while True:
            p5 = int(pct) % 101
            p7 = int(pct / 2) % 101
            days[6] = int(pct * 12_000)
            h5 = int(pct * 9_000)
            line = f"U,{wd}," + ",".join(map(str, days)) + f",{h5},{int(pct)},{p5},{max(0, 300 - int(pct * 3))},{p7},{10080 - int(pct * 20)}\n"
            os.write(fd, line.encode())
            print(f"session {p5:3d}%  weekly {p7:3d}%")
            pct = (pct + a.step) % 105
            time.sleep(a.interval)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
