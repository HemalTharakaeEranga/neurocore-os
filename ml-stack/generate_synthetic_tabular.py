#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: CC0-1.0
"""Deterministic synthetic tabular classification dataset generator.

Generates a reproducible CSV dataset under /usr/share/neurocore/datasets/synthetic-tabular/
using only the Python standard library so Polars, Linfa, and scikit-learn benchmarks
run cleanly without any third-party dataset licensing ambiguity.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
from pathlib import Path


def generate(out_dir: Path, rows: int, seed: int) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)

    csv_path = out_dir / "neurocore_tabular_v1.csv"
    fieldnames = ["f0", "f1", "f2", "f3", "f4", "f5", "label"]

    class_counts = {0: 0, 1: 0, 2: 0}
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for i in range(rows):
            cls = i % 3
            cx = math.cos(cls * 2.0943951023931953) * 2.2
            cy = math.sin(cls * 2.0943951023931953) * 2.2
            f0 = round(cx + rng.gauss(0.0, 0.55), 6)
            f1 = round(cy + rng.gauss(0.0, 0.55), 6)
            f2 = round(0.5 * f0 - 0.3 * f1 + rng.gauss(0.0, 0.35), 6)
            f3 = round(math.sin(f0) + rng.gauss(0.0, 0.25), 6)
            f4 = round(f0 * f1 * 0.25 + rng.gauss(0.0, 0.30), 6)
            f5 = round(rng.gauss(cls * 0.8, 0.65), 6)
            writer.writerow(
                {
                    "f0": f0,
                    "f1": f1,
                    "f2": f2,
                    "f3": f3,
                    "f4": f4,
                    "f5": f5,
                    "label": cls,
                }
            )
            class_counts[cls] += 1

    meta = {
        "name": "neurocore_tabular_v1",
        "license": "CC0-1.0",
        "seed": seed,
        "rows": rows,
        "features": fieldnames[:-1],
        "target": "label",
        "class_distribution": class_counts,
    }
    (out_dir / "metadata.json").write_text(
        json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"Generated {rows} rows -> {csv_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate NeuroCore synthetic tabular dataset")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--rows", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=20260101)
    args = parser.parse_args()
    generate(args.out_dir, args.rows, args.seed)


if __name__ == "__main__":
    main()
