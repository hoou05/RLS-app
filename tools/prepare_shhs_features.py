#!/usr/bin/env python3
"""Project downloaded SHHS CSV data into the RLS model feature schema.

This script does not download data and does not write identifiers by default.
It expects files from `nsrr download shhs/datasets`.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd


SHHS_VERSION = "0.21.0"


def first_present(row: pd.Series, names: list[str]) -> Any:
    for name in names:
        if name in row and pd.notna(row[name]):
            return row[name]
    return None


def to_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def sex_to_model(value: Any) -> str | None:
    if value is None or pd.isna(value):
        return None
    numeric = to_float(value)
    if numeric == 1.0:
        return "male"
    if numeric in {0.0, 2.0}:
        return "female"
    normalized = str(value).strip().lower()
    if normalized in {"1", "m", "male", "man"}:
        return "male"
    if normalized in {"0", "2", "f", "female", "woman"}:
        return "female"
    return None


def stage_minutes(tst_minutes: float | None, pct: float | None) -> float | None:
    if tst_minutes is None or pct is None:
        return None
    return tst_minutes * pct / 100.0


def project_row(row: pd.Series) -> dict[str, Any]:
    tst = to_float(first_present(row, ["nsrr_ttldursp_f1", "slpprdp"]))
    n1_pct = to_float(first_present(row, ["nsrr_pctdursp_s1", "timest1p"]))
    n2_pct = to_float(first_present(row, ["nsrr_pctdursp_s2", "timest2p"]))
    n3_pct = to_float(first_present(row, ["nsrr_pctdursp_s3", "times34p"]))
    rem_pct = to_float(first_present(row, ["nsrr_pctdursp_sr", "timeremp"]))
    n1n2_pct = None
    if n1_pct is not None or n2_pct is not None:
        n1n2_pct = (n1_pct or 0.0) + (n2_pct or 0.0)

    experiment_features = {
        "WASO/分 入睡后清醒时间": to_float(first_present(row, ["nsrr_ttldurws_f1", "waso"])),
        "睡眠潜伏期/分": to_float(first_present(row, ["nsrr_ttllatsp_f1", "slplatp"])),
        "REM睡眠潜伏期/分": to_float(first_present(row, ["nsrr_ttldursp_s1sr", "remlaiip", "remlaip"])),
        "睡眠平均SPO2": to_float(first_present(row, ["avgo2sat", "avgspo2", "avgsat"])),
        "睡眠最低SPO2": to_float(first_present(row, ["minsat", "minsao2", "minspo2"])),
        "N1N2时间": stage_minutes(tst, n1n2_pct),
        "N1N2%": n1n2_pct,
        "N3时间": stage_minutes(tst, n3_pct),
        "N3%": n3_pct,
        "R期时间": stage_minutes(tst, rem_pct),
        "R%": rem_pct,
    }
    experiment_features = {k: v for k, v in experiment_features.items() if v is not None}

    return {
        "sleep_duration_minutes": tst,
        "sleep_efficiency": to_float(first_present(row, ["nsrr_ttleffsp_f1", "slpeffp"])),
        "age": to_float(first_present(row, ["nsrr_age", "age_s1", "age_s2"])),
        "sex": sex_to_model(first_present(row, ["nsrr_sex", "gender"])),
        "height": to_float(first_present(row, ["height", "pm207"])),
        "weight": to_float(first_present(row, ["weight", "pm202"])),
        "bmi": to_float(first_present(row, ["nsrr_bmi", "bmi_s1", "bmi_s2"])),
        "experiment_features": experiment_features,
    }


def source_file(input_dir: Path, visit: str) -> Path:
    name = {
        "shhs1": f"shhs1-dataset-{SHHS_VERSION}.csv",
        "shhs2": f"shhs2-dataset-{SHHS_VERSION}.csv",
        "harmonized": f"shhs-harmonized-dataset-{SHHS_VERSION}.csv",
    }[visit]
    path = input_dir / name
    if not path.exists():
        raise FileNotFoundError(f"Missing {path}. Download with: tools/download_shhs.sh datasets")
    return path


def coverage(rows: list[dict[str, Any]]) -> dict[str, float]:
    keys = [
        "sleep_duration_minutes",
        "sleep_efficiency",
        "age",
        "sex",
        "height",
        "weight",
        "bmi",
    ]
    total = len(rows) or 1
    result = {}
    for key in keys:
        result[key] = round(sum(row.get(key) is not None for row in rows) / total, 4)
    experiment_keys = sorted({k for row in rows for k in row["experiment_features"]})
    for key in experiment_keys:
        result[f"experiment_features.{key}"] = round(
            sum(key in row["experiment_features"] for row in rows) / total,
            4,
        )
    return result


def read_dataset(path: Path) -> pd.DataFrame:
    try:
        return pd.read_csv(path, low_memory=False)
    except UnicodeDecodeError:
        return pd.read_csv(path, low_memory=False, encoding="latin1")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path("data/nsrr/shhs/datasets"))
    parser.add_argument("--visit", choices=["shhs1", "shhs2", "harmonized"], default="shhs1")
    parser.add_argument("--output", type=Path, default=Path("outputs/shhs/shhs_features.jsonl"))
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--include-id", action="store_true", help="Include nsrrid in output JSONL.")
    args = parser.parse_args()

    df = read_dataset(source_file(args.input_dir, args.visit))
    if args.limit:
        df = df.head(args.limit)

    rows = []
    for _, row in df.iterrows():
        projected = project_row(row)
        if args.include_id:
            nsrrid = first_present(row, ["nsrrid"])
            projected["nsrrid"] = None if nsrrid is None else str(nsrrid)
        rows.append(projected)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n")

    summary = {
        "source": str(source_file(args.input_dir, args.visit)),
        "rows": len(rows),
        "coverage": coverage(rows),
    }
    summary_path = args.output.with_suffix(".summary.json")
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
