#!/usr/bin/env python3
"""Read local Claude Code logs and push usage stats to the ESP over USB serial.

Line format: U,<weekday 0=Mon>,<d0..d6 tokens/day, today last>,<tokens last 5h>,<messages today>,
             <5h limit %>,<5h reset min>,<7d limit %>,<7d reset min>   (-1 = unknown)
Limits come from the undocumented Claude Code OAuth usage endpoint, using the token Claude Code
keeps in the macOS keychain. If that token is expired, `claude -p "/usage"` is run to refresh it (free, no model call).
Tokens = input + output + cache creation (cache reads excluded).
Usage: python3 tools/usage_push.py [--port /dev/cu.usbmodemXXXX] [--interval 30] [--once]
"""
import argparse, glob, json, os, sys, time, subprocess, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone

PROJECTS = os.path.expanduser("~/.claude/projects")


_limits = {"t": 0, "val": (-1, -1, -1, -1)}


def _minutes_until(iso):
    try:
        t = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return max(0, int((t - datetime.now(timezone.utc)).total_seconds() // 60))
    except (ValueError, AttributeError):
        return -1


def _read_token():
    raw = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                         capture_output=True, text=True, timeout=10).stdout
    return json.loads(raw)["claudeAiOauth"]["accessToken"]


def _locate_claude():
    """Well-known install locations first, then the login shell PATH (nvm/volta/custom prefixes)."""
    home = os.path.expanduser("~")
    for c in (f"{home}/.local/bin/claude", f"{home}/.claude/local/claude", "/opt/homebrew/bin/claude",
              "/usr/local/bin/claude", f"{home}/.npm-global/bin/claude", f"{home}/.volta/bin/claude"):
        if os.access(c, os.X_OK):
            return c
    try:
        out = subprocess.run(["/bin/zsh", "-ilc", "command -v claude"], capture_output=True, text=True,
                             timeout=15, stdin=subprocess.DEVNULL).stdout.strip().splitlines()
    except (OSError, subprocess.SubprocessError):
        return None
    return out[-1].strip() if out and os.access(out[-1].strip(), os.X_OK) else None


def _refresh_token_via_cli():
    """`claude -p "/usage"` is handled locally (no model call, no cost) but the CLI refreshes its
    OAuth token and rewrites the keychain item on startup. True if it exited successfully."""
    claude = _locate_claude()
    if not claude:
        return False
    env = dict(os.environ)
    env["PATH"] = ":".join([os.path.dirname(claude), "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                            "/bin", env.get("PATH", "")])
    try:
        r = subprocess.run([claude, "-p", "/usage"], capture_output=True, stdin=subprocess.DEVNULL,
                           env=env, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 0


def _request_usage(tok):
    req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
        "Authorization": "Bearer " + tok, "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code/2.0"})
    return json.load(urllib.request.urlopen(req, timeout=10))


def fetch_limits():
    """Return (pct5h, reset5h_min, pct7d, reset7d_min); -1 where unknown. Cached 60 s."""
    if time.time() - _limits["t"] < 60:
        return _limits["val"]
    _limits["t"] = time.time()
    try:
        tok = _read_token()
        try:
            d = _request_usage(tok)
        except urllib.error.HTTPError as ex:
            if ex.code not in (401, 403) or not _refresh_token_via_cli():
                raise
            fresh = _read_token()
            if fresh == tok:
                raise
            d = _request_usage(fresh)
        out = []
        for k in ("five_hour", "seven_day"):
            w = d.get(k) or {}
            u = w.get("utilization")
            out += [int(round(u)) if u is not None else -1, _minutes_until(w.get("resets_at"))]
        _limits["val"] = tuple(out)
    except urllib.error.HTTPError as ex:
        print("limits: HTTP", ex.code, "(token expired? run `claude` once)", file=sys.stderr)
        _limits["val"] = (-1, -1, -1, -1)
    except Exception as ex:
        print("limits:", ex, file=sys.stderr)
        _limits["val"] = (-1, -1, -1, -1)
    return _limits["val"]


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
    return f"U,{now.weekday()}," + ",".join(map(str, days)) + f",{h5},{msgs}," + ",".join(map(str, fetch_limits())) + "\n"


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
