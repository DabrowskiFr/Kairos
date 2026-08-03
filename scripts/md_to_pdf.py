#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["reportlab>=4,<5"]
# ///

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

import reportlab
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    XPreformatted,
)


REPORTLAB_FONTS = Path(reportlab.__file__).parent / "fonts"


def available_font(*candidates: str) -> str:
    for candidate in candidates:
        if Path(candidate).is_file():
            return candidate
    raise RuntimeError(f"none of these fonts is installed: {', '.join(candidates)}")


pdfmetrics.registerFont(TTFont("DocSans", available_font(
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    str(REPORTLAB_FONTS / "Vera.ttf"),
)))
pdfmetrics.registerFont(TTFont("DocSans-Bold", available_font(
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    str(REPORTLAB_FONTS / "VeraBd.ttf"),
)))
pdfmetrics.registerFont(TTFont("DocSans-Italic", available_font(
    "/System/Library/Fonts/Supplemental/Arial Italic.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf",
    str(REPORTLAB_FONTS / "VeraIt.ttf"),
)))
pdfmetrics.registerFont(TTFont("DocMono", available_font(
    "/System/Library/Fonts/Supplemental/Andale Mono.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    str(REPORTLAB_FONTS / "VeraMono.ttf"),
)))
pdfmetrics.registerFontFamily(
    "DocSans", normal="DocSans", bold="DocSans-Bold", italic="DocSans-Italic"
)


def inline_markup(text: str) -> str:
    placeholders: list[str] = []

    def stash(value: str) -> str:
        placeholders.append(value)
        return f"\x00{len(placeholders) - 1}\x00"

    text = re.sub(
        r"`([^`]+)`",
        lambda m: stash(f'<font name="DocMono" size="7.4">{html.escape(m.group(1))}</font>'),
        text,
    )
    text = html.escape(text)
    def render_link(match):
        label, target = match.group(1), html.unescape(match.group(2))
        if target.startswith("#"):
            return f'<font color="#24557a">{label}</font>'
        return f'<link href="{html.escape(target, quote=True)}" color="#24557a">{label}</link>'

    text = re.sub(r"\[([^]]+)\]\(([^)]+)\)", render_link, text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", text)
    for index, value in enumerate(placeholders):
        text = text.replace(f"\x00{index}\x00", value)
    return text


def make_styles():
    styles = getSampleStyleSheet()
    body = ParagraphStyle(
        "Body",
        parent=styles["BodyText"],
        fontName="DocSans",
        fontSize=7.9,
        leading=9.55,
        spaceAfter=2.1,
        textColor=colors.HexColor("#202428"),
        allowWidows=0,
        allowOrphans=0,
    )
    return {
        "body": body,
        "title": ParagraphStyle(
            "Title", parent=body, fontName="DocSans-Bold", fontSize=17,
            leading=19, alignment=TA_CENTER, spaceAfter=7, textColor=colors.HexColor("#17344d")
        ),
        "h2": ParagraphStyle(
            "H2", parent=body, fontName="DocSans-Bold", fontSize=11.5,
            leading=13.2, spaceBefore=5.5, spaceAfter=2.5, keepWithNext=True,
            textColor=colors.HexColor("#17344d")
        ),
        "h3": ParagraphStyle(
            "H3", parent=body, fontName="DocSans-Bold", fontSize=9.2,
            leading=10.8, spaceBefore=4, spaceAfter=1.7, keepWithNext=True,
            textColor=colors.HexColor("#31566f")
        ),
        "bullet": ParagraphStyle(
            "Bullet", parent=body, leftIndent=10, firstLineIndent=-6,
            bulletIndent=2, spaceAfter=1.2
        ),
        "number": ParagraphStyle(
            "Number", parent=body, leftIndent=13, firstLineIndent=-9,
            spaceAfter=1.2
        ),
        "code": ParagraphStyle(
            "Code", parent=body, fontName="DocMono", fontSize=6.7,
            leading=8.2, leftIndent=5, rightIndent=4, spaceBefore=2,
            spaceAfter=4, backColor=colors.HexColor("#f1f3f5"),
            borderPadding=4, borderColor=colors.HexColor("#d5dade"), borderWidth=0.4
        ),
        "table": ParagraphStyle(
            "Table", parent=body, fontSize=6.7, leading=8.0, spaceAfter=0
        ),
        "table_head": ParagraphStyle(
            "TableHead", parent=body, fontName="DocSans-Bold", fontSize=6.8,
            leading=8.1, textColor=colors.white, spaceAfter=0
        ),
    }


def paragraph(text: str, style):
    return Paragraph(inline_markup(text.strip()), style)


def markdown_story(source: Path):
    styles = make_styles()
    lines = source.read_text(encoding="utf-8").splitlines()
    story = []
    i = 0
    pending: list[str] = []

    def flush():
        if pending:
            story.append(paragraph(" ".join(x.strip() for x in pending), styles["body"]))
            pending.clear()

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            flush()
            language = line[3:].strip()
            code = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                code.append(lines[i])
                i += 1
            label = f"[{language}]\n" if language and language != "text" else ""
            story.append(XPreformatted(label + "\n".join(code), styles["code"]))
        elif re.match(r"^#{1,3} ", line):
            flush()
            marks, title = line.split(" ", 1)
            key = "title" if len(marks) == 1 else "h2" if len(marks) == 2 else "h3"
            item = paragraph(title, styles[key])
            story.append(item)
        elif line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|?\s*:?-{3,}", lines[i + 1]):
            flush()
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                rows.append(cells)
                i += 1
            i -= 1
            if len(rows) >= 2:
                rows.pop(1)
            width = A4[0] - 30 * mm
            columns = max(len(row) for row in rows)
            data = []
            for ridx, row in enumerate(rows):
                row += [""] * (columns - len(row))
                style = styles["table_head"] if ridx == 0 else styles["table"]
                data.append([paragraph(cell, style) for cell in row])
            table = Table(data, colWidths=[width / columns] * columns, repeatRows=1, hAlign="LEFT")
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#31566f")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#b8c1c8")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f5f7f8")]),
                ("LEFTPADDING", (0, 0), (-1, -1), 3),
                ("RIGHTPADDING", (0, 0), (-1, -1), 3),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
            ]))
            story.extend([table, Spacer(1, 3)])
        elif re.match(r"^\s*- ", line):
            flush()
            text = re.sub(r"^\s*- ", "", line)
            story.append(Paragraph(inline_markup(text), styles["bullet"], bulletText="•"))
        elif re.match(r"^\s*\d+\. ", line):
            flush()
            match = re.match(r"^\s*(\d+)\. (.*)", line)
            story.append(Paragraph(f'<b>{match.group(1)}.</b> {inline_markup(match.group(2))}', styles["number"]))
        elif not line.strip():
            flush()
        else:
            pending.append(line)
        i += 1
    flush()
    return story


def build(source: Path, destination: Path):
    title = source.stem.replace("_", " ").title()
    left = right = 15 * mm
    top = 12 * mm
    bottom = 13 * mm
    doc = BaseDocTemplate(
        str(destination), pagesize=A4, leftMargin=left, rightMargin=right,
        topMargin=top, bottomMargin=bottom, title=title, author="Kairos contributors",
        subject="Kairos project documentation", pageCompression=1
    )
    frame = Frame(left, bottom, A4[0] - left - right, A4[1] - top - bottom, id="main")

    def decorate(canvas, current_doc):
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor("#c7cdd1"))
        canvas.setLineWidth(0.35)
        canvas.line(left, 10 * mm, A4[0] - right, 10 * mm)
        canvas.setFont("DocSans", 6.7)
        canvas.setFillColor(colors.HexColor("#66717a"))
        canvas.drawString(left, 6.5 * mm, source.name)
        canvas.drawRightString(A4[0] - right, 6.5 * mm, f"Page {current_doc.page}")
        canvas.restoreState()

    doc.addPageTemplates([PageTemplate(id="compact", frames=[frame], onPage=decorate)])
    doc.build(markdown_story(source))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: md_to_pdf.py SOURCE.md DESTINATION.pdf")
    build(Path(sys.argv[1]), Path(sys.argv[2]))
