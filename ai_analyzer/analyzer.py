"""
AI Analyzer Pipeline
Sends extracted medical report text to the primary model (OpenAI GPT-4o)
and returns a structured JSON analysis result.

If the primary model fails or returns invalid JSON, falls back to
the local HuggingFace model via fallback_model.py.

Confidence warning is appended to both summaries when score < 0.6.
"""

import json
import logging
import os
from typing import Any

import httpx
from openai import AsyncOpenAI, APIError, APITimeoutError, RateLimitError

from fallback_model import analyze_with_fallback

logger = logging.getLogger("docmedrepo.analyzer")

# ── Constants ─────────────────────────────────────────────────────────────────
LOW_CONFIDENCE_THRESHOLD = 0.6
LOW_CONFIDENCE_WARNING = (
    "\n\n⚠️ Low confidence result. Please have a doctor review this report."
)

# ── System prompt ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """You are a highly accurate medical report analysis assistant.
You will receive the text of a medical report and must return ONLY a single valid JSON object.
Do not include any explanation, preamble, markdown, or code fences — ONLY the JSON.

The JSON must match this exact schema:
{
  "diagnoses": ["string"],
  "abnormal_values": [
    { "test": "string", "value": "string", "flag": "HIGH" | "LOW" | "NORMAL" }
  ],
  "medications_mentioned": ["string"],
  "summary_for_patient": "string — plain English, no medical jargon, max 100 words",
  "summary_for_doctor": "string — clinical language, concise, max 150 words",
  "confidence_score": number between 0.0 and 1.0
}

Rules:
- diagnoses: list of conditions, diseases, or findings mentioned. Empty list if none.
- abnormal_values: only include lab results or measurements that are flagged as abnormal
  or that have a value clearly outside the normal range. Empty list if none.
- medications_mentioned: all drug names, dosages, or treatments referenced.
- summary_for_patient: explain findings in simple, reassuring language a patient can understand.
  Never use abbreviations or Latin medical terms.
- summary_for_doctor: clinical summary for a physician reviewing the case.
  Use standard medical terminology and abbreviations.
- confidence_score: your confidence that the analysis is accurate (0 = not confident, 1 = very confident).
  Lower this when the input is illegible, incomplete, or ambiguous.

If the report text is too short or illegible to analyze, still return the schema with empty arrays,
placeholder summaries explaining the issue, and a confidence_score of 0.1.
"""


def _build_user_message(report_text: str) -> str:
    """
    Builds the user-turn message for the LLM.

    Args:
        report_text: Extracted plain text from the medical report

    Returns:
        Formatted prompt string
    """
    # Truncate very long reports to avoid hitting context limits
    max_chars = 12_000
    if len(report_text) > max_chars:
        logger.warning(
            f"Report text truncated from {len(report_text)} to {max_chars} chars for LLM"
        )
        report_text = report_text[:max_chars] + "\n\n[... report truncated ...]"

    return f"Analyze the following medical report and return the JSON:\n\n{report_text}"


def _parse_llm_json(raw: str) -> dict[str, Any]:
    """
    Safely parses the LLM response as JSON.
    Strips any accidental markdown fences before parsing.

    Args:
        raw: Raw string response from the LLM

    Returns:
        Parsed dict

    Raises:
        ValueError: If the string cannot be parsed as JSON
    """
    cleaned = raw.strip()

    # Strip ```json ... ``` or ``` ... ``` fences if the model adds them
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        # Remove first line (```json or ```) and last line (```)
        lines = [l for l in lines if not l.strip().startswith("```")]
        cleaned = "\n".join(lines).strip()

    return json.loads(cleaned)


def _validate_and_normalise(data: dict[str, Any], source: str) -> dict[str, Any]:
    """
    Validates the parsed JSON has all required fields and normalises types.
    Adds the 'source' field and applies the low-confidence warning.

    Args:
        data:   Parsed JSON dict from LLM
        source: 'primary' or 'fallback'

    Returns:
        Validated and normalised result dict
    """
    result = {
        "diagnoses":             list(data.get("diagnoses") or []),
        "abnormal_values":       list(data.get("abnormal_values") or []),
        "medications_mentioned": list(data.get("medications_mentioned") or []),
        "summary_for_patient":   str(data.get("summary_for_patient") or ""),
        "summary_for_doctor":    str(data.get("summary_for_doctor") or ""),
        "confidence_score":      float(data.get("confidence_score") or 0.5),
        "source":                source,
    }

    # Clamp confidence score to [0, 1]
    result["confidence_score"] = max(0.0, min(1.0, result["confidence_score"]))

    # Validate abnormal_values entries have required fields
    validated_abnormals = []
    for item in result["abnormal_values"]:
        if isinstance(item, dict) and "test" in item and "value" in item:
            validated_abnormals.append({
                "test":  str(item.get("test", "")),
                "value": str(item.get("value", "")),
                "flag":  str(item.get("flag", "NORMAL")).upper(),
            })
    result["abnormal_values"] = validated_abnormals

    # Append low-confidence warning to both summaries
    if result["confidence_score"] < LOW_CONFIDENCE_THRESHOLD:
        logger.warning(
            f"Low confidence score: {result['confidence_score']:.2f} — appending warning"
        )
        result["summary_for_patient"] += LOW_CONFIDENCE_WARNING
        result["summary_for_doctor"]  += LOW_CONFIDENCE_WARNING

    return result


async def _analyze_with_openai(report_text: str) -> dict[str, Any]:
    """
    Calls OpenAI GPT-4o with the report text and returns parsed structured output.

    Args:
        report_text: Extracted text from the medical report

    Returns:
        Parsed and validated result dict

    Raises:
        ValueError: If the response cannot be parsed as valid JSON
        APIError: If the OpenAI API returns an error
    """
    client = AsyncOpenAI(
        api_key=os.getenv("OPENAI_API_KEY"),
        timeout=httpx.Timeout(60.0, connect=10.0),
    )

    response = await client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user",   "content": _build_user_message(report_text)},
        ],
        max_tokens=1500,
        temperature=0.1,  # Low temperature for consistent, factual output
        response_format={"type": "json_object"},  # Enforce JSON mode
    )

    raw = response.choices[0].message.content
    logger.debug(f"OpenAI raw response (first 200 chars): {raw[:200]}")

    parsed = _parse_llm_json(raw)
    return _validate_and_normalise(parsed, source="primary")


async def analyze_report(report_text: str) -> dict[str, Any]:
    """
    Main analysis pipeline entry point.

    Attempts primary analysis via OpenAI GPT-4o.
    On any failure (API error, timeout, invalid JSON), falls back to
    the local HuggingFace model.

    Args:
        report_text: Extracted plain text from the medical report

    Returns:
        Structured analysis dict matching the AnalysisResult schema
    """
    openai_key = os.getenv("OPENAI_API_KEY")

    if openai_key:
        try:
            logger.info("Running analysis with OpenAI GPT-4o (primary)")
            result = await _analyze_with_openai(report_text)
            logger.info(
                f"Primary analysis succeeded: "
                f"confidence={result['confidence_score']:.2f}, "
                f"diagnoses={len(result['diagnoses'])}"
            )
            return result

        except (APIError, APITimeoutError, RateLimitError) as e:
            logger.warning(f"OpenAI API error — switching to fallback: {type(e).__name__}: {e}")

        except (json.JSONDecodeError, ValueError) as e:
            logger.warning(f"OpenAI returned invalid JSON — switching to fallback: {e}")

        except Exception as e:
            logger.error(f"Unexpected OpenAI error — switching to fallback: {e}")
    else:
        logger.warning("OPENAI_API_KEY not set — using fallback model directly")

    # ── Fallback ──────────────────────────────────────────────────────────────
    logger.info("Running analysis with fallback model")
    try:
        raw_result = analyze_with_fallback(report_text)
        result = _validate_and_normalise(raw_result, source="fallback")
        logger.info(
            f"Fallback analysis succeeded: confidence={result['confidence_score']:.2f}"
        )
        return result

    except Exception as e:
        logger.error(f"Fallback model also failed: {e}")
        # Last resort — return a safe empty result with low confidence
        return {
            "diagnoses":             [],
            "abnormal_values":       [],
            "medications_mentioned": [],
            "summary_for_patient":   (
                "We were unable to automatically analyse this report. "
                "Please consult your doctor for a review." + LOW_CONFIDENCE_WARNING
            ),
            "summary_for_doctor": (
                "Automated analysis failed. Manual review required." + LOW_CONFIDENCE_WARNING
            ),
            "confidence_score": 0.0,
            "source":           "failed",
        }
