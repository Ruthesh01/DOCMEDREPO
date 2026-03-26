# DocMedRepo — AI Analyzer Service

A FastAPI microservice that analyzes medical reports using OCR + LLM and returns structured clinical findings.

---

## Stack

| Layer | Technology |
|-------|-----------|
| API Framework | FastAPI + Uvicorn |
| Primary Model | OpenAI GPT-4o (`json_object` mode) |
| Fallback Model | Bio_ClinicalBERT (HuggingFace NER) |
| OCR (images) | pytesseract |
| OCR (scanned PDFs) | pdf2image + pytesseract |
| Digital PDFs | pdfplumber |
| File storage | AWS S3 (private bucket) |

---

## System Requirements

Install these system packages before running:

```bash
# Ubuntu / Debian
sudo apt-get install -y tesseract-ocr poppler-utils

# macOS
brew install tesseract poppler
```

---

## Setup

```bash
cd ai_analyzer

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Copy and fill environment variables
cp .env.example .env
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Optional | GPT-4o API key. If absent, fallback model is used directly |
| `AWS_ACCESS_KEY_ID` | Yes (production) | AWS credentials for S3 download |
| `AWS_SECRET_ACCESS_KEY` | Yes (production) | AWS credentials |
| `AWS_REGION` | Yes | e.g. `ap-south-1` |
| `AWS_S3_BUCKET` | Yes | Private S3 bucket name |
| `ALLOWED_ORIGINS` | Optional | Comma-separated CORS origins (default: `http://localhost:5000`) |

---

## Running

```bash
# Development (auto-reload)
uvicorn main:app --reload --port 8000

# Production
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
```

---

## API Endpoints

### `GET /health`
Liveness probe.
```json
{ "status": "ok", "model": "gpt-4o", "fallback_available": true }
```

### `POST /analyze`
Called by the Node.js AI worker. Downloads the file from S3 and analyzes it.
```json
// Request
{ "s3_key": "reports/userId/uuid.pdf", "file_type": "pdf" }

// Response
{
  "diagnoses": ["Type 2 Diabetes", "Hypertension"],
  "abnormal_values": [{ "test": "HbA1c", "value": "8.2%", "flag": "HIGH" }],
  "medications_mentioned": ["Metformin 500mg"],
  "summary_for_patient": "Your blood sugar levels are higher than normal...",
  "summary_for_doctor": "HbA1c at 8.2% indicates poor glycaemic control...",
  "confidence_score": 0.87,
  "source": "primary"
}
```

### `POST /analyze/upload`
Direct file upload (for testing and admin tools). Accepts `multipart/form-data`.

### `POST /summarize`
Accepts raw extracted text and returns a structured summary.
```json
{ "text": "Patient presents with elevated glucose levels..." }
```

---

## Analysis Pipeline

```
File (PDF/JPG/PNG)
       │
       ▼
  OCR Processor
  ├── Digital PDF  → pdfplumber
  ├── Scanned PDF  → pdf2image → pytesseract
  └── Image        → preprocess → pytesseract
       │
       ▼
  Extracted Text
       │
       ▼
  Primary: OpenAI GPT-4o (JSON mode)
       │
       ├── Success → validate → return (source: primary)
       │
       └── Failure (API error / rate limit / invalid JSON)
                │
                ▼
           Fallback: Bio_ClinicalBERT NER + regex
                │
                └── return (source: fallback)
```

---

## Low Confidence Warning

When `confidence_score < 0.6`, both summaries automatically include:

> ⚠️ Low confidence result. Please have a doctor review this report.

---

## Notes

- The fallback model downloads ~430MB on first use. Subsequent runs use the HuggingFace cache.
- For GPU inference, change `torch==2.3.0` to `torch[cuda]==2.3.0` in `requirements.txt` and set `device=0` in `fallback_model.py`.
- This service is stateless — all file data comes from S3 or direct upload.
