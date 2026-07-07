import os
from pathlib import Path
import pickle
from typing import Any

from app.services.rls_experiments_adapter import RLSExperimentModelAdapter


ARTIFACT_DIR = Path(__file__).resolve().parents[2] / "model_artifacts"
RLS_EXPERIMENT_SCENARIOS = {
    "tier1": "sleep_heart_basic__apple",
    "tier2": "sleep_heart_basic_q__apple",
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
            scenario = RLS_EXPERIMENT_SCENARIOS.get(tier)
            scenario_dir = self.artifact_dir / "rls_experiments" / scenario if scenario else None
            if scenario_dir and scenario_dir.exists():
                cache_key = f"{tier}:rls_experiments"
                if cache_key not in self._cache:
                    adapter = RLSExperimentModelAdapter(scenario_dir)
                    if adapter.has_required_files():
                        self._cache[cache_key] = adapter
                return self._cache.get(cache_key)
            return None
        cache_key = f"{tier}:pkl"
        if cache_key not in self._cache:
            with path.open("rb") as handle:
                self._cache[cache_key] = pickle.load(handle)
        return self._cache[cache_key]

    def version(self, tier: str, using_fallback: bool, model: Any | None = None) -> str:
        if using_fallback:
            return f"{tier}-fallback-2026-07-01"
        if hasattr(model, "version"):
            return str(model.version)
        return f"{tier}-artifact-pkl"


model_registry = ModelRegistry()
