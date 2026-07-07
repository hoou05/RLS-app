import json
import os
from pathlib import Path
import pickle
from typing import Any

from app.services.rls_experiments_adapter import RLSExperimentModelAdapter


ARTIFACT_DIR = Path(__file__).resolve().parents[2] / "model_artifacts"
RLS_EXPERIMENT_SCENARIOS = {
    "sleep": "sleep__apple",
    "sleep_heart": "sleep_heart__apple",
    "sleep_heart_basic": "sleep_heart_basic__apple",
    "sleep_heart_basic_q": "sleep_heart_basic_q__apple",
}

LEGACY_TIER_SCENARIOS = {
    "tier1": "sleep_heart_basic",
    "tier2": "sleep_heart_basic_q",
}


class ModelRegistry:
    def __init__(self, artifact_dir: Path = ARTIFACT_DIR) -> None:
        self.artifact_dir = artifact_dir
        self._cache: dict[str, Any] = {}

    def load(self, tier: str) -> Any | None:
        if os.getenv("RLS_FORCE_FALLBACK_MODEL", "").strip().lower() in {"1", "true", "yes"}:
            return None
        path = self.artifact_dir / f"{tier}_model.pkl"
        if not path.exists():
            scenario_key = LEGACY_TIER_SCENARIOS.get(tier, tier)
            scenario = RLS_EXPERIMENT_SCENARIOS.get(scenario_key)
            scenario_dir = self.artifact_dir / "rls_experiments" / scenario if scenario else None
            if scenario_dir and scenario_dir.exists():
                return self._load_scenario(scenario_key, scenario_dir)
            return None
        cache_key = f"{tier}:pkl"
        if cache_key not in self._cache:
            with path.open("rb") as handle:
                self._cache[cache_key] = pickle.load(handle)
        return self._cache[cache_key]

    def load_best(self, features: dict[str, Any], tier: str) -> Any | None:
        if os.getenv("RLS_FORCE_FALLBACK_MODEL", "").strip().lower() in {"1", "true", "yes"}:
            return None
        path = self.artifact_dir / f"{tier}_model.pkl"
        if path.exists():
            return self.load(tier)

        best: tuple[int, float, int, str, Path] | None = None
        for scenario_key, scenario_name in RLS_EXPERIMENT_SCENARIOS.items():
            scenario_dir = self.artifact_dir / "rls_experiments" / scenario_name
            meta_path = scenario_dir / "meta.json"
            if not meta_path.exists():
                continue
            adapter = RLSExperimentModelAdapter(scenario_dir)
            if not adapter.has_required_files():
                continue
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            internal = adapter.to_experiment_features(features)
            total = len(meta.get("features", []))
            available = sum(
                1
                for feature in meta.get("features", [])
                if _is_finite_number(internal.get(feature))
            )
            coverage = available / total if total else 0.0
            score = (available, coverage, -total, scenario_key, scenario_dir)
            if best is None or score > best:
                best = score

        if best is None:
            return None
        return self._load_scenario(best[3], best[4])

    def _load_scenario(self, scenario_key: str, scenario_dir: Path) -> Any | None:
        cache_key = f"{scenario_key}:rls_experiments"
        if cache_key not in self._cache:
            adapter = RLSExperimentModelAdapter(scenario_dir)
            if adapter.has_required_files():
                self._cache[cache_key] = adapter
        return self._cache.get(cache_key)

    def version(self, tier: str, using_fallback: bool, model: Any | None = None) -> str:
        if using_fallback:
            return f"{tier}-fallback-2026-07-01"
        if hasattr(model, "version"):
            return str(model.version)
        return f"{tier}-artifact-pkl"


model_registry = ModelRegistry()


def _is_finite_number(value: Any) -> bool:
    return isinstance(value, int | float) and value == value and value not in {float("inf"), float("-inf")}
