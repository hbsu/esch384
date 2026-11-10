"""Builds slides/esch384_progress.pptx: one black-and-white progress slide
for the design-document presentation (ECE 545, 11/11).
Run: .venv/bin/python slides/make_progress_slide.py
"""
from pathlib import Path
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

BLACK = RGBColor(0, 0, 0)
WHITE = RGBColor(255, 255, 255)
FONT = "Arial"

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
s = prs.slides.add_slide(prs.slide_layouts[6])  # blank
s.background.fill.solid()
s.background.fill.fore_color.rgb = WHITE


def text(x, y, w, h, lines, size=16, bold_first=False, align=PP_ALIGN.LEFT):
    tb = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        bold = line.startswith("**")
        r = p.add_run()
        r.text = line.strip("*")
        r.font.name, r.font.size, r.font.color.rgb = FONT, Pt(size), BLACK
        r.font.bold = bold or (bold_first and i == 0)
        p.alignment = align
        p.space_after = Pt(4)
        if bold and i > 0:
            p.space_before = Pt(14)
    return tb


def box(x, y, w, h, label, size=14):
    b = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    b.fill.solid()
    b.fill.fore_color.rgb = WHITE
    b.line.color.rgb, b.line.width = BLACK, Pt(1.5)
    b.shadow.inherit = False
    tf = b.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    for i, line in enumerate(label.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.CENTER
        r = p.add_run()
        r.text = line
        r.font.name, r.font.size, r.font.color.rgb = FONT, Pt(size if i == 0 else size - 3), BLACK
        r.font.bold = i == 0
    return b


def seg(x1, y1, x2, y2):
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb, c.line.width = BLACK, Pt(1.5)
    return c


def arrow(x1, y1, x2, y2):
    c = seg(x1, y1, x2, y2)
    c.line._get_or_add_ln().append(
        c.line._get_or_add_ln().makeelement(
            "{http://schemas.openxmlformats.org/drawingml/2006/main}tailEnd", {"type": "triangle"}))


# Title
text(0.5, 0.3, 12.3, 0.7, ["Esch384 Hash on FPGA: Progress Report"], size=30, bold_first=True)
text(0.5, 0.95, 12.3, 0.4, ["Henry Su, Nick Ngo  |  ECE 545 Final Project  |  Design Document"], size=16)
line = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(0.5), Inches(1.45), Inches(12.83), Inches(1.45))
line.line.color.rgb, line.line.width = BLACK, Pt(1)

# Block diagram (left)
text(0.5, 1.65, 6.3, 0.4, ["**Design: iterative, one step per clock cycle"], size=16)
box(2.4, 2.2, 2.6, 0.75, "Controller\nstate machine")
box(0.5, 3.4, 1.4, 1.0, "Message\n16 B / block")
box(2.4, 3.3, 2.6, 1.2, "Datapath\n512-bit state, padding,\nmessage injection")
box(5.55, 3.4, 1.5, 1.0, "Digest\n48 B (3 × 16 B)")
box(2.4, 5.0, 2.6, 1.2, "SPARKLE512 step\n8 Alzette boxes\n+ linear layer")
arrow(1.9, 3.9, 2.4, 3.9)
arrow(5.0, 3.9, 5.55, 3.9)
arrow(3.7, 2.95, 3.7, 3.3)
arrow(3.3, 4.5, 3.3, 5.0)   # state into step
arrow(4.1, 5.0, 4.1, 4.5)   # result back
# controller also drives the step: step number (constant) and 8 or 12 steps
seg(5.0, 2.575, 5.28, 2.575)
seg(5.28, 2.575, 5.28, 5.6)
arrow(5.28, 5.6, 5.0, 5.6)
text(5.3, 4.95, 1.9, 0.6, ["step number,", "8 or 12 steps"], size=11)
text(0.5, 6.25, 6.6, 0.4, ["Arty A7 (Artix-7), Vivado 2026.1, Claude Code (AI, all use logged)"], size=12)

# Timeline band
line2 = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(0.5), Inches(6.72), Inches(12.83), Inches(6.72))
line2.line.color.rgb, line2.line.width = BLACK, Pt(1)
text(0.5, 6.8, 12.3, 0.5, ["**Plan:  Nov 17 datapath + controller  →  Nov 21 full hash  →  Nov 24 synthesis  →  Dec 1 area optimization  →  Dec 9 final presentation"], size=14)

# Right column
text(7.3, 1.65, 5.6, 5.0, [
    "**Goal: smallest area",
    "Serialize: 8 → 4 → 2 → 1 Alzette boxes",
    "Compare LUTs, flip-flops, clock speed, throughput",
    "**Progress (Henry: done; Nick: next)",
    "Done: reference model, all 1025 official tests",
    "Done: Alzette, linear layer, SPARKLE512",
    "     all unit tests pass; 2023 LUTs, 521 FFs",
    "Next: datapath, controller, full hash (Nick)",
    "**Risks and challenges",
    "Each block tested alone against official C code",
    "Unclear byte order → checked with C code",
], size=15)

out = Path(__file__).resolve().parent / "esch384_progress.pptx"
prs.save(out)
print("wrote", out)
