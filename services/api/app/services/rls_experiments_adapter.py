from __future__ import annotations

import json
import pickle
from pathlib import Path
from typing import Any


class ModelAdapterUnavailable(RuntimeError):
    pass


def _to_float(value: Any) -> float:
    try:
        if value is None:
            return float("nan")
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def _to_binary(value: Any) -> float:
    if value is None:
        return float("nan")
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "y", "是", "male", "m", "男"}:
        return 1.0
    if normalized in {"0", "false", "no", "n", "否", "female", "f", "女"}:
        return 0.0
    return float("nan")


def _first_present(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None


def _adjust_prevalence(p_model: float, train_prev: float, pop_prev: float) -> float:
    if p_model <= 0 or p_model >= 1:
        return p_model
    odds_model = p_model / (1 - p_model)
    odds_train = train_prev / (1 - train_prev)
    likelihood_ratio = odds_model / odds_train
    odds_pop = pop_prev / (1 - pop_prev)
    posterior_odds = likelihood_ratio * odds_pop
    return posterior_odds / (1 + posterior_odds)


class RLSExperimentModelAdapter:
    """Adapter for the exported XGBoost + TabM scenarios from rls-prediction-experiments."""

    def __init__(
        self,
        scenario_dir: Path,
        *,
        population_prevalence: float = 0.07,
        apply_prevalence_adjustment: bool = True,
    ) -> None:
        self.scenario_dir = scenario_dir
        self.population_prevalence = population_prevalence
        self.apply_prevalence_adjustment = apply_prevalence_adjustment
        self.meta: dict[str, Any] | None = None
        self._loaded = False
        self._xgb_models: list[Any] = []
        self._tabm_model: Any | None = None
        self._tabm_qt: Any | None = None
        self._tabm_medians: Any | None = None
        self._np: Any | None = None
        self._pd: Any | None = None
        self._scipy_special: Any | None = None
        self._torch: Any | None = None

    @property
    def version(self) -> str:
        if self.meta:
            return f"{self.meta.get('scenario', self.scenario_dir.name)}-xgb-tabm-v2"
        return f"{self.scenario_dir.name}-xgb-tabm-v2"

    def has_required_files(self) -> bool:
        if not (self.scenario_dir / "meta.json").exists():
            return False
        try:
            meta = json.loads((self.scenario_dir / "meta.json").read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return False
        required = ["tabm_model.pt", "tabm_qt.pkl", "tabm_medians.npy"]
        required += [f"xgb_{idx}.ubj" for idx in range(int(meta.get("mask_k", 0)))]
        return all((self.scenario_dir / name).exists() for name in required)

    def load(self) -> None:
        if self._loaded:
            return
        if not self.has_required_files():
            raise ModelAdapterUnavailable(f"Missing model files in {self.scenario_dir}")
        try:
            import numpy as np
            import pandas as pd
            import scipy.special
            from xgboost import XGBClassifier
        except ImportError as exc:
            raise ModelAdapterUnavailable(
                "Real RLS model dependencies are not installed. Install services/api/requirements-model.txt."
            ) from exc

        self._np = np
        self._pd = pd
        self._scipy_special = scipy.special
        self.meta = json.loads((self.scenario_dir / "meta.json").read_text(encoding="utf-8"))

        self._xgb_models = []
        for idx in range(int(self.meta["mask_k"])):
            model = XGBClassifier()
            model.load_model(str(self.scenario_dir / f"xgb_{idx}.ubj"))
            self._xgb_models.append(model)

        try:
            import tabm as tabm_pkg
            import torch
        except ImportError as exc:
            raise ModelAdapterUnavailable(
                "Real RLS model dependencies are not installed. Install services/api/requirements-model.txt."
            ) from exc

        self._torch = torch

        cfg = self.meta["tabm_config"]
        n_features = len(self.meta["tabm_features"])
        device = torch.device("cpu")
        tabm_model = tabm_pkg.TabM.make(
            n_num_features=n_features,
            d_out=2,
            k=cfg["k"],
            n_blocks=cfg["n_blocks"],
            d_block=cfg["d_block"],
            dropout=cfg["dropout"],
        ).to(device)
        tabm_model.load_state_dict(
            torch.load(self.scenario_dir / "tabm_model.pt", map_location=device, weights_only=True)
        )
        tabm_model.eval()
        self._tabm_model = tabm_model

        with (self.scenario_dir / "tabm_qt.pkl").open("rb") as handle:
            self._tabm_qt = pickle.load(handle)
        self._tabm_medians = np.load(self.scenario_dir / "tabm_medians.npy")
        self._loaded = True

    def predict_proba(self, feature_dict: dict[str, Any]) -> float:
        self.load()
        assert self.meta is not None
        assert self._np is not None
        assert self._pd is not None
        assert self._scipy_special is not None
        assert self._torch is not None
        assert self._tabm_model is not None
        assert self._tabm_qt is not None
        assert self._tabm_medians is not None

        internal = self.to_experiment_features(feature_dict)
        xgb_frame = self._pd.DataFrame([{name: internal.get(name, self._np.nan) for name in self.meta["features"]}])
        tabm_array = self._np.array(
            [[internal.get(name, self._np.nan) for name in self.meta["tabm_features"]]],
            dtype=self._np.float32,
        )

        xgb_prob = float(self._np.mean([model.predict_proba(xgb_frame)[:, 1] for model in self._xgb_models]))

        tabm_input = tabm_array.copy()
        nan_mask = self._np.isnan(tabm_input)
        for idx in range(tabm_input.shape[1]):
            tabm_input[nan_mask[:, idx], idx] = self._tabm_medians[idx]
        transformed = self._tabm_qt.transform(tabm_input).astype(self._np.float32)
        transformed[nan_mask] = 0.0
        tensor = self._torch.tensor(transformed)
        with self._torch.inference_mode():
            output = self._tabm_model(tensor).float()
            tabm_prob = float(
                self._scipy_special.softmax(output.cpu().numpy(), axis=-1).mean(axis=1)[0, 1]
            )

        ensemble_prob = 0.5 * xgb_prob + 0.5 * tabm_prob
        if self.apply_prevalence_adjustment:
            ensemble_prob = _adjust_prevalence(
                ensemble_prob,
                float(self.meta.get("train_prevalence", 0.1829123580267842)),
                self.population_prevalence,
            )
        return round(min(max(float(ensemble_prob), 0.0), 1.0), 4)

    def to_experiment_features(self, feature_dict: dict[str, Any]) -> dict[str, float]:
        height = _to_float(feature_dict.get("height") or feature_dict.get("height_cm"))
        weight = _to_float(feature_dict.get("weight") or feature_dict.get("weight_kg"))
        bmi = _to_float(feature_dict.get("bmi"))
        if bmi != bmi and height == height and weight == weight and height > 0:
            bmi = weight / (height / 100) ** 2

        mean_hr = _to_float(feature_dict.get("mean_heart_rate"))
        resting_hr = _to_float(feature_dict.get("resting_heart_rate"))
        min_hr = _to_float(feature_dict.get("min_heart_rate"))
        max_hr = _to_float(feature_dict.get("max_heart_rate"))
        avg_minus_min = _to_float(feature_dict.get("average_minus_min_heart_rate"))
        max_minus_avg = _to_float(feature_dict.get("max_minus_average_heart_rate"))
        if avg_minus_min != avg_minus_min and mean_hr == mean_hr and min_hr == min_hr:
            avg_minus_min = mean_hr - min_hr
        elif avg_minus_min != avg_minus_min and mean_hr == mean_hr and resting_hr == resting_hr:
            avg_minus_min = max(mean_hr - resting_hr, 0.0)
        if max_minus_avg != max_minus_avg and mean_hr == mean_hr and max_hr == max_hr:
            max_minus_avg = max_hr - mean_hr

        internal = {
            "总睡眠时间/分": _to_float(feature_dict.get("sleep_duration_minutes")),
            "睡眠效率%": _to_float(feature_dict.get("sleep_efficiency")),
            "WASO/分 入睡后清醒时间": _to_float(feature_dict.get("waso_minutes")),
            "睡眠潜伏期/分": _to_float(feature_dict.get("sleep_latency_minutes")),
            "REM睡眠潜伏期/分": _to_float(feature_dict.get("rem_latency_minutes")),
            "W期时间": _to_float(feature_dict.get("awake_stage_minutes")),
            "睡眠平均SPO2": _to_float(_first_present(feature_dict.get("average_spo2"), feature_dict.get("average_spo2_percent"))),
            "睡眠最低SPO2": _to_float(_first_present(feature_dict.get("minimum_spo2"), feature_dict.get("minimum_spo2_percent"))),
            "N1N2时间": _to_float(_first_present(feature_dict.get("light_sleep_minutes"), feature_dict.get("n1n2_minutes"))),
            "N1N2%": _to_float(_first_present(feature_dict.get("light_sleep_percent"), feature_dict.get("n1n2_percent"))),
            "N3时间": _to_float(_first_present(feature_dict.get("deep_sleep_minutes"), feature_dict.get("n3_minutes"))),
            "N3%": _to_float(_first_present(feature_dict.get("deep_sleep_percent"), feature_dict.get("n3_percent"))),
            "R期时间": _to_float(_first_present(feature_dict.get("rem_sleep_minutes"), feature_dict.get("r_minutes"))),
            "R%": _to_float(_first_present(feature_dict.get("rem_sleep_percent"), feature_dict.get("r_percent"))),
            "平均心率": mean_hr,
            "平均-最慢心率差值": avg_minus_min,
            "最快-平均心率差值": max_minus_avg,
            "性别_男1女0": _to_binary(feature_dict.get("sex")),
            "身高cm": height,
            "体重Kg": weight,
            "年龄_发病年龄合并": _to_float(feature_dict.get("age")),
            "BMI": bmi,
            "家系（口述或诊断确认家族内有患病）": _to_binary(feature_dict.get("family_history_rls")),
            "糖尿病": _to_binary(feature_dict.get("diabetes")),
            "精神类药物": _to_binary(feature_dict.get("psychiatric_medication")),
            "除腿部以外部位受累": _to_binary(feature_dict.get("non_leg_symptoms")),
        }

        explicit = feature_dict.get("experiment_features")
        if isinstance(explicit, dict):
            for key, value in explicit.items():
                internal[key] = _to_float(value)
        return internal
