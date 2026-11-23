from pathlib import Path
import re
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle, PageBreak
from reportlab.platypus import Image
from PIL import Image as PILImage, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
OUTPUT = ROOT / "output" / "pdf"
OUTPUT.mkdir(parents=True, exist_ok=True)
ASSETS = DOCS / "assets"

def make_diagrams():
    ASSETS.mkdir(exist_ok=True)
    font = ImageFont.truetype("arial.ttf", 16)
    title_font = ImageFont.truetype("arialbd.ttf", 20)
    def make(name, title, boxes, arrows):
        image = PILImage.new("RGB", (1280, 360), "#f7f8fa")
        draw = ImageDraw.Draw(image)
        draw.text((640, 24), title, anchor="mt", font=title_font, fill="#172235")
        for x, y, width, height, label, color in boxes:
            draw.rounded_rectangle((x, y, x + width, y + height), 14, fill=color, outline="#31445e", width=2)
            draw.text((x + width / 2, y + height / 2), label, anchor="mm", font=font, fill="white")
        for x1, y1, x2, y2 in arrows:
            draw.line((x1, y1, x2, y2), fill="#ff5146", width=5)
            draw.polygon([(x2, y2), (x2 - 18, y2 - 9), (x2 - 18, y2 + 9)], fill="#ff5146")
        image.save(ASSETS / name)
    make("forge-request-flow.png", "Normal request flow - local isolated lab", [(48,145,260,92,"Learner browser","#172235"),(510,145,260,92,"Flask routes","#172235"),(972,145,260,92,"PostgreSQL","#172235")], [(308,191,495,191),(770,191,957,191)])
    make("union-reasoning.png", "Column count and compatible types must match", [(42,145,300,92,"Normal 6 columns","#172235"),(490,145,300,92,"UNION: 6 values","#7a342f"),(938,145,300,92,"Rendered build row","#172235")], [(342,191,475,191),(790,191,923,191)])
    make("telemetry-oracle.png", "Boolean telemetry oracle - no timing required", [(42,145,300,92,"Prefix condition","#172235"),(490,145,300,92,"DB evaluates","#7a342f"),(938,75,300,72,"TRUE -> HTTP 200","#21633f"),(938,220,300,72,"FALSE -> HTTP 404","#5d2b2b")], [(342,191,475,191),(790,191,923,111),(790,191,923,256)])

def clean(value: str) -> str:
    value = value.replace("→", "->").replace("·", "-").replace("≤", "<=").replace("—", "-").replace("–", "-")
    return value.encode("ascii", "replace").decode("ascii")

def inline(value: str) -> str:
    value = clean(value.strip())
    value = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    value = re.sub(r"`([^`]+)`", r'<font name="Courier">\1</font>', value)
    value = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", value)
    return value

def make_pdf(source: Path) -> Path:
    target = OUTPUT / f"{source.stem}.pdf"
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(name="DocTitle", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=22, leading=27, textColor=colors.HexColor("#172235"), spaceAfter=12))
    styles.add(ParagraphStyle(name="H1Custom", parent=styles["Heading1"], fontName="Helvetica-Bold", fontSize=15, leading=20, textColor=colors.HexColor("#b8302b"), spaceBefore=13, spaceAfter=7))
    styles.add(ParagraphStyle(name="H2Custom", parent=styles["Heading2"], fontName="Helvetica-Bold", fontSize=12, leading=16, textColor=colors.HexColor("#172235"), spaceBefore=10, spaceAfter=5))
    styles.add(ParagraphStyle(name="BodyCustom", parent=styles["BodyText"], fontName="Helvetica", fontSize=9.5, leading=14, spaceAfter=6, alignment=TA_LEFT))
    styles.add(ParagraphStyle(name="CodeCustom", parent=styles["BodyText"], fontName="Courier", fontSize=8.2, leading=11, backColor=colors.HexColor("#eef1f5"), borderColor=colors.HexColor("#d3d9e1"), borderWidth=0.5, borderPadding=6, spaceAfter=8))
    story = []
    code_lines = []
    in_code = False
    table_lines = []

    def flush_code():
        nonlocal code_lines
        if code_lines:
            story.append(Paragraph("<br/>".join(inline(x) for x in code_lines), styles["CodeCustom"]))
            code_lines = []

    def flush_table():
        nonlocal table_lines
        if len(table_lines) >= 2:
            parsed = [[clean(re.sub(r"`([^`]+)`", r"\1", cell.strip())) for cell in row.strip().strip("|").split("|")] for row in table_lines if not re.match(r"^\s*\|?\s*[-:]+", row)]
            if parsed:
                table = Table(parsed, repeatRows=1, hAlign="LEFT")
                table.setStyle(TableStyle([
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#172235")),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
                    ("FONTSIZE", (0, 0), (-1, -1), 8.5),
                    ("LEADING", (0, 0), (-1, -1), 11),
                    ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#cbd2dc")),
                    ("BACKGROUND", (0, 1), (-1, -1), colors.HexColor("#f7f8fa")),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                    ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ]))
                story.extend([table, Spacer(1, 8)])
        table_lines = []

    for raw in source.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if line.startswith("```"):
            if in_code: flush_code()
            in_code = not in_code
            continue
        if in_code:
            code_lines.append(line)
            continue
        if line.lstrip().startswith("|"):
            table_lines.append(line)
            continue
        flush_table()
        if not line.strip():
            story.append(Spacer(1, 4)); continue
        image_match = re.match(r"!\[[^]]*\]\(([^)]+)\)", line)
        if image_match:
            image_path = DOCS / image_match.group(1)
            if image_path.exists():
                story.extend([Image(str(image_path), width=160*mm, height=45*mm), Spacer(1, 7)])
            continue
        if line.startswith("# "):
            story.append(Paragraph(inline(line[2:]), styles["DocTitle"])); continue
        if line.startswith("## "):
            if line[3:].strip() == "Flag summary": story.append(PageBreak())
            story.append(Paragraph(inline(line[3:]), styles["H1Custom"])); continue
        if line.startswith("### "):
            story.append(Paragraph(inline(line[4:]), styles["H2Custom"])); continue
        if line.startswith("> "):
            story.append(Paragraph("<b>Note:</b> " + inline(line[2:]), styles["CodeCustom"])); continue
        if re.match(r"^\d+\. ", line):
            story.append(Paragraph(inline(line), styles["BodyCustom"])); continue
        if line.startswith("- "):
            story.append(Paragraph("- " + inline(line[2:]), styles["BodyCustom"])); continue
        story.append(Paragraph(inline(line), styles["BodyCustom"]))
    flush_code(); flush_table()

    doc = SimpleDocTemplate(str(target), pagesize=A4, rightMargin=18*mm, leftMargin=18*mm, topMargin=17*mm, bottomMargin=17*mm, title=clean(source.stem.replace("-", " ").title()), author="Redline Forge Motorsport")
    doc.build(story)
    return target

if __name__ == "__main__":
    make_diagrams()
    for markdown in sorted(DOCS.glob("*.md")):
        print(make_pdf(markdown))
