"""Summarize exported XCTest metric CSVs without replacing raw measurements."""
import argparse
import csv
import json
import math
from pathlib import Path
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--metrics", action="append", required=True, metavar="LABEL=CSV_OR_DIRECTORY")
parser.add_argument("--out", required=True, type=Path)
args = parser.parse_args()
report = []
for source in args.metrics:
    label, location = source.split("=", 1)
    source_path = Path(location)
    files = [source_path] if source_path.is_file() and source_path.suffix == ".csv" else sorted(source_path.glob("*.csv"))
    if not files:
        parser.error("No metric CSVs found at " + location)
    for path in files:
        with path.open(newline="") as handle:
            for row in csv.DictReader(handle):
                for key, raw in row.items():
                    if not key.endswith(" (Iterations)"):
                        continue
                    metric = key.removesuffix(" (Iterations)")
                    if not row[metric + " (Average)"].endswith(" s"):
                        raise ValueError("Unsupported metric unit: " + metric)
                    values = json.loads(raw)
                    if not values or not all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in values):
                        raise ValueError("Invalid iteration data: " + str(path))
                    mean = statistics.mean(values)
                    if abs(mean - float(row[metric + " (Average)"].removesuffix(" s"))) > 1e-6:
                        raise ValueError("CSV average does not match its iterations: " + str(path))
                    report.append({
                        "label": label, "metric": metric, "destination": row["Destination"],
                        "sourceCSV": str(path.resolve()), "count": len(values), "seconds": values,
                        "meanSeconds": mean, "medianSeconds": statistics.median(values),
                        "minimumSeconds": min(values), "maximumSeconds": max(values),
                        "sampleStandardDeviationSeconds": statistics.stdev(values) if len(values) > 1 else None,
                        "p95Seconds": sorted(values)[math.ceil(len(values) * .95) - 1] if len(values) >= 20 else None,
                        "note": "No P95 estimate for fewer than 20 measurements",
                    })
if not report:
    raise ValueError("No duration iterations were found")
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps([{key: row[key] for key in ["label", "metric", "count", "meanSeconds", "medianSeconds"]}
                  for row in report], indent=2))
