#!/usr/bin/env python3
"""Print Claude Code token usage to the console, broken down by period and model.

Reads the same `~/.claude/projects/**/*.jsonl` logs as usage_push.py, but instead of
pushing a compact line to the ESP, prints a readable report: usage for the last 5
hours / today / the last 7 days, split out per model family (and per exact model
version within that family), with input / input(c) / output tokens and an estimated
USD cost. input(c) = cache_creation_input_tokens + cache_read_input_tokens, billed at
the discounted "cache" rate below.

Usage: python3 tools/usage_report.py
"""
import glob
import json
import os
from collections import defaultdict
from datetime import datetime, timedelta

PROJECTS = os.path.expanduser("~/.claude/projects")

# Estimated USD price per 1M tokens, by model family. `None` means no published rate
# yet, so cost is reported as "n/a" rather than guessed.
PRICING = {
    "haiku":  {"input": 0.1, "cache": 0.01, "output": 0.5},
    "sonnet": {"input": 2.0, "cache": 0.1,  "output": 10.0},
    "opus":   {"input": 4.0, "cache": 0.2,  "output": 20.0},
    "fable":  {"input": 10.0, "cache": 0.25, "output": 50.0},
}

# Checked in this order, so e.g. a model string containing both "opus" and "haiku"
# (shouldn't happen) picks the first match.
FAMILIES = ["sonnet", "opus", "fable", "haiku"]


def family_of(model):
    m = (model or "").lower()
    for fam in FAMILIES:
        if fam in m:
            return fam
    return None


def estimate_cost(family, input_tok, cache_tok, output_tok):
    rates = PRICING.get(family)
    if not rates or rates["input"] is None:
        return None
    million = 1_000_000
    return (input_tok / million * rates["input"]
            + cache_tok / million * rates["cache"]
            + output_tok / million * rates["output"])


def new_bucket():
    return {"input": 0, "output": 0, "cache": 0}


def collect():
    """Returns (records, period_bounds) where records is a list of
    (timestamp, model, input, output, cache) tuples from the last 7 days."""
    now = datetime.now().astimezone()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=6)
    five_h_ago = now - timedelta(hours=5)

    records = []
    seen = set()
    for path in glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True):
        try:
            if datetime.fromtimestamp(os.path.getmtime(path)).astimezone() < week_start:
                continue
            f = open(path, encoding="utf-8", errors="ignore")
        except OSError:
            continue
        with f:
            for line in f:
                if '"usage"' not in line:
                    continue
                try:
                    entry = json.loads(line)
                    message = entry.get("message") or {}
                    usage = message.get("usage")
                    ts = entry.get("timestamp")
                    if not usage or not ts:
                        continue
                    key = (message.get("id"), entry.get("requestId"))
                    if key != (None, None):
                        if key in seen:
                            continue
                        seen.add(key)
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
                except (ValueError, AttributeError):
                    continue
                if t < week_start:
                    continue
                records.append((
                    t,
                    message.get("model"),
                    usage.get("input_tokens") or 0,
                    usage.get("output_tokens") or 0,
                    (usage.get("cache_creation_input_tokens") or 0) + (usage.get("cache_read_input_tokens") or 0),
                ))
    return records, (five_h_ago, today_start, week_start)


def format_tokens(v):
    if v >= 1_000_000:
        return f"{v / 1_000_000:.1f}M"
    if v >= 1_000:
        return f"{v / 1_000:.1f}K"
    return str(v)


def format_cost(v):
    if v is None:
        return "n/a"
    return f"${v:.4f}" if v < 0.01 else f"${v:.2f}"


def print_period(title, records):
    by_family = defaultdict(new_bucket)
    by_version = defaultdict(new_bucket)  # keyed by (family_or_other, model)

    for _ts, model, inp, out, cache in records:
        fam = family_of(model) or "other"
        for bucket, key in ((by_family, fam), (by_version, (fam, model))):
            b = bucket[key]
            b["input"] += inp
            b["output"] += out
            b["cache"] += cache

    print(f"\n=== {title} ===")
    header = f"{'MODEL':<32} {'INPUT':>9} {'INPUT(C)':>9} {'OUTPUT':>9} {'COST':>9}"
    print(header)
    print("-" * len(header))

    total_input = total_output = total_cache = 0
    total_cost = 0.0
    any_unknown_cost = False

    for fam in FAMILIES + ["other"]:
        if fam not in by_family:
            continue
        b = by_family[fam]
        cost = estimate_cost(fam, b["input"], b["cache"], b["output"]) if fam != "other" else None
        print(f"{fam.upper():<32} {format_tokens(b['input']):>9} {format_tokens(b['cache']):>9} "
              f"{format_tokens(b['output']):>9} {format_cost(cost):>9}")

        versions = sorted(v for (f, v) in by_version if f == fam)
        for model in versions:
            vb = by_version[(fam, model)]
            vcost = estimate_cost(fam, vb["input"], vb["cache"], vb["output"]) if fam != "other" else None
            label = f"  {model or '(unknown)'}"
            print(f"{label:<32} {format_tokens(vb['input']):>9} {format_tokens(vb['cache']):>9} "
                  f"{format_tokens(vb['output']):>9} {format_cost(vcost):>9}")

        total_input += b["input"]
        total_output += b["output"]
        total_cache += b["cache"]
        if cost is None:
            any_unknown_cost = True
        else:
            total_cost += cost

    print("-" * len(header))
    cost_str = format_cost(total_cost) + ("+" if any_unknown_cost else "")
    print(f"{'TOTAL':<32} {format_tokens(total_input):>9} {format_tokens(total_cache):>9} "
          f"{format_tokens(total_output):>9} {cost_str:>9}")


def print_pricing_table():
    print("=== Pricing ($ / 1M tokens) ===")
    header = f"{'MODEL':<10} {'INPUT':>8} {'INPUT(C)':>10} {'OUTPUT':>8}"
    print(header)
    print("-" * len(header))
    for fam in FAMILIES:
        rates = PRICING[fam]
        fmt = lambda v: f"${v}" if v is not None else "n/a"
        print(f"{fam:<10} {fmt(rates['input']):>8} {fmt(rates['cache']):>10} {fmt(rates['output']):>8}")


def main():
    print_pricing_table()

    records, (five_h_ago, today_start, _week_start) = collect()

    r_5h = [r for r in records if r[0] >= five_h_ago]
    r_today = [r for r in records if r[0] >= today_start]
    r_week = records  # already limited to the 7-day window by collect()

    print_period("LAST 5H", r_5h)
    print_period("TODAY", r_today)
    print_period("WEEKLY (7D)", r_week)
    print()


if __name__ == "__main__":
    main()
