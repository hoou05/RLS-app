#!/usr/bin/env python3
"""Score projected SHHS feature JSONL with the RLS experiment adapter."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from statistics import mean
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
API_ROOT = REPO_ROOT / "services" / "api"
sys.path.insert(0, str(API_ROOT))

from app.services.rls_experiments_adapter import RLSExperimentModelAdapter  # noqa: E402


def quantile(sorted_values: list[float], q: float) -> float:
    if not sorted_values:
        return float("nan")
    idx = (len(sorted_values) - 1) * q
    lo = int(idx)
    hi = min(lo + 1, len(sorted_values) - 1)
    weight = idx - lo
    return sorted_values[lo] * (1 - weight) + sorted_values[hi] * weight


def risk_level(score: float) -> str:
    if score >= 0.35:
        return "high"
    if score >= 0.18:
        return "moderate"
    return "low"


def summarize(scores: list[float], rows: int, model_version: str) -> dict[str, Any]:
    sorted_scores = sorted(scores)
    bands = {"low": 0, "moderate": 0, "high": 0}
    for score in scores:
        bands[risk_level(score)] += 1
    return {
        "rows": rows,
        "scored_rows": len(scores),
        "model_version": model_version,
        "score": {
            "min": round(min(scores), 4) if scores else None,
            "p05": round(quantile(sorted_scores, 0.05), 4) if scores else None,
            "p25": round(quantile(sorted_scores, 0.25), 4) if scores else None,
            "mean": round(mean(scores), 4) if scores else None,
            "median": round(quantile(sorted_scores, 0.5), 4) if scores else None,
            "p75": round(quantile(sorted_scores, 0.75), 4) if scores else None,
            "p95": round(quantile(sorted_scores, 0.95), 4) if scores else None,
            "max": round(max(scores), 4) if scores else None,
        },
        "risk_level_counts": bands,
        "risk_level_rates": {
            key: round(value / len(scores), 4) if scores else None for key, value in bands.items()
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("outputs/shhs/shhs1_features.jsonl"))
    parser.add_argument("--output", type=Path, default=Path("outputs/shhs/shhs1_scores.jsonl"))
    parser.add_argument(
        "--scenario-dir",
        type=Path,
        default=Path("services/api/model_artifacts/rls_experiments/sleep_heart_basic__apple"),
    )
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument(
        "--no-prevalence-adjustment",
        action="store_true",
        help="Use raw ensemble probability without population prevalence adjustment.",
    )
    args = parser.parse_args()

    adapter = RLSExperimentModelAdapter(
        args.scenario_dir,
        apply_prevalence_adjustment=not args.no_prevalence_adjustment,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)

    rows = 0
    scores: list[float] = []
    with args.input.open(encoding="utf-8") as source, args.output.open("w", encoding="utf-8") as sink:
        for line in source:
            if args.limit is not None and rows >= args.limit:
                break
            rows += 1
            features = json.loads(line)
            score = adapter.predict_proba(features)
            scores.append(score)
            sink.write(
                json.dumps(
                    {
                        "row_index": rows - 1,
                        "risk_score": score,
                        "risk_level": risk_level(score),
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )

    summary = summarize(scores, rows, adapter.version)
    summary["input"] = str(args.input)
    summary["output"] = str(args.output)
    summary["prevalence_adjusted"] = not args.no_prevalence_adjustment
    summary_path = args.output.with_suffix(".summary.json")
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
