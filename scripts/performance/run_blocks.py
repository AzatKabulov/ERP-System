"""Counterbalanced, separate-browser A/B runs against one disposable server."""

import argparse
import os
import subprocess
import sys
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--data", type=Path, required=True)
p.add_argument("--baseline", type=Path, required=True)
p.add_argument("--candidate", type=Path, required=True)
p.add_argument("--out", type=Path, required=True)
p.add_argument("--iterations", type=int, default=11)
p.add_argument("--order", default="baseline,candidate,baseline,candidate")
p.add_argument("--no-trace", action="store_true")
a = p.parse_args()
if not (a.data / ".performance-sample").is_file():
    p.error("Use a marked disposable sample server.")
env = dict(
    os.environ,
    ERP_SAMPLE_PASSWORD=(a.data / "password").read_text(),
    ERP_E2E_DISPOSABLE="true",
    PERF_ITERATIONS=str(a.iterations),
    PERF_TRACE="false" if a.no_trace else "true",
)
for index, label in enumerate(a.order.split(",")):
    archive = {"baseline": a.baseline, "candidate": a.candidate}[label]
    subprocess.run(
        [
            sys.executable,
            "scripts/performance/switch_build.py",
            "--data",
            str(a.data),
            "--archive",
            str(archive),
        ],
        check=True,
    )
    env["PERF_OUT"] = str(a.out / f"{index}-{label}")
    print(f"BLOCK {index}: {label}", flush=True)
    subprocess.run(
        [env.get("NODE_BINARY", "node"), "scripts/performance/navigation_benchmark.js"],
        env=env,
        check=True,
    )
