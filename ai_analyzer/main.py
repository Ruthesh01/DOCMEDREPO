"""
DocMedRepo AI Analyzer Service
FastAPI application exposing medical report analysis endpoints.

Fixes applied:
  H-01 — S3 key is now validated against a strict regex whitelist before use.
          All endpoints that can be called by the Node worker now require an
          X-Internal-Secret header to reject unknown callers.
  H-01 — boto3 S3 client is now a module-level singleton (one connection pool
          reused across all requests, same principle as the OpenAI fix).
"""

import os
import re
import logging
from contextlib import asynccontextmanager
from typing import Annotated

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, File, UploadFile, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from analyzer import analyze_report
from ocr_processor import extract_text

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("docmedrepo.ai")

# ── S3 key validation (H-01) ──────────────────────────────────────────────────
# Only accept keys that look exactly like: reports/<hex-objectid>/<uuid>.<ext>
# This prevents path traversal (../../), object enumeration, and injection.
_S3_KEY_RE = re.compile(
    r'^reports/[a-f0-9]{24}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|png)$'
)


def _validate_s3_key(s3_key: str) -> None:
    """
    Raises HTTP 400 if s3_key does not match the expected format.
    Called before any S3 operation to prevent path traversal and enumeration.
    """
    if not _S3_KEY_RE.match(s3_key):
        logger.warning(f"Rejected invalid S3 key format: {s3_key!r}")
        raise HTTPException(status_code=400, detail="Invalid S3 key format")


# ── Inter-service authentication (H-01) ───────────────────────────────────────
# The /analyze and /summarize endpoints are internal — they should only be
# reachable by the Node.js worker, not by external clients.
# Callers must supply X-Internal-Secret matching AI_SERVICE_SECRET env var.
def _require_internal_secret(x_internal_secret: Annotated[str | None, Header()] = None) -> None:
    """
    Dependency that rejects requests without a valid inter-service secret.
    Raises HTTP 403 if the header is missing or wrong.
    Set AI_SERVICE_SECRET to the same value in both the Node and Python envs.
    """
    expected = os.getenv("AI_SERVICE_SECRET", "")
    if not expected:
        # Secret not configured — log a warning but don't block (dev convenience).
        # In production, AI_SERVICE_SECRET must always be set.
        logger.warning(
            "AI_SERVICE_SECRET is not set — inter-service auth is DISABLED. "
            "Set this variable in production."
        )
        return
    if x_internal_secret != expected:
        logger.warning("Rejected request with invalid or missing X-Internal-Secret")
        raise HTTPException(status_code=403, detail="Forbidden")


# ── Singleton S3 client (H-01 / C-02 pattern) ────────────────────────────────
_s3_client = None


def _get_s3_client():
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client(
            "s3",
            aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
            aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY"),
            region_name=os.getenv("AWS_REGION", "ap-south-1"),
        )
        logger.debug("boto3 S3 singleton created")
    return _s3_client


# ── Lifespan (startup / shutdown logging) ────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("AI Analyzer service starting up...")
    yield
    logger.info("AI Analyzer service shutting down...")


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="DocMedRepo AI Analyzer",
    description="Analyzes medical reports using OCR + LLM and returns structured findings.",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "http://localhost:5000").split(","),
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


# ── Pydantic schemas ──────────────────────────────────────────────────────────
class S3AnalyzeRequest(BaseModel):
    """Request body when the Node.js worker calls /analyze with an S3 key."""
    s3_key: str
    file_type: str  # 'pdf' | 'jpg' | 'png'


class SummarizeRequest(BaseModel):
    """Request body for /summarize — accepts raw extracted text."""
    text: str


class AbnormalValue(BaseModel):
    test: str
    value: str
    flag: str  # HIGH | LOW | NORMAL


class AnalysisResult(BaseModel):
    diagnoses: list[str]
    abnormal_values: list[AbnormalValue]
    medications_mentioned: list[str]
    summary_for_patient: str
    summary_for_doctor: str
    confidence_score: float
    source: str  # 'primary' | 'fallback'


# ── Helper: download file from S3 into memory ─────────────────────────────────
def download_from_s3(s3_key: str) -> bytes:
    """
    Downloads a private S3 object into memory as bytes.
    Assumes s3_key has already been validated by _validate_s3_key().

    Args:
        s3_key: Validated S3 object key

    Returns:
        File bytes

    Raises:
        HTTPException 502 if S3 download fails
    """
    bucket = os.getenv("AWS_S3_BUCKET")
    if not bucket:
        raise HTTPException(status_code=500, detail="AWS_S3_BUCKET not configured")

    try:
        s3 = _get_s3_client()
        response = s3.get_object(Bucket=bucket, Key=s3_key)
        return response["Body"].read()
    except ClientError as e:
        code = e.response["Error"]["Code"]
        logger.error(f"S3 download failed for key '{s3_key}': {code}")
        raise HTTPException(status_code=502, detail=f"Failed to retrieve file from storage: {code}")
    except BotoCoreError as e:
        logger.error(f"S3 BotoCoreError: {e}")
        raise HTTPException(status_code=502, detail="Storage service unavailable")


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health", tags=["System"])
async def health_check():
    """
    Liveness probe endpoint.
    Returns the service status and which AI model is active.
    No auth required — used by load balancers and orchestrators.
    """
    primary_model = "gpt-4o" if os.getenv("OPENAI_API_KEY") else "unavailable"
    return {
        "status": "ok",
        "model": primary_model,
        "fallback_available": True,
    }


@app.post("/analyze", response_model=AnalysisResult, tags=["Analysis"])
async def analyze_from_s3(
    request: S3AnalyzeRequest,
    x_internal_secret: Annotated[str | None, Header()] = None,
    x_correlation_id: Annotated[str | None, Header()] = None,
):
    """
    Main analysis endpoint called by the Node.js AI worker.
    Downloads the file from S3, runs OCR if needed, then calls the AI pipeline.

    Requires X-Internal-Secret header (H-01).
    S3 key is validated against a strict format before use (H-01).
    Logs X-Correlation-Id for cross-service tracing (L-05).

    - **s3_key**: Private S3 object key (must match reports/<id>/<uuid>.<ext>)
    - **file_type**: 'pdf', 'jpg', or 'png'
    """
    # H-01: enforce inter-service auth
    _require_internal_secret(x_internal_secret)

    log_prefix = f"[corr={x_correlation_id}] " if x_correlation_id else ""
    logger.info(f"{log_prefix}Analyze request: s3_key={request.s3_key}, type={request.file_type}")

    if request.file_type not in ("pdf", "jpg", "png"):
        raise HTTPException(status_code=400, detail=f"Unsupported file type: {request.file_type}")

    # H-01: validate S3 key before touching S3
    _validate_s3_key(request.s3_key)

    file_bytes = download_from_s3(request.s3_key)

    try:
        extracted_text = extract_text(file_bytes, request.file_type)
    except Exception as e:
        logger.error(f"OCR extraction failed: {e}")
        raise HTTPException(status_code=422, detail=f"Text extraction failed: {str(e)}")

    if not extracted_text or len(extracted_text.strip()) < 20:
        raise HTTPException(
            status_code=422,
            detail="Could not extract meaningful text from the document. "
                   "Please ensure the file is legible.",
        )

    result = await analyze_report(extracted_text)
    logger.info(
        f"{log_prefix}Analysis complete: confidence={result['confidence_score']:.2f}, "
        f"source={result['source']}"
    )
    return result


@app.post("/analyze/upload", response_model=AnalysisResult, tags=["Analysis"])
async def analyze_uploaded_file(
    file: UploadFile = File(...),
    x_internal_secret: Annotated[str | None, Header()] = None,
):
    """
    Alternative analysis endpoint that accepts a direct file upload.
    Used by the Node worker in dev/test mode and by admin tooling.

    Requires X-Internal-Secret header (H-01).
    Accepts PDF, JPG, or PNG files up to 10MB.
    """
    # H-01: enforce inter-service auth
    _require_internal_secret(x_internal_secret)

    MAX_SIZE = 10 * 1024 * 1024  # 10 MB

    content_type_map = {
        "application/pdf": "pdf",
        "image/jpeg":      "jpg",
        "image/png":       "png",
    }

    file_type = content_type_map.get(file.content_type)
    if not file_type:
        raise HTTPException(
            status_code=400,
            detail="Unsupported file type. Please upload a PDF, JPG, or PNG.",
        )

    file_bytes = await file.read()
    if len(file_bytes) > MAX_SIZE:
        raise HTTPException(status_code=400, detail="File exceeds the 10MB size limit.")

    logger.info(f"Direct upload analysis: filename={file.filename}, size={len(file_bytes)}")

    try:
        extracted_text = extract_text(file_bytes, file_type)
    except Exception as e:
        logger.error(f"OCR extraction failed: {e}")
        raise HTTPException(status_code=422, detail=f"Text extraction failed: {str(e)}")

    if not extracted_text or len(extracted_text.strip()) < 20:
        raise HTTPException(
            status_code=422,
            detail="Could not extract meaningful text. Please ensure the file is legible.",
        )

    result = await analyze_report(extracted_text)
    return result


@app.post("/summarize", response_model=AnalysisResult, tags=["Analysis"])
async def summarize_text(
    request: SummarizeRequest,
    x_internal_secret: Annotated[str | None, Header()] = None,
):
    """
    Accepts raw extracted text and returns a structured AI summary.
    Useful when the caller has already performed OCR.

    Requires X-Internal-Secret header (H-01).
    """
    # H-01: enforce inter-service auth
    _require_internal_secret(x_internal_secret)

    if not request.text or len(request.text.strip()) < 20:
        raise HTTPException(status_code=400, detail="Text is too short to analyze.")

    if len(request.text) > 50_000:
        raise HTTPException(status_code=400, detail="Text exceeds maximum length of 50,000 characters.")

    logger.info(f"Summarize request: text_length={len(request.text)}")
    result = await analyze_report(request.text)
    return result
