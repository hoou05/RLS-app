from __future__ import annotations

import argparse
import json
import math
import pickle
import sys
from pathlib import Path
from typing import Any

import numpy as np
import torch
import ubjson


ROOT = Path(__file__).resolve().parents[2]
API_ROOT = ROOT / "services" / "api"
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.services.rls_experiments_adapter import RLSExperimentModelAdapter  # noqa: E402


SCENARIOS = {
    "tier1": "sleep_heart_basic__apple",
    "tier2": "sleep_heart_basic_q__apple",
}


def logit(probability: float) -> float:
    probability = min(max(float(probability), 1e-15), 1.0 - 1e-15)
    return math.log(probability / (1.0 - probability))


def parse_base_score_margin(config: dict[str, Any]) -> float:
    value = config["learner"]["learner_model_param"]["base_score"]
    if isinstance(value, str):
        value = value.strip("[]")
    return logit(float(value))


def normalize_xgb_tree(tree: dict[str, Any], node_id: int = 0) -> dict[str, Any]:
    left = int(tree["left_children"][node_id])
    right = int(tree["right_children"][node_id])
    output: dict[str, Any] = {"nodeid": int(node_id)}
    if left == -1 and right == -1:
        output["leaf"] = float(tree["split_conditions"][node_id])
        return output

    default_left = bool(tree["default_left"][node_id])
    missing = left if default_left else right
    output.update(
        {
            "split_index": int(tree["split_indices"][node_id]),
            "split_condition": float(tree["split_conditions"][node_id]),
            "yes": left,
            "no": right,
            "missing": missing,
            "children": [
                normalize_xgb_tree(tree, left),
                normalize_xgb_tree(tree, right),
            ],
        }
    )
    return output


def export_xgboost_models(scenario_dir: Path, mask_k: int) -> list[dict[str, Any]]:
    models = []
    for idx in range(mask_k):
        with (scenario_dir / f"xgb_{idx}.ubj").open("rb") as handle:
            model = ubjson.load(handle)
        learner = model["learner"]
        trees = [normalize_xgb_tree(tree) for tree in learner["gradient_booster"]["model"]["trees"]]
        models.append(
            {
                "index": idx,
                "base_score_margin": parse_base_score_margin({"learner": learner}),
                "trees": trees,
            }
        )
    return models


def load_tabm_model(scenario_dir: Path, meta: dict[str, Any]) -> torch.nn.Module:
    import tabm as tabm_pkg

    cfg = meta["tabm_config"]
    model = tabm_pkg.TabM.make(
        n_num_features=len(meta["tabm_features"]),
        d_out=2,
        k=cfg["k"],
        n_blocks=cfg["n_blocks"],
        d_block=cfg["d_block"],
        dropout=cfg["dropout"],
    )
    state = torch.load(scenario_dir / "tabm_model.pt", map_location="cpu", weights_only=True)
    model.load_state_dict(state)
    model.eval()
    return model


def tensor_to_list(value: torch.Tensor) -> Any:
    return value.detach().cpu().numpy().astype(float).tolist()


def export_tabm_weights(scenario_dir: Path, meta: dict[str, Any]) -> dict[str, Any]:
    state = load_tabm_model(scenario_dir, meta).state_dict()
    blocks = []
    for idx in range(int(meta["tabm_config"]["n_blocks"])):
        prefix = f"backbone.blocks.{idx}.0"
        blocks.append(
            {
                "weight": tensor_to_list(state[f"{prefix}.weight"]),
                "r": tensor_to_list(state[f"{prefix}.r"]),
                "s": tensor_to_list(state[f"{prefix}.s"]),
                "bias": tensor_to_list(state[f"{prefix}.bias"]),
            }
        )
    return {
        "k": int(meta["tabm_config"]["k"]),
        "activation": "relu",
        "blocks": blocks,
        "output": {
            "weight": tensor_to_list(state["output.weight"]),
            "bias": tensor_to_list(state["output.bias"]),
        },
    }


def export_scenario(artifact_root: Path, output_dir: Path, tier: str, scenario_name: str) -> dict[str, Any]:
    scenario_dir = artifact_root / "rls_experiments" / scenario_name
    meta = json.loads((scenario_dir / "meta.json").read_text(encoding="utf-8"))

    with (scenario_dir / "tabm_qt.pkl").open("rb") as handle:
        quantile_transformer = pickle.load(handle)
    quantiles = np.asarray(quantile_transformer.quantiles_, dtype=np.float64)
    medians = np.load(scenario_dir / "tabm_medians.npy").astype(np.float64)

    return {
        "scenario": meta["scenario"],
        "features": meta["features"],
        "tabm_features": meta["tabm_features"],
        "train_prevalence": float(meta["train_prevalence"]),
        "apply_prevalence_adjustment": True,
        "tabm_medians": medians.tolist(),
        "tabm_weights": export_tabm_weights(scenario_dir, meta),
        "quantile_references": np.asarray(quantile_transformer.references_, dtype=np.float64).tolist(),
        "quantile_values_by_feature": quantiles.T.tolist(),
        "xgboost_models": export_xgboost_models(scenario_dir, int(meta["mask_k"])),
    }


def validation_inputs() -> dict[str, dict[str, Any]]:
    base = {
        "sleep_duration_minutes": 405,
        "sleep_efficiency": 80,
        "mean_heart_rate": 78,
        "resting_heart_rate": 69,
        "age": 51,
        "sex": "female",
        "height": 165,
        "weight": 62,
    }
    return {
        "tier1_demo": base,
        "tier2_demo": {
            **base,
            "family_history_rls": True,
            "diabetes": False,
            "psychiatric_medication": False,
            "non_leg_symptoms": None,
        },
        "tier2_higher_signal": {
            **base,
            "sleep_duration_minutes": 360,
            "sleep_efficiency": 72,
            "mean_heart_rate": 86,
            "resting_heart_rate": 76,
            "age": 64,
            "family_history_rls": True,
            "diabetes": True,
            "psychiatric_medication": False,
            "non_leg_symptoms": True,
        },
    }


def eval_raw_xgboost_tree(tree: dict[str, Any], vector: list[float]) -> float:
    node = 0
    default_left = list(tree["default_left"])
    while int(tree["left_children"][node]) != -1:
        value = vector[int(tree["split_indices"][node])]
        if value != value:
            node = int(tree["left_children"][node]) if default_left[node] else int(tree["right_children"][node])
        else:
            node = int(tree["left_children"][node]) if value < float(tree["split_conditions"][node]) else int(tree["right_children"][node])
    return float(tree["split_conditions"][node])


def raw_xgboost_probability(scenario_dir: Path, meta: dict[str, Any], internal: dict[str, float]) -> float:
    vector = [internal.get(name, float("nan")) for name in meta["features"]]
    probabilities = []
    for idx in range(int(meta["mask_k"])):
        with (scenario_dir / f"xgb_{idx}.ubj").open("rb") as handle:
            model = ubjson.load(handle)
        margin = sum(
            eval_raw_xgboost_tree(tree, vector)
            for tree in model["learner"]["gradient_booster"]["model"]["trees"]
        )
        probabilities.append(1.0 / (1.0 + math.exp(-margin)))
    return float(np.mean(probabilities))


def tabm_probability(scenario_dir: Path, meta: dict[str, Any], internal: dict[str, float]) -> float:
    with (scenario_dir / "tabm_qt.pkl").open("rb") as handle:
        quantile_transformer = pickle.load(handle)
    medians = np.load(scenario_dir / "tabm_medians.npy")
    raw = np.array([[internal.get(name, np.nan) for name in meta["tabm_features"]]], dtype=np.float32)
    nan_mask = np.isnan(raw)
    tabm_input = raw.copy()
    for idx in range(tabm_input.shape[1]):
        tabm_input[nan_mask[:, idx], idx] = medians[idx]
    transformed = quantile_transformer.transform(tabm_input).astype(np.float32)
    transformed[nan_mask] = 0.0
    model = load_tabm_model(scenario_dir, meta)
    with torch.inference_mode():
        output = model(torch.tensor(transformed)).float().numpy()
    shifted = output - np.max(output, axis=-1, keepdims=True)
    probabilities = np.exp(shifted) / np.sum(np.exp(shifted), axis=-1, keepdims=True)
    return float(probabilities[:, :, 1].mean(axis=1)[0])


def adjust_prevalence(p_model: float, train_prevalence: float, population_prevalence: float) -> float:
    if p_model <= 0 or p_model >= 1:
        return p_model
    odds_model = p_model / (1 - p_model)
    odds_train = train_prevalence / (1 - train_prevalence)
    likelihood_ratio = odds_model / odds_train
    odds_pop = population_prevalence / (1 - population_prevalence)
    posterior_odds = likelihood_ratio * odds_pop
    return posterior_odds / (1 + posterior_odds)


def write_validation(artifact_root: Path, output_dir: Path) -> None:
    rows = []
    for name, features in validation_inputs().items():
        tier = "tier1" if name.startswith("tier1") else "tier2"
        scenario_dir = artifact_root / "rls_experiments" / SCENARIOS[tier]
        meta = json.loads((scenario_dir / "meta.json").read_text(encoding="utf-8"))
        adapter = RLSExperimentModelAdapter(scenario_dir)
        internal = adapter.to_experiment_features(features)
        xgb_probability = raw_xgboost_probability(scenario_dir, meta, internal)
        tabm_prob = tabm_probability(scenario_dir, meta, internal)
        probability = adjust_prevalence(
            0.5 * xgb_probability + 0.5 * tabm_prob,
            float(meta["train_prevalence"]),
            0.07,
        )
        rows.append(
            {
                "name": name,
                "tier": tier,
                "features": features,
                "expected_probability": probability,
                "expected_xgboost_probability": xgb_probability,
                "expected_tabm_probability": tabm_prob,
                "model_version": adapter.version,
            }
        )
    (output_dir / "validation_cases.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export RLS XGBoost + TabM artifacts for iOS inference.")
    parser.add_argument(
        "--artifact-root",
        type=Path,
        default=API_ROOT / "model_artifacts",
        help="Path to services/api/model_artifacts.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / "ios_inference" / "Artifacts",
        help="Directory for RLSModelBundle.json and TabM mlpackages.",
    )
    parser.add_argument("--population-prevalence", type=float, default=0.07)
    parser.add_argument(
        "--write-validation",
        action="store_true",
        help="Also run the Python backend adapter and write validation_cases.json.",
    )
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    tiers = {
        tier: export_scenario(args.artifact_root, args.output_dir, tier, scenario)
        for tier, scenario in SCENARIOS.items()
    }
    bundle = {
        "schema_version": 1,
        "generated_by": "tools/ios_inference_export/export_ios_inference_assets.py",
        "population_prevalence": args.population_prevalence,
        "tiers": tiers,
    }
    (args.output_dir / "RLSModelBundle.json").write_text(
        json.dumps(bundle, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    if args.write_validation:
        write_validation(args.artifact_root, args.output_dir)
    print(f"Wrote iOS inference artifacts to {args.output_dir}")


if __name__ == "__main__":
    main()
