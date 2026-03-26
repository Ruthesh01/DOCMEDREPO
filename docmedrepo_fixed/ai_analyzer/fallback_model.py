"""
Fallback Model
Uses a local HuggingFace pipeline (Bio_ClinicalBERT for NER + rule-based
extraction) when the primary OpenAI model is unavailable.

This is intentionally lightweight — it won't match GPT-4o quality, but it
ensures the service never fully fails even when offline or rate-limited.

Architecture:
  1. Named Entity Recognition (NER) using emilyalsentzer/Bio_ClinicalBERT
     to extract medical entities (diseases, medications, tests)
  2. Rule-based abnormal value detection using regex patterns
  3. Simple extractive summarization (first N sentences of the text)
"""

import logging
import re
from typing import Any

logger = logging.getLogger("docmedrepo.fallback")

# ── Lazy-loaded model (only instantiated on first use) ────────────────────────
_ner_pipeline = None


def _get_ner_pipeline():
    """
    Lazily loads the BioClinicalBERT NER pipeline.
    Disabled for local development to avoid hanging downloads.
    """
    return None


# ── Regex patterns for common abnormal lab values ────────────────────────────
# Matches patterns like "HbA1c: 8.2% (High)", "WBC 12.5 H", "Glucose: 210 mg/dL ↑"
_ABNORMAL_PATTERNS = [
    # Pattern: "TEST_NAME: VALUE UNIT (High|Low|H|L|↑|↓)"
    re.compile(
        r"(?P<test>[A-Za-z][A-Za-z0-9\s\-/]{1,40})"   # test name
        r"[:\s]+(?P<value>[\d.,]+\s*(?:[a-zA-Z/%]+)?)" # numeric value + optional unit
        r"\s*(?P<flag>H\b|L\b|High|Low|↑|↓|HIGH|LOW|Abnormal|Elevated|Decreased)",
        re.IGNORECASE,
    ),
    # Pattern: "(H)" or "(L)" suffix after value
    re.compile(
        r"(?P<test>[A-Za-z][A-Za-z0-9\s\-/]{1,30})"
        r"[:\s]+(?P<value>[\d.,]+\s*(?:[a-zA-Z/%]+)?)"
        r"\s*\((?P<flag>H|L|High|Low)\)",
        re.IGNORECASE,
    ),
]

_FLAG_NORMALISE = {
    "h": "HIGH", "high": "HIGH", "elevated": "HIGH", "↑": "HIGH",
    "l": "LOW",  "low":  "LOW",  "decreased": "LOW",  "↓": "LOW",
    "abnormal": "HIGH",
}


def _extract_abnormal_values(text: str) -> list[dict[str, str]]:
    """
    Extracts abnormal lab values from text using regex patterns.

    Args:
        text: Report plain text

    Returns:
        List of dicts with 'test', 'value', 'flag' keys
    """
    results = []
    seen_tests = set()

    for pattern in _ABNORMAL_PATTERNS:
        for match in pattern.finditer(text):
            test  = match.group("test").strip().rstrip(":").strip()
            value = match.group("value").strip()
            flag  = match.group("flag").strip().lower()

            normalised_flag = _FLAG_NORMALISE.get(flag, "HIGH")

            # Deduplicate
            key = test.lower()
            if key not in seen_tests:
                seen_tests.add(key)
                results.append({
                    "test":  test,
                    "value": value,
                    "flag":  normalised_flag,
                })

    logger.debug(f"Rule-based extraction found {len(results)} abnormal values")
    return results[:15]  # cap at 15 to avoid noise


def _extract_entities_via_ner(text: str) -> tuple[list[str], list[str]]:
    """
    Uses Bio_ClinicalBERT NER to extract disease and medication entities.

    Args:
        text: Report plain text (will be truncated to 512 tokens internally)

    Returns:
        Tuple of (diagnoses_list, medications_list)
    """
    pipeline = _get_ner_pipeline()
    if pipeline is None:
        return [], []

    try:
        # NER works best on shorter chunks — process first 1000 chars
        chunk = text[:1000]
        entities = pipeline(chunk)

        diagnoses   = []
        medications = []

        for ent in entities:
            word  = ent.get("word", "").replace("##", "").strip()
            label = ent.get("entity_group", "").upper()
            score = ent.get("score", 0)

            if score < 0.75 or len(word) < 3:
                continue

            # BioClinicalBERT labels: DISEASE, CHEMICAL (medications), GENE, etc.
            if label in ("DISEASE", "CONDITION", "PROBLEM") and word not in diagnoses:
                diagnoses.append(word)
            elif label in ("CHEMICAL", "DRUG", "MEDICATION") and word not in medications:
                medications.append(word)

        logger.debug(
            f"NER extracted {len(diagnoses)} diagnoses, {len(medications)} medications"
        )
        return diagnoses[:10], medications[:10]

    except Exception as e:
        logger.error(f"NER pipeline error: {e}")
        return [], []


def _simple_extractive_summary(text: str, max_sentences: int = 4) -> str:
    """
    Returns the first N sentences of the text as a simple extractive summary.
    Used when the LLM is unavailable.

    Args:
        text:          Full report text
        max_sentences: Maximum number of sentences to include

    Returns:
        Summary string
    """
    # Split on sentence-ending punctuation
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    selected  = [s.strip() for s in sentences if len(s.strip()) > 20][:max_sentences]
    return " ".join(selected) if selected else text[:300].strip()


def _estimate_confidence(
    text: str,
    diagnoses: list,
    medications: list,
    abnormals: list,
) -> float:
    """
    Heuristically estimates analysis confidence based on extraction quality.

    Factors:
      - Length of input text (more text = more confidence)
      - Number of entities found
      - Presence of structured lab values

    Returns:
        Confidence score in [0.0, 0.6] range
        (capped at 0.6 — fallback should always score below primary)
    """
    score = 0.2  # baseline for fallback

    if len(text) > 500:
        score += 0.1
    if len(text) > 2000:
        score += 0.1
    if diagnoses:
        score += 0.1
    if medications:
        score += 0.05
    if abnormals:
        score += 0.05

    return min(score, 0.6)  # Never exceed 0.6 for fallback


def analyze_with_fallback(report_text: str) -> dict[str, Any]:
    """
    Performs best-effort medical report analysis using local NLP tools.
    Always tagged with source='fallback'.

    This function is synchronous (called from async context via the analyzer).

    Args:
        report_text: Extracted plain text from the medical report

    Returns:
        Analysis dict matching the AnalysisResult schema (without 'source' — added by caller)
    """
    logger.info(f"Fallback analysis on {len(report_text)} chars of text")

    # Step 1: NER-based entity extraction
    diagnoses, medications = _extract_entities_via_ner(report_text)

    # Step 2: Rule-based abnormal value detection
    abnormal_values = _extract_abnormal_values(report_text)

    # Step 3: Extractive summaries
    raw_summary = _simple_extractive_summary(report_text, max_sentences=4)

    patient_summary = (
        "This is an automated extract from your report. "
        "Key findings have been identified, but please consult your doctor for a full explanation. "
        f"{raw_summary}"
    )

    doctor_summary = (
        f"Automated fallback analysis. NER-extracted entities: "
        f"diagnoses={diagnoses}, medications={medications}. "
        f"Abnormal values detected: {len(abnormal_values)}. "
        "Manual clinical review recommended."
    )

    # Step 4: Heuristic confidence
    confidence = _estimate_confidence(report_text, diagnoses, medications, abnormal_values)

    return {
        "diagnoses":             diagnoses,
        "abnormal_values":       abnormal_values,
        "medications_mentioned": medications,
        "summary_for_patient":   patient_summary,
        "summary_for_doctor":    doctor_summary,
        "confidence_score":      confidence,
    }
