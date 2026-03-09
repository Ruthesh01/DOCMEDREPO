"""
OCR Processor
Extracts plain text from PDF, JPG, and PNG files.

Pipeline:
  - PDF  → pdfplumber (digital PDF) → pdf2image + pytesseract (scanned fallback)
  - JPG/PNG → pytesseract directly

All functions are synchronous (called from async FastAPI handlers via run_in_executor
if needed, but kept sync here to keep the OCR logic clean and testable).
"""

import io
import logging
from typing import Literal

import pdfplumber
import pytesseract
from PIL import Image, ImageFilter, ImageEnhance

logger = logging.getLogger("docmedrepo.ocr")

# Minimum character count from pdfplumber before we assume it's a scanned PDF
DIGITAL_PDF_MIN_CHARS = 50


def _preprocess_image_for_ocr(image: Image.Image) -> Image.Image:
    """
    Applies preprocessing steps to improve OCR accuracy on medical documents.

    Steps:
      1. Convert to grayscale
      2. Increase contrast
      3. Sharpen edges
      4. Resize to at least 300 DPI equivalent (scale up small images)

    Args:
        image: PIL Image object

    Returns:
        Preprocessed PIL Image
    """
    # Convert to grayscale
    image = image.convert("L")

    # Boost contrast — medical reports often have low contrast text
    enhancer = ImageEnhance.Contrast(image)
    image = enhancer.enhance(2.0)

    # Sharpen for cleaner edges
    image = image.filter(ImageFilter.SHARPEN)

    # Scale up if the image is small (OCR accuracy drops below ~150px height)
    width, height = image.size
    if height < 800:
        scale = 800 / height
        new_size = (int(width * scale), 800)
        image = image.resize(new_size, Image.LANCZOS)
        logger.debug(f"Upscaled image to {new_size} for better OCR accuracy")

    return image


def _ocr_image_bytes(image_bytes: bytes) -> str:
    """
    Runs pytesseract OCR on raw image bytes.

    Args:
        image_bytes: Raw image data (JPEG or PNG)

    Returns:
        Extracted text string
    """
    image = Image.open(io.BytesIO(image_bytes))
    preprocessed = _preprocess_image_for_ocr(image)

    # PSM 6 = assume a single uniform block of text (good for medical reports)
    custom_config = r"--oem 3 --psm 6"
    text = pytesseract.image_to_string(preprocessed, config=custom_config)
    return text.strip()


def _extract_from_digital_pdf(pdf_bytes: bytes) -> str:
    """
    Extracts text from a digitally-created PDF using pdfplumber.
    Much faster and more accurate than OCR for digital PDFs.

    Args:
        pdf_bytes: Raw PDF file bytes

    Returns:
        Concatenated text from all pages
    """
    text_parts = []
    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        for page_num, page in enumerate(pdf.pages, start=1):
            page_text = page.extract_text()
            if page_text:
                text_parts.append(page_text)
                logger.debug(f"Page {page_num}: extracted {len(page_text)} chars via pdfplumber")
    return "\n\n".join(text_parts)


def _extract_from_scanned_pdf(pdf_bytes: bytes) -> str:
    """
    Extracts text from a scanned PDF by converting each page to an image
    and running pytesseract OCR on it.

    Falls back to this when pdfplumber returns insufficient text.

    Args:
        pdf_bytes: Raw PDF file bytes

    Returns:
        OCR-extracted text from all pages
    """
    try:
        from pdf2image import convert_from_bytes
    except ImportError:
        raise RuntimeError("pdf2image is not installed. Run: pip install pdf2image")

    logger.info("PDF appears to be scanned — falling back to pdf2image + pytesseract")

    # Convert all pages to PIL images at 300 DPI
    pages = convert_from_bytes(pdf_bytes, dpi=300)
    text_parts = []

    for page_num, page_image in enumerate(pages, start=1):
        preprocessed = _preprocess_image_for_ocr(page_image)
        custom_config = r"--oem 3 --psm 6"
        page_text = pytesseract.image_to_string(preprocessed, config=custom_config)
        if page_text.strip():
            text_parts.append(page_text.strip())
        logger.debug(f"Page {page_num}: extracted {len(page_text)} chars via OCR")

    return "\n\n".join(text_parts)


def extract_text(
    file_bytes: bytes,
    file_type: Literal["pdf", "jpg", "png"],
) -> str:
    """
    Main entry point for text extraction.

    Routes to the appropriate extractor based on file type:
      - PDF: pdfplumber first, then pdf2image+pytesseract if needed
      - JPG/PNG: pytesseract directly

    Args:
        file_bytes: Raw file content as bytes
        file_type:  One of 'pdf', 'jpg', 'png'

    Returns:
        Extracted plain text

    Raises:
        ValueError: If an unsupported file_type is passed
        RuntimeError: If extraction fails catastrophically
    """
    if not file_bytes:
        raise ValueError("file_bytes cannot be empty")

    logger.info(f"Extracting text from {file_type} file ({len(file_bytes):,} bytes)")

    if file_type == "pdf":
        # Try digital extraction first
        text = _extract_from_digital_pdf(file_bytes)
        logger.info(f"pdfplumber extracted {len(text)} chars")

        # If we got too little text, the PDF is likely scanned
        if len(text.strip()) < DIGITAL_PDF_MIN_CHARS:
            logger.info(
                f"pdfplumber returned < {DIGITAL_PDF_MIN_CHARS} chars — "
                "assuming scanned PDF, switching to OCR"
            )
            text = _extract_from_scanned_pdf(file_bytes)

        return text

    elif file_type in ("jpg", "png"):
        text = _ocr_image_bytes(file_bytes)
        logger.info(f"pytesseract extracted {len(text)} chars from {file_type}")
        return text

    else:
        raise ValueError(f"Unsupported file_type: '{file_type}'. Expected 'pdf', 'jpg', or 'png'.")
