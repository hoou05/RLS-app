from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import yaml

from app.schemas.agent import EducationPrescription, SleepTrendSummary


TEMPLATES_DIR = Path(__file__).resolve().parents[2] / "templates"


@lru_cache
def load_templates() -> list[dict]:
    templates: list[dict] = []
    for path in sorted(TEMPLATES_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        if isinstance(data, list):
            templates.extend(data)
        elif isinstance(data, dict):
            templates.append(data)
    return templates


def select_templates(mode: str, trend: SleepTrendSummary | None, red_flags: list[str], topic: str) -> list[EducationPrescription]:
    selected: list[EducationPrescription] = []
    for template in load_templates():
        category = template.get("category", "")
        condition = template.get("condition", "general")
        applies_to = template.get("applies_to_modes", ["trend", "guide", "question"])
        if mode not in applies_to:
            continue
        if category == "red_flag_referral" and not red_flags:
            continue
        if topic == "rls" and condition not in {"general", "RLS"}:
            continue
        if topic == "insomnia" and condition not in {"general", "insomnia"}:
            continue
        if topic == "osa" and condition not in {"general", "OSA"}:
            continue
        if category == "sleep_schedule_regularization" and trend and not trend.irregular_schedule_flag:
            continue
        if category == "rls_lifestyle_advice" and trend and not trend.possible_rls_pattern_flag and topic != "rls":
            continue
        selected.append(
            EducationPrescription(
                template_id=template["template_id"],
                category=category,
                text=str(template["text"]).strip(),
            )
        )
    return selected[:4]
