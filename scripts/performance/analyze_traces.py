"""Recompute navigation timings/callback work and sampled stacks from saved Chrome traces."""

import argparse
import gzip
import json
from collections import Counter
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
args = parser.parse_args()
result = []
for filename in sorted(args.directory.glob("sample-*.trace.json.gz")):
    events = json.loads(gzip.decompress(filename.read_bytes()))["traceEvents"]
    marks = {e["name"]: e["ts"] for e in events if e["name"].startswith("erp.navigation.")}
    start = marks["erp.navigation.input"]
    callbacks = [
        e
        for e in events
        if e["name"] == "FireAnimationFrame"
        and e.get("ph") == "X"
        and 0 <= e["ts"] - start < 500_000
    ]
    row = {
        "trace": filename.name,
        "usefulMs": (marks["erp.navigation.useful"] - start) / 1000,
        "feedbackMs": (marks["erp.navigation.feedback"] - start) / 1000,
        "callbackWorkMs500": sum(e.get("dur", 0) for e in callbacks) / 1000,
        "longestCallbackMs": max((e.get("dur", 0) for e in callbacks), default=0) / 1000,
        "callbacksOverFrameBudget": sum(e.get("dur", 0) > 16667 for e in callbacks),
    }
    nodes = {}
    for event in events:
        if event["name"] == "ProfileChunk":
            for node in event["args"]["data"].get("cpuProfile", {}).get("nodes", []):
                nodes[(event["pid"], event["tid"], event.get("id"), node["id"])] = node
    weight = Counter()
    for event in events:
        if event["name"] != "ProfileChunk":
            continue
        data = event["args"]["data"]
        samples = data.get("cpuProfile", {}).get("samples", [])
        deltas = data.get("timeDeltas", [])
        if len(samples) != len(deltas):
            raise ValueError("CPU sample and duration counts differ")
        for index, sample in enumerate(samples):
            delta = deltas[index]
            profile = (event["pid"], event["tid"], event.get("id"))
            node = nodes.get((*profile, sample))
            seen = set()
            while node:
                frame = node.get("callFrame", {})
                name = frame.get("functionName", "")
                if name and name not in seen and name not in ("(root)", "(idle)", "(program)"):
                    weight[name] += delta / 1000
                    seen.add(name)
                node = nodes.get((*profile, node.get("parent")))
    row["inclusiveSampleMsWholeCapture"] = weight.most_common(35)
    result.append(row)
print(json.dumps(result, indent=2))
