#!/usr/bin/env python3
"""Render the seven-page, source-linked YouTube design proposal.

Run with a Python environment that provides reportlab and pypdf.
Content and references are kept separately in docs/design/youtube-source-design.json.
"""
from __future__ import annotations

import argparse
import html
import json
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Flowable, Frame, PageBreak,
    PageTemplate, Paragraph, Spacer, Table, TableStyle,
)
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / "docs/design/youtube-source-design.json"
DEFAULT_OUTPUT = ROOT / "output/pdf/KidsJellyFin-YouTube-Source-Design.pdf"
FONT_DIR = Path("/System/Library/Fonts/Supplemental")
INK = colors.HexColor("#182A3B")
MUTED = colors.HexColor("#536574")
BLUE = colors.HexColor("#075A83")
TEAL = colors.HexColor("#137A73")
PALE = colors.HexColor("#EEF6F7")
LIGHT = colors.HexColor("#F3F6F9")
LINE = colors.HexColor("#D6E1E8")
WHITE = colors.white
PAGE_W, PAGE_H = 612, 792
MARGIN = 42
WIDTH = PAGE_W - 2 * MARGIN


def register_fonts():
    for name, filename in (
        ("DocArial", "Arial.ttf"),
        ("DocArial-Bold", "Arial Bold.ttf"),
        ("DocArial-Italic", "Arial Italic.ttf"),
        ("DocArial-BoldItalic", "Arial Bold Italic.ttf"),
    ):
        path = FONT_DIR / filename
        if not path.exists():
            raise FileNotFoundError(f"Required embedded font: {path}")
        pdfmetrics.registerFont(TTFont(name, str(path)))
    pdfmetrics.registerFontFamily(
        "DocArial", normal="DocArial", bold="DocArial-Bold",
        italic="DocArial-Italic", boldItalic="DocArial-BoldItalic",
    )


def make_styles():
    def style(name, size, leading, **kwargs):
        options = dict(fontName="DocArial", fontSize=size, leading=leading,
                       textColor=INK, alignment=TA_LEFT)
        options.update(kwargs)
        return ParagraphStyle(name, **options)
    return {
        "title": style("Title", 25, 28.5, fontName="DocArial-Bold", spaceAfter=9),
        "dek": style("Deck", 11.5, 15.5, textColor=MUTED, spaceAfter=15),
        "h2": style("Heading", 12.2, 15, fontName="DocArial-Bold", spaceBefore=10, spaceAfter=6, keepWithNext=True),
        "body": style("Body", 10.25, 14.0, spaceAfter=7),
        "label": style("Labeled", 10.25, 14.0, spaceAfter=7),
        "callout": style("Callout", 10.35, 14.2),
        "callout_label": style("CalloutLabel", 10, 12.8, fontName="DocArial-Bold", textColor=TEAL, spaceAfter=4),
        "cell": style("TableCell", 9.6, 12.7),
        "cell_label": style("TableLabel", 9.6, 12.7, fontName="DocArial-Bold"),
        "cell_header": style("TableHeader", 9.4, 12.2, fontName="DocArial-Bold", textColor=WHITE),
        "note": style("Note", 8.7, 11.8, textColor=MUTED, spaceBefore=6, spaceAfter=2),
        "reference": style("Reference", 8.5, 11.1, textColor=MUTED, spaceAfter=4),
    }


class ApprovalFlow(Flowable):
    def __init__(self, items, captions):
        super().__init__()
        self.items = items
        self.captions = captions
        self.width = WIDTH
        self.height = 63

    def draw(self):
        c = self.canv
        gap = 16
        box_w = (self.width - 3 * gap) / 4
        for i, (label, caption) in enumerate(zip(self.items, self.captions)):
            x = i * (box_w + gap)
            c.setFillColor(PALE if i == 2 else LIGHT)
            c.setStrokeColor(LINE)
            c.roundRect(x, 16, box_w, 44, 6, stroke=1, fill=1)
            c.setFont("DocArial-Bold", 9.4)
            c.setFillColor(INK)
            c.drawCentredString(x + box_w / 2, 42, label)
            c.setFont("DocArial", 8.5)
            c.setFillColor(MUTED)
            c.drawCentredString(x + box_w / 2, 27, caption)
            if i < 3:
                ax = x + box_w + 4
                c.setStrokeColor(TEAL)
                c.setLineWidth(1.3)
                c.line(ax, 38, ax + 8, 38)
                c.line(ax + 8, 38, ax + 5, 41)
                c.line(ax + 8, 38, ax + 5, 35)


class NavigationSketch(Flowable):
    def __init__(self):
        super().__init__()
        self.width = WIDTH
        self.height = 88

    def draw(self):
        c = self.canv
        c.setFillColor(LIGHT)
        c.setStrokeColor(LINE)
        c.roundRect(0, 9, WIDTH, 77, 6, stroke=1, fill=1)
        c.setFont("DocArial-Bold", 9.7)
        c.setFillColor(INK)
        c.drawString(13, 66, "Separate-category trial")
        labels = [("Shows", 119), ("Movies", 188), ("YouTube", 260), ("Parents", 346)]
        for text, x in labels:
            c.setFillColor(TEAL if text == "YouTube" else WHITE)
            c.setStrokeColor(TEAL if text == "YouTube" else LINE)
            c.roundRect(x, 54, 65, 23, 4, stroke=1, fill=1)
            c.setFillColor(WHITE if text == "YouTube" else INK)
            c.setFont("DocArial-Bold", 9)
            c.drawCentredString(x + 32.5, 62, text)
        c.setFont("DocArial", 9.3)
        c.setFillColor(MUTED)
        c.drawString(13, 30, "Approved artwork")
        c.setFont("DocArial-Bold", 10)
        c.setFillColor(INK)
        c.drawString(119, 30, "Little Bear")
        for text, x in [("Next", 260), ("Shuffle", 346)]:
            c.setFillColor(WHITE)
            c.setStrokeColor(LINE)
            c.roundRect(x, 22, 65, 23, 4, stroke=1, fill=1)
            c.setFillColor(INK)
            c.setFont("DocArial-Bold", 9)
            c.drawCentredString(x + 32.5, 30, text)
        c.setFillColor(MUTED)
        c.setFont("DocArial", 7.8)
        c.drawRightString(WIDTH - 13, 15, "Diagram labels stand in for artwork and child-friendly icons")


def render(source: Path, output: Path):
    content = json.loads(source.read_text())
    if len(content["pages"]) != 7:
        raise ValueError("The review document must have exactly seven authored pages")
    serialized = json.dumps(content, ensure_ascii=False)
    forbidden = [char for char in ("\u2010", "\u2011", "\u2012", "\u2013", "\u2014", "\u2212") if char in serialized]
    if forbidden:
        raise ValueError("Use ASCII hyphens in document source")
    register_fonts()
    styles = make_styles()
    source_map = {entry["id"]: entry for entry in content["sources"]}

    def markup(text):
        # Source supports only intentional ReportLab b/i markup. References link to primary pages.
        escaped = html.escape(text)
        for tag in ("b", "i"):
            escaped = escaped.replace(f"&lt;{tag}&gt;", f"<{tag}>")
            escaped = escaped.replace(f"&lt;/{tag}&gt;", f"</{tag}>")
        def citations(match):
            ids = [part.strip() for part in match.group(1).split(",")]
            return "[" + ", ".join(
                f'<link href="{html.escape(source_map[ref]["url"], quote=True)}" color="#075A83">{ref}</link>'
                for ref in ids
            ) + "]"
        return re.sub(r"\[((?:S\d+)(?:,\s*S\d+)*)\]", citations, escaped)

    def p(text, style="body"):
        return Paragraph(markup(text), styles[style])

    def block_flowables(block):
        kind = block["type"]
        if kind == "heading":
            return [p(block["text"], "h2")]
        if kind in ("paragraph", "note"):
            return [p(block["text"], "body" if kind == "paragraph" else "note")]
        if kind == "labeled":
            return [p(f'<b>{block["label"]}.</b> {block["text"]}', "label")]
        if kind == "callout":
            paras = [p(block["label"].upper(), "callout_label"), p(block["text"], "callout")]
            table = Table([[paras]], colWidths=[WIDTH], hAlign="LEFT")
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), PALE),
                ("BOX", (0, 0), (-1, -1), 0.65, LINE),
                ("LINEBEFORE", (0, 0), (0, -1), 3, TEAL),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
            ]))
            return [Spacer(1, 5), table, Spacer(1, 8)]
        if kind == "table":
            data = [[p(text, "cell_header") for text in block["headers"]]]
            for row in block["rows"]:
                data.append([p(text, "cell_label" if i == 0 else "cell") for i, text in enumerate(row)])
            table = Table(data, colWidths=[WIDTH * part for part in block["widths"]], hAlign="LEFT", repeatRows=1)
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), BLUE),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [LIGHT, WHITE]),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LINEBELOW", (0, 1), (-1, -1), 0.4, LINE),
                ("LEFTPADDING", (0, 0), (-1, -1), 9),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]))
            return [table, Spacer(1, 6)]
        if kind == "flow":
            return [ApprovalFlow(block["items"], block["captions"])]
        if kind == "navigation":
            return [NavigationSketch()]
        if kind == "references":
            entries = content["sources"]
            midpoint = (len(entries) + 1) // 2
            cols = []
            for subset in (entries[:midpoint], entries[midpoint:]):
                col = []
                for entry in subset:
                    url = html.escape(entry["url"], quote=True)
                    title = html.escape(entry["title"])
                    text = f'<link href="{url}" color="#075A83"><b>[{entry["id"]}]</b> {title}</link>'
                    col.append(Paragraph(text, styles["reference"]))
                cols.append(col)
            table = Table([cols], colWidths=[WIDTH / 2, WIDTH / 2], hAlign="LEFT")
            table.setStyle(TableStyle([
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 14),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]))
            return [table]
        raise ValueError(f"Unknown block: {kind}")

    def furniture(canvas, doc):
        authored = content["pages"][min(doc.page - 1, 6)]
        canvas.saveState()
        canvas.setStrokeColor(LINE)
        canvas.setLineWidth(0.6)
        canvas.line(MARGIN, 752, PAGE_W - MARGIN, 752)
        canvas.setFont("DocArial-Bold", 8.5)
        canvas.setFillColor(TEAL)
        canvas.drawString(MARGIN, 765, "KIDSJELLYFIN  /  " + authored["eyebrow"])
        canvas.setFont("DocArial", 8.5)
        canvas.setFillColor(MUTED)
        canvas.drawRightString(PAGE_W - MARGIN, 765, content["date"])
        canvas.line(MARGIN, 38, PAGE_W - MARGIN, 38)
        canvas.setFont("DocArial", 8)
        canvas.drawString(MARGIN, 24, "RESEARCH + DESIGN  |  Proposed behavior unless identified as verified")
        canvas.setFont("DocArial-Bold", 8)
        canvas.drawRightString(PAGE_W - MARGIN, 24, f"{doc.page} / 7")
        canvas.restoreState()

    output.parent.mkdir(parents=True, exist_ok=True)
    doc = BaseDocTemplate(
        str(output), pagesize=(PAGE_W, PAGE_H),
        title=content["title"] + " - KidsJellyFin",
        author="KidsJellyFin Product and Engineering",
        subject="Parent-approved YouTube source: research, alternatives, system design and acceptance gates",
        leftMargin=MARGIN, rightMargin=MARGIN, topMargin=53, bottomMargin=49,
        pageCompression=1,
    )
    frame = Frame(MARGIN, 49, WIDTH, 690, leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0, id="body")
    doc.addPageTemplates(PageTemplate(id="Review", frames=[frame], onPage=furniture))
    story = []
    page_heights = []
    for index, page in enumerate(content["pages"]):
        flowables = [p(page["title"], "title"), p(page["dek"], "dek")]
        for block in page["blocks"]:
            flowables.extend(block_flowables(block))
        height = sum(item.wrap(WIDTH, 1000)[1] + item.getSpaceBefore() + item.getSpaceAfter() for item in flowables)
        page_heights.append(round(height, 1))
        story.extend(flowables)
        if index < len(content["pages"]) - 1:
            story.append(PageBreak())
    doc.build(story)
    reader = PdfReader(str(output))
    if len(reader.pages) != 7:
        raise RuntimeError(f"Expected seven pages, rendered {len(reader.pages)}; measured page heights: {page_heights}")
    for page, expected in zip(reader.pages, content["pages"]):
        if expected["title"] not in page.extract_text():
            raise RuntimeError(f'Page {expected["number"]} content flowed onto another page')
    print(json.dumps({
        "output": str(output), "pages": len(reader.pages),
        "estimated_authored_heights_pt": page_heights,
        "source_references": len(source_map),
        "external_links": sum(len(page.get("/Annots", [])) for page in reader.pages),
    }, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    render(args.source, args.output)
