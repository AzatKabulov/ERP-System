"""Summarize matched blocks; first-route samples never enter warm statistics."""

import argparse
import json
import statistics
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
args = parser.parse_args()
groups = {"baseline": [], "candidate": []}
hashes = {label: set() for label in groups}
blocks = []
for folder in sorted(args.directory.iterdir()):
    if not folder.is_dir() or not (folder / "samples.json").is_file():
        continue
    label = folder.name.split("-", 1)[1]
    if label not in groups:
        continue
    data = json.loads((folder / "samples.json").read_text())
    if not data.get("bundleSha256"):
        raise SystemExit(f"Incomplete block: {folder}")
    hashes[label].add(data["bundleSha256"])
    traces = json.loads(
        subprocess.check_output(
            [
                sys.executable,
                "scripts/performance/analyze_traces.py",
                str(folder),
            ]
        )
    )
    by_trace = {row["trace"]: row for row in traces}
    rows = []
    for sample in data["samples"]:
        row = {key: sample[key] for key in ("i", "cache", "feedbackMs", "usefulMs", "readyMs")}
        trace = by_trace.get(f"sample-{sample['i']}.trace.json.gz", {})
        for metric in ("callbackWorkMs500", "longestCallbackMs"):
            if metric in trace:
                row[metric] = trace[metric]
        row["apiMs"] = [r["endMs"] for r in sample["requests"]]
        row["endpoints"] = [r["endpoint"] for r in sample["requests"]]
        if sample["cache"] == "warm":
            groups[label].append(row)
        rows.append(row)
    blocks.append({"folder": folder.name, "bundleSha256": data["bundleSha256"], "samples": rows})
if any(len(values) != 1 for values in hashes.values()):
    raise SystemExit("Expected exactly one bundle hash per variant.")


def describe(values):
    q1, _, q3 = statistics.quantiles(values, method="inclusive")
    return {
        "n": len(values),
        "median": statistics.median(values),
        "q1": q1,
        "q3": q3,
        "min": min(values),
        "max": max(values),
    }


metrics = ["feedbackMs", "usefulMs", "readyMs", "callbackWorkMs500", "longestCallbackMs"]
comparison = {}
for metric in metrics:
    if not all(all(metric in row for row in rows) for rows in groups.values()):
        continue
    result = {label: describe([row[metric] for row in rows]) for label, rows in groups.items()}
    result["medianReductionPercent"] = 100 * (
        1 - result["candidate"]["median"] / result["baseline"]["median"]
    )
    comparison[metric] = result
print(json.dumps({"warm": comparison, "blocks": blocks}, indent=2))
