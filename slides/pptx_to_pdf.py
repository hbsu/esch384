"""Draws a simple one-slide .pptx (text boxes, rectangles, straight lines/arrows)
into a PDF with matplotlib, since LibreOffice is not available on Grendel.
Uses Liberation Sans (same letter widths as Arial).
Run: .venv/bin/python slides/pptx_to_pdf.py slides/esch384_progress.pptx
"""
import sys
from pathlib import Path
from pptx import Presentation
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
matplotlib.rcParams["pdf.fonttype"] = 42  # embed TrueType fonts

EMU = 914400  # per inch
FONT = "Liberation Sans"
INSET_X, INSET_Y = 0.1, 0.05  # pptx default text insets (inches)


def wrap(ax, text, size, bold, width_in):
    """Split text into lines that fit width_in inches."""
    fig = ax.figure
    rend = fig.canvas.get_renderer()

    def w(s):
        t = ax.text(0, 0, s, fontsize=size, family=FONT, weight="bold" if bold else "normal")
        bb = t.get_window_extent(rend)
        t.remove()
        return bb.width / fig.dpi

    lead = len(text) - len(text.lstrip(" "))
    words, lines, cur = text.split(), [], " " * lead
    for word in words:
        trial = (cur + " " + word) if cur.strip() else cur + word
        if w(trial) <= width_in or not cur.strip():
            cur = trial
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    return lines


def layout(ax, sh):
    """Return list of (line, size, bold, align, y_offset) and total height."""
    out, y = [], 0.0
    width = sh.width / EMU - 2 * INSET_X
    for i, p in enumerate(sh.text_frame.paragraphs):
        if not p.runs:
            continue
        r = p.runs[0]
        size, bold = r.font.size.pt, bool(r.font.bold)
        if i > 0 and p.space_before is not None:
            y += p.space_before.pt / 72
        for line in wrap(ax, p.text, size, bold, width):
            out.append((line, size, bold, p.alignment, y))
            y += size * 1.2 / 72
        if p.space_after is not None:
            y += p.space_after.pt / 72
    return out, y


def main(src):
    prs = Presentation(src)
    W, H = prs.slide_width / EMU, prs.slide_height / EMU
    pdf = Path(src).with_suffix(".pdf")
    fig = plt.figure(figsize=(W, H))
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(H, 0)
    ax.axis("off")
    for sh in prs.slides[0].shapes:
        x, y, w, h = (v / EMU for v in (sh.left, sh.top, sh.width, sh.height))
        if sh.shape_type == 9 or not sh.has_text_frame:  # straight connector
            bx, by, ex, ey = (v / EMU for v in (sh.begin_x, sh.begin_y, sh.end_x, sh.end_y))
            head = "tailEnd" in sh.line._get_or_add_ln().xml
            ax.annotate("", xy=(ex, ey), xytext=(bx, by),
                        arrowprops=dict(arrowstyle="-|>" if head else "-", color="black",
                                        lw=sh.line.width.pt, mutation_scale=14,
                                        shrinkA=0, shrinkB=0))
            continue
        is_box = sh.shape_type == 1  # autoshape rectangle
        if is_box:
            ax.add_patch(plt.Rectangle((x, y), w, h, fill=False, ec="black", lw=sh.line.width.pt))
        lines, total = layout(ax, sh)
        top = y + INSET_Y
        if is_box and sh.text_frame.vertical_anchor == MSO_ANCHOR.MIDDLE:
            top = y + (h - total) / 2
        for line, size, bold, align, dy in lines:
            center = align == PP_ALIGN.CENTER
            ax.text(x + w / 2 if center else x + INSET_X, top + dy, line, fontsize=size,
                    family=FONT, weight="bold" if bold else "normal",
                    ha="center" if center else "left", va="top", color="black")
    fig.savefig(pdf)
    print("wrote", pdf)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "slides/esch384_progress.pptx")
