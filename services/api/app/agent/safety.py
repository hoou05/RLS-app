from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import yaml


RULES_PATH = Path(__file__).with_name("safety_rules.yaml")
MANDATORY_DISCLAIMER = (
    "This is sleep-health education and trend observation only. It does not replace medical diagnosis or treatment."
)


@lru_cache
def load_safety_rules() -> dict:
    return yaml.safe_load(RULES_PATH.read_text(encoding="utf-8"))


def detect_red_flags(question: str, notes: list[str]) -> list[str]:
    haystack = f"{question} {' '.join(notes)}".lower()
    checks = {
        "possible_osa_warning": ["apnea", "呼吸暂停", "choking", "憋醒", "喘", "snore", "打鼾"],
        "severe_daytime_sleepiness": ["sleepy driving", "driving", "开车犯困", "白天特别困", "daytime sleepiness"],
        "pregnancy_or_child": ["pregnan", "妊娠", "pregnancy", "child", "儿童"],
        "medical_comorbidity": ["kidney", "肾", "anemia", "贫血", "neuropathy", "神经"],
        "chest_pain_or_neuro": ["chest pain", "胸痛", "weakness", "无力", "numb", "麻木"],
        "medication_related": ["medication", "药", "停药", "换药", "dose", "剂量"],
    }
    flags = [name for name, terms in checks.items() if any(term in haystack for term in terms)]
    return flags + detect_forbidden_request(question)


def detect_forbidden_request(question: str) -> list[str]:
    lowered = question.lower()
    checks = {
        "unsafe_direct_diagnosis_request": ["diagnose me", "do i have", "am i rls", "是不是不宁腿", "我是不是得了", "你诊断"],
        "unsafe_medication_request": ["gabapentin", "pregabalin", "dopamine agonist", "安眠药", "处方药", "吃什么药", "用什么药"],
        "unsafe_dose_request": ["what dose", "how many mg", "mg", "剂量", "吃多少"],
        "unsafe_iron_request": ["take iron", "iron supplement", "补铁", "铁剂"],
        "unsafe_medication_change_request": [
            "stop medication",
            "stop my medication",
            "change medication",
            "change my medication",
            "停药",
            "换药",
            "加药",
        ],
        "unsafe_device_request": ["buy cpap", "buy a device", "购买设备", "买呼吸机"],
        "unsafe_cpap_request": ["cpap pressure", "adjust cpap", "cpap参数", "调cpap", "调节cpap"],
    }
    return [name for name, terms in checks.items() if any(term in lowered for term in terms)]


def is_forbidden_request(red_flags: list[str]) -> bool:
    return any(flag.startswith("unsafe_") for flag in red_flags)


def forbidden_request_response() -> str:
    return (
        "I cannot diagnose a sleep disorder, recommend prescription medicines, provide dosing, suggest iron-related treatment, "
        "advise treatment changes, recommend buying treatment devices, or set breathing-device parameters. I can help you track symptoms, "
        "explain general sleep-health concepts, and identify when to contact a clinician or sleep specialist."
    )


def enforce_guardrails(text: str) -> str:
    rules = load_safety_rules()
    lowered = text.lower()
    forbidden_fragments = {
        "direct_diagnosis": ["you have rls", "you have insomnia", "you have sleep apnea", "你就是", "你得了"],
        "prescription_medication": ["gabapentin", "pregabalin", "dopamine agonist", "处方药", "安眠药"],
        "medication_dose": ["mg", "milligram", "剂量"],
        "iron_supplement_instruction": ["take iron", "补铁", "ferrous"],
        "stop_or_change_medication": ["stop your medication", "change your medication", "停药", "换药", "加药"],
        "device_purchase_recommendation": ["buy a cpap", "purchase a device", "购买设备"],
        "cpap_pressure_adjustment": ["adjust cpap", "cpap pressure", "调节cpap"],
    }
    if any(any(fragment in lowered for fragment in forbidden_fragments[key]) for key in rules["forbidden_outputs"] if key in forbidden_fragments):
        text = (
            "I can only provide general sleep-health education, symptom tracking suggestions, and guidance on when to seek clinical care. "
            + MANDATORY_DISCLAIMER
        )
    if MANDATORY_DISCLAIMER not in text:
        text = f"{text} {MANDATORY_DISCLAIMER}"
    return text
