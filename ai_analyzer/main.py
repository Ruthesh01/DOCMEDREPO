"""
DocMedRepo AI Analyzer Service
FastAPI application exposing medical report analysis endpoints.
"""

import os
import logging
from contextlib import asynccontextmanager

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, File, UploadFile, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional

from analyzer import analyze_report
from ocr_processor import extract_text

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("docmedrepo.ai")

# ── AWS S3 client (lazy — only needed when s3_key is passed) ─────────────────
def get_s3_client():
    return boto3.client(
        "s3",
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY"),
        region_name=os.getenv("AWS_REGION", "ap-south-1"),
    )


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

    Args:
        s3_key: The S3 object key (not a public URL)

    Returns:
        File bytes

    Raises:
        HTTPException 502 if S3 download fails
    """
    bucket = os.getenv("AWS_S3_BUCKET")
    if not bucket:
        raise HTTPException(status_code=500, detail="AWS_S3_BUCKET not configured")

    try:
        s3 = get_s3_client()
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
    """
    primary_model = "gpt-4o" if os.getenv("OPENAI_API_KEY") else "unavailable"
    return {
        "status": "ok",
        "model": primary_model,
        "fallback_available": True,
    }


@app.post("/analyze", response_model=AnalysisResult, tags=["Analysis"])
async def analyze_from_s3(request: S3AnalyzeRequest):
    """
    Main analysis endpoint called by the Node.js AI worker.
    Downloads the file from S3, runs OCR if needed, then calls the AI pipeline.

    - **s3_key**: Private S3 object key
    - **file_type**: 'pdf', 'jpg', or 'png'
    """
    logger.info(f"Analyze request: s3_key={request.s3_key}, type={request.file_type}")

    if request.file_type not in ("pdf", "jpg", "png"):
        raise HTTPException(status_code=400, detail=f"Unsupported file type: {request.file_type}")

    # Download from S3
    file_bytes = download_from_s3(request.s3_key)

    # Extract text via OCR pipeline
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

    # Run AI analysis
    result = await analyze_report(extracted_text)
    logger.info(
        f"Analysis complete: confidence={result['confidence_score']:.2f}, "
        f"source={result['source']}"
    )
    return result


@app.post("/analyze/upload", response_model=AnalysisResult, tags=["Analysis"])
async def analyze_uploaded_file(file: UploadFile = File(...)):
    """
    Alternative analysis endpoint that accepts a direct file upload.
    Useful for testing and for admin tooling.

    Accepts PDF, JPG, or PNG files up to 10MB.
    """
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
async def summarize_text(request: SummarizeRequest):
    """
    Accepts raw extracted text and returns a structured AI summary.
    Useful when the caller has already performed OCR.
    """
    if not request.text or len(request.text.strip()) < 20:
        raise HTTPException(status_code=400, detail="Text is too short to analyze.")

    if len(request.text) > 50_000:
        raise HTTPException(status_code=400, detail="Text exceeds maximum length of 50,000 characters.")

    logger.info(f"Summarize request: text_length={len(request.text)}")
    result = await analyze_report(request.text)
    return result
