"""Setup check, Python part: validates the AI's extraction and that the course packages load."""
import csv, pathlib, sys

import pandas as pd  # noqa: F401  (proves the course Python environment works)
import matplotlib    # noqa: F401
import pymupdf       # noqa: F401

out = pathlib.Path(__file__).parent / "out"
rows = {r["field"].strip(): r["value"].strip() for r in csv.DictReader(open(out / "extract.csv", encoding="utf-8"))}
expected = {"sample_size": "412", "preregistered": "yes", "open_data": "yes"}
problems = [f"{k}: expected {v!r}, got {rows.get(k)!r}" for k, v in expected.items() if rows.get(k, "").lower() != v]
if "t(410)" not in rows.get("test_statistic", "").replace(" ", ""):
    problems.append(f"test_statistic: expected t(410)..., got {rows.get('test_statistic')!r}")
if problems:
    print("PYTHON CHECK: the AI's extraction has problems:\n  " + "\n  ".join(problems))
    sys.exit(1)
(out / "python-ok.txt").write_text("ok", encoding="utf-8")
print("PYTHON CHECK: OK (4 fields correct, pandas/matplotlib/pymupdf load)")
