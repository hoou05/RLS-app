from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from app.schemas.agent import KnowledgeSnippet


KNOWLEDGE_BASE_DIR = Path(__file__).resolve().parents[2] / "knowledge_base"
TOPIC_PATHS = {
    "rls": ["rls", "safety"],
    "insomnia": ["insomnia", "general_sleep", "safety"],
    "osa": ["osa", "safety"],
    "general": ["general_sleep", "safety"],
}


@lru_cache
def load_knowledge_docs() -> list[dict[str, str]]:
    docs: list[dict[str, str]] = []
    for path in sorted(KNOWLEDGE_BASE_DIR.rglob("*.md")):
        text = path.read_text(encoding="utf-8")
        docs.append(
            {
                "path": str(path.relative_to(KNOWLEDGE_BASE_DIR)),
                "text": text,
                "source": _read_section(text, "# Source"),
                "intended_use": _read_section(text, "# Intended Use"),
                "summary": _read_section(text, "# Summary"),
            }
        )
    return docs


def retrieve_knowledge(topic: str, red_flags: list[str]) -> list[KnowledgeSnippet]:
    buckets = TOPIC_PATHS.get(topic, ["general_sleep", "safety"])
    results: list[KnowledgeSnippet] = []
    for doc in load_knowledge_docs():
        if not any(doc["path"].startswith(bucket + "/") for bucket in buckets):
            continue
        if not red_flags and doc["path"].startswith("safety/forbidden_medical_outputs"):
            continue
        results.append(
            KnowledgeSnippet(
                source=doc["source"] or doc["path"],
                intended_use=doc["intended_use"],
                snippet=doc["summary"],
            )
        )
    return results[:4]


def _read_section(text: str, header: str) -> str:
    lines = text.splitlines()
    collected: list[str] = []
    capture = False
    for line in lines:
        if line.strip() == header:
            capture = True
            continue
        if capture and line.startswith("# "):
            break
        if capture and line.strip():
            collected.append(line.strip("- ").strip())
    return " ".join(collected).strip()
