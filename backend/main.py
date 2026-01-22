import os
import json
from io import BytesIO
from typing import Any, Dict, List, Optional

import requests
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel

# PDF (ReportLab)
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import cm
from reportlab.lib.utils import ImageReader
from reportlab.lib import colors

load_dotenv()

# -----------------------------
# Load env
# -----------------------------
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "").strip()
if not GROQ_API_KEY:
    print("⚠️ GROQ_API_KEY is missing. Set it in .env or Render env vars.")

# -----------------------------
# FastAPI app
# -----------------------------
app = FastAPI(title="SprintSlides Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # hackathon mode
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------
# Paths
# -----------------------------
BASE_DIR = os.path.dirname(__file__)
LOGO_PATH = os.path.join(BASE_DIR, "assets", "logo.png")  # backend/assets/logo.png

# -----------------------------
# Request schemas
# -----------------------------
class DeckRequest(BaseModel):
    topic: str
    slideCount: Optional[int] = 5


class PdfRequest(BaseModel):
    topic: str
    slides: List[Dict[str, Any]]


# -----------------------------
# Prompt builders
# -----------------------------
def build_prompt(topic: str, n: int) -> str:
    return f"""
Return ONLY strict JSON. No markdown. No commentary.

You are an expert academic coach.

Create a {n}-slide revision deck for the topic: "{topic}".
Focus strongly on:
1) Active Recall
2) Structural Learning

STRICT RULES:
- Output MUST be valid JSON
- Must start with {{ and end with }}
- No extra text before or after JSON
- "slides" MUST be a JSON ARRAY (list)
- EXACTLY {n} slides
- Never return slides as an object/dict

Schema:
{{
  "slides": [
    {{
      "type": "overview|core_concepts|active_recall|examples|exam_tips",
      "title": "string",
      "content": "string"
    }}
  ]
}}

Slide requirements:
- Each slide should be rich: 8–12 bullet points OR detailed explanation
- Assume exam revision: include definitions, key concepts, common traps/mistakes
- Use \\n for newlines in content
- Ensure JSON is complete (quotes closed etc.)

Now output ONLY the JSON.
""".strip()


def build_retry_prompt(topic: str, n: int) -> str:
    return f"""
RETURN JSON ONLY.

Schema:
{{
  "slides": [
    {{
      "type": "overview|core_concepts|active_recall|examples|exam_tips",
      "title": "string",
      "content": "string"
    }}
  ]
}}

RULES:
- slides MUST be an array
- EXACTLY {n} slides
- JSON only. Nothing else.
- Keep content clear and complete.
- Use \\n between bullet points.

TOPIC: {topic}
""".strip()


# -----------------------------
# Helpers
# -----------------------------
def strip_markdown_fences(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        first_nl = t.find("\n")
        if first_nl != -1:
            t = t[first_nl + 1 :]
        last = t.rfind("```")
        if last != -1:
            t = t[:last]
    return t.strip()


def force_json_only(text: str) -> str:
    t = text.strip()
    start = t.find("{")
    end = t.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return t
    return t[start : end + 1].strip()


def estimate_max_tokens(n: int) -> int:
    # Safe scaling 3-15 slides
    return min(6500, 1200 + (n * 350))


def safe_json_load(raw: str) -> Dict[str, Any]:
    cleaned = force_json_only(strip_markdown_fences(raw))
    try:
        return json.loads(cleaned)
    except Exception:
        raise HTTPException(
            status_code=500,
            detail={
                "error": "Invalid JSON from model",
                "cleaned_preview": cleaned[:900],
            },
        )


def normalize_slides(decoded: Dict[str, Any], n: int) -> Optional[List[Dict[str, Any]]]:
    slides = decoded.get("slides")

    # Model sometimes returns dict instead of list
    if isinstance(slides, dict):
        slides = list(slides.values())

    if not isinstance(slides, list):
        return None

    # Trim if too many
    if len(slides) > n:
        slides = slides[:n]

    if len(slides) != n:
        return None

    final: List[Dict[str, Any]] = []
    for s in slides:
        if not isinstance(s, dict):
            return None

        slide_type = str(s.get("type", "overview")).strip()
        title = str(s.get("title", "")).strip()
        content = str(s.get("content", "")).strip()

        final.append({"type": slide_type, "title": title, "content": content})

    return final


# -----------------------------
# Groq call
# -----------------------------
def groq_chat(prompt: str, model: str, max_tokens: int, json_mode: bool = True) -> str:
    if not GROQ_API_KEY:
        raise HTTPException(status_code=500, detail="GROQ_API_KEY missing on server")

    url = "https://api.groq.com/openai/v1/chat/completions"

    payload: Dict[str, Any] = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "You output ONLY valid JSON. Never add any other text.",
            },
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.25,
        "max_tokens": max_tokens,
    }

    if json_mode:
        payload["response_format"] = {"type": "json_object"}

    resp = requests.post(
        url,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {GROQ_API_KEY}",
        },
        json=payload,
        timeout=90,
    )

    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)

    data = resp.json()
    return data["choices"][0]["message"]["content"]


# -----------------------------
# PDF helpers
# -----------------------------
def wrap_text(text: str, max_chars: int = 95) -> List[str]:
    words = text.split()
    lines = []
    current = ""
    for w in words:
        if len(current) + len(w) + 1 <= max_chars:
            current = f"{current} {w}".strip()
        else:
            if current:
                lines.append(current)
            current = w
    if current:
        lines.append(current)
    return lines


def build_pdf(topic: str, slides: List[Dict[str, Any]]) -> bytes:
    buffer = BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4

    # -----------------------------
    # Title Page
    # -----------------------------
    c.setFillColor(colors.black)
    c.rect(0, 0, width, height, fill=1)

    if os.path.exists(LOGO_PATH):
        logo = ImageReader(LOGO_PATH)
        logo_w = 16 * cm
        logo_h = 4 * cm
        c.drawImage(
            logo,
            (width - logo_w) / 2,
            height - 7 * cm,
            width=logo_w,
            height=logo_h,
            mask="auto",
        )

    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 28)
    c.drawCentredString(width / 2, height - 10.2 * cm, "SprintSlidesAI")

    c.setFont("Helvetica", 16)
    c.setFillColor(colors.HexColor("#9CA3AF"))
    c.drawCentredString(width / 2, height - 11.5 * cm, f"Topic: {topic}")

    c.setFont("Helvetica", 11)
    c.setFillColor(colors.HexColor("#6B7280"))
    c.drawCentredString(width / 2, 2.2 * cm, "Generated using Groq + FastAPI")
    c.showPage()

    # -----------------------------
    # Slide Pages
    # -----------------------------
    for i, s in enumerate(slides, start=1):
        slide_type = str(s.get("type", "slide")).replace("_", " ").title()
        title = str(s.get("title", "Untitled")).strip()
        content = str(s.get("content", "")).strip()

        # Background
        c.setFillColor(colors.HexColor("#0A0D14"))
        c.rect(0, 0, width, height, fill=1)

        # Small logo header
        if os.path.exists(LOGO_PATH):
            logo = ImageReader(LOGO_PATH)
            c.drawImage(
                logo,
                1.4 * cm,
                height - 2.2 * cm,
                width=5.5 * cm,
                height=1.35 * cm,
                mask="auto",
            )

        # Slide count
        c.setFillColor(colors.HexColor("#9CA3AF"))
        c.setFont("Helvetica", 10)
        c.drawRightString(width - 1.6 * cm, height - 1.7 * cm, f"{i} / {len(slides)}")

        # Type badge
        c.setFillColor(colors.HexColor("#6366F1"))
        c.setFont("Helvetica-Bold", 11)
        c.drawString(1.5 * cm, height - 3.2 * cm, slide_type.upper())

        # Title
        c.setFillColor(colors.white)
        c.setFont("Helvetica-Bold", 22)
        c.drawString(1.5 * cm, height - 4.5 * cm, title)

        # Divider
        c.setStrokeColor(colors.HexColor("#6366F1"))
        c.setLineWidth(2)
        c.line(1.5 * cm, height - 5.0 * cm, 6.0 * cm, height - 5.0 * cm)

        # Content
        y = height - 6.0 * cm
        c.setFillColor(colors.HexColor("#D1D5DB"))
        c.setFont("Helvetica", 12)

        blocks = content.split("\n")
        for block in blocks:
            block = block.strip()
            if not block:
                y -= 10
                continue

            wrapped = wrap_text(block, max_chars=95)
            for line in wrapped:
                if y < 2.5 * cm:
                    c.showPage()
                    c.setFillColor(colors.HexColor("#0A0D14"))
                    c.rect(0, 0, width, height, fill=1)

                    # repeated header logo
                    if os.path.exists(LOGO_PATH):
                        logo = ImageReader(LOGO_PATH)
                        c.drawImage(
                            logo,
                            1.4 * cm,
                            height - 2.2 * cm,
                            width=5.5 * cm,
                            height=1.35 * cm,
                            mask="auto",
                        )

                    y = height - 3.0 * cm
                    c.setFillColor(colors.HexColor("#D1D5DB"))
                    c.setFont("Helvetica", 12)

                c.drawString(1.7 * cm, y, line)
                y -= 14

        # Footer
        c.setFillColor(colors.HexColor("#6B7280"))
        c.setFont("Helvetica", 10)
        c.drawCentredString(width / 2, 1.4 * cm, "SprintSlidesAI • Study smarter ⚡")

        c.showPage()

    c.save()
    buffer.seek(0)
    return buffer.read()


# -----------------------------
# Routes
# -----------------------------
@app.get("/")
def root():
    return {"ok": True, "service": "SprintSlides Backend", "status": "running"}


@app.post("/generateDeck")
def generate_deck(req: DeckRequest):
    topic = req.topic.strip()
    n = int(req.slideCount or 5)

    if not topic:
        raise HTTPException(status_code=400, detail="topic is required")
    if n < 3 or n > 15:
        raise HTTPException(status_code=400, detail="slideCount must be between 3 and 15")

    model = "llama-3.1-8b-instant"
    max_tokens = estimate_max_tokens(n)

    # Attempt 1
    prompt = build_prompt(topic, n)
    raw1 = groq_chat(prompt, model=model, max_tokens=max_tokens, json_mode=True)
    decoded1 = safe_json_load(raw1)
    slides = normalize_slides(decoded1, n)

    # Retry once
    if slides is None:
        retry_prompt = build_retry_prompt(topic, n)
        raw2 = groq_chat(retry_prompt, model=model, max_tokens=max_tokens + 1200, json_mode=True)
        decoded2 = safe_json_load(raw2)
        slides = normalize_slides(decoded2, n)

        if slides is None:
            raise HTTPException(
                status_code=500,
                detail={
                    "error": f"Model output inconsistent. Expected {n} slides.",
                    "attempt1_preview": str(decoded1)[:900],
                    "attempt2_preview": str(decoded2)[:900],
                },
            )

    return {"ok": True, "slides": slides}


# ✅ POST PDF (optional if you want Flutter to send slides)
@app.post("/downloadPdf")
def download_pdf(req: PdfRequest):
    topic = req.topic.strip()
    slides = req.slides

    if not topic:
        raise HTTPException(status_code=400, detail="topic is required")
    if not isinstance(slides, list) or len(slides) == 0:
        raise HTTPException(status_code=400, detail="slides list is required")

    pdf_bytes = build_pdf(topic, slides)
    filename = f"SprintSlidesAI_{topic.replace(' ', '_')}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ✅ GET PDF (BEST for Flutter Web download)
@app.get("/downloadPdf")
def download_pdf_get(topic: str, slideCount: int = 5):
    topic = topic.strip()
    n = int(slideCount or 5)

    if not topic:
        raise HTTPException(status_code=400, detail="topic is required")
    if n < 3 or n > 15:
        raise HTTPException(status_code=400, detail="slideCount must be between 3 and 15")

    # generate slides again on backend
    model = "llama-3.1-8b-instant"
    max_tokens = estimate_max_tokens(n)

    prompt = build_prompt(topic, n)
    raw1 = groq_chat(prompt, model=model, max_tokens=max_tokens, json_mode=True)
    decoded1 = safe_json_load(raw1)
    slides = normalize_slides(decoded1, n)

    if slides is None:
        retry_prompt = build_retry_prompt(topic, n)
        raw2 = groq_chat(retry_prompt, model=model, max_tokens=max_tokens + 1200, json_mode=True)
        decoded2 = safe_json_load(raw2)
        slides = normalize_slides(decoded2, n)

        if slides is None:
            raise HTTPException(status_code=500, detail="Failed to generate slides for PDF")

    pdf_bytes = build_pdf(topic, slides)
    filename = f"SprintSlidesAI_{topic.replace(' ', '_')}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
