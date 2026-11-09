#!/usr/bin/env python3
"""Build slides/esch384_design.pptx (black and white, one sans-serif font).

Run:  source scripts/env.sh && python slides/build_slides.py
Diagrams are drawn with graphviz into slides/img/.
Slides not yet done show "Coming in Phase N".
"""
import os
import subprocess
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "img")
OUT = os.path.join(HERE, "esch384_design.pptx")
FONT = "Arial"
BLACK = RGBColor(0, 0, 0)

# ---------------- diagrams (graphviz, black and white) ----------------

GV_STYLE = ('graph [bgcolor=white fontname="Arial" nodesep=0.25 ranksep=0.3];'
            'node [fontname="Arial" color=black fontcolor=black shape=box];'
            'edge [color=black fontname="Arial"];')

SPONGE = """digraph G { rankdir=LR; %s
  s0 [label="S = 0\\n512 bits"];
  i0 [label="inject\\nP0" shape=circle];
  p0 [label="SPARKLE512\\nslim (8)"];
  dots [label="..." shape=plaintext];
  il [label="inject last\\nblock + ConstM" shape=circle];
  pb [label="SPARKLE512\\nbig (12)"];
  d0 [label="D0" shape=plaintext];
  q1 [label="SPARKLE512\\nslim (8)"];
  d1 [label="D1" shape=plaintext];
  q2 [label="SPARKLE512\\nslim (8)"];
  d2 [label="D2" shape=plaintext];
  s0 -> i0 -> p0 -> dots -> il -> pb -> q1 -> q2;
  pb -> d0 [style=dashed]; q1 -> d1 [style=dashed]; q2 -> d2 [style=dashed];
}""" % GV_STYLE

STEP = """digraph G { rankdir=TB; ordering=out; %s
  c [label="y0 ^= c[s mod 8],  y1 ^= s"];
  { rank=same; a0 [label="A c0"]; a1 [label="A c1"]; a2 [label="... 8 in parallel ..." shape=plaintext]; a7 [label="A c7"]; }
  l [label="Linear layer L8\\n(Feistel + branch swap)"];
  c -> a0; c -> a1; c -> a2 [arrowhead=none style=invis]; c -> a7;
  a0 -> l; a1 -> l; a7 -> l;
}""" % GV_STYLE

ALZETTE = """digraph G { rankdir=TB; %s
  node [shape=box width=2.6];
  r1 [label="x += y>>>31;  y ^= x>>>24;  x ^= c"];
  r2 [label="x += y>>>17;  y ^= x>>>17;  x ^= c"];
  r3 [label="x += y;       y ^= x>>>31;  x ^= c"];
  r4 [label="x += y>>>24;  y ^= x>>>16;  x ^= c"];
  in [label="(x, y)" shape=plaintext]; out [label="(u, v)" shape=plaintext];
  in -> r1 -> r2 -> r3 -> r4 -> out;
}""" % GV_STYLE

VERIF = """digraph G { rankdir=LR; %s
  spec [label="Spec PDF\\n(pseudocode)"];
  c [label="Official C code"];
  py [label="Python model\\n(from spec)"];
  kat [label="Official KAT\\n1025 messages"];
  vec [label="Unit vectors\\nAlzette, L8, SPARKLE"];
  dbg [label="Debug trace\\nstate per step"];
  hw [label="RTL testbench\\n(xsim)"];
  c -> kat [label="match"]; spec -> py; py -> vec [label="check"];
  c -> vec; c -> dbg; kat -> hw; vec -> hw; dbg -> hw [label="first\\ndifference"];
}""" % GV_STYLE


def render(name, src):
    os.makedirs(IMG, exist_ok=True)
    path = os.path.join(IMG, name + ".png")
    subprocess.run(["dot", "-Tpng", "-Gdpi=200", "-o", path],
                   input=src.encode(), check=True)
    return path

# ---------------- slide helpers ----------------

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
BLANK = prs.slide_layouts[6]


def text(slide, s, left, top, width, height, size=20, bold=False):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    for i, line in enumerate(s.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = line
        p.font.name, p.font.size, p.font.bold = FONT, Pt(size), bold
        p.font.color.rgb = BLACK
    return tb


def slide(title, bullets=None, image=None, img_left=None, img_width=None):
    s = prs.slides.add_slide(BLANK)
    s.background.fill.solid()
    s.background.fill.fore_color.rgb = RGBColor(255, 255, 255)
    text(s, title, Inches(0.6), Inches(0.4), Inches(12), Inches(0.9), 34, True)
    line = s.shapes.add_connector(1, Inches(0.6), Inches(1.3), Inches(12.7), Inches(1.3))
    line.line.color.rgb = BLACK
    if bullets:
        w = Inches(5.6) if image else Inches(12)
        text(s, "\n".join("- " + b for b in bullets),
             Inches(0.6), Inches(1.6), w, Inches(5.5), 20)
    if image:
        left = img_left if img_left is not None else (Inches(6.4) if bullets else Inches(0.8))
        width = img_width if img_width is not None else (Inches(6.4) if bullets else Inches(11.7))
        s.shapes.add_picture(image, left, Inches(1.7), width=width)
    return s


def todo(title, phase):
    slide(title, [f"Coming in Phase {phase}"])

# ---------------- slides ----------------

s = prs.slides.add_slide(BLANK)
text(s, "Esch384 on FPGA", Inches(0.8), Inches(2.4), Inches(11.7), Inches(1.2), 48, True)
text(s, "A hardware implementation of the SPARKLE hash\nHenry Su, Nick Ngo\nECE 545, NC State University",
     Inches(0.8), Inches(3.8), Inches(11.7), Inches(2), 24)

slide("Esch384 overview",
      ["Hash from the SPARKLE family (NIST lightweight crypto finalist)",
       "Sponge: absorb 128-bit blocks, then squeeze",
       "State 512 bits, rate 128, capacity 384",
       "Digest 384 bits (3 squeezes of 128)",
       "Slim permutation: 8 steps; big (after last block): 12 steps",
       "Last block padded with 10*; constant marks padded vs. full"],
      render("sponge", SPONGE), img_left=Inches(0.6), img_width=Inches(12.1))
# put bullets under the wide sponge picture
sp = prs.slides[-1].shapes
pic, box = sp[-1], sp[-2]
pic.top = Inches(1.5)
box.top, box.width = Inches(1.5) + pic.height + Inches(0.2), Inches(12)
box.height = Inches(3.6)

s3 = slide("SPARKLE512 and the Alzette ARX-box",
           ["One step = constant, 8 Alzettes, linear layer",
            "Alzette: 4 rounds of add, rotate, XOR (ARX)",
            "Each branch has its own constant c_i",
            "Linear layer mixes the 8 branches"],
           render("step", STEP), img_left=Inches(5.0), img_width=Inches(4.2))
s3.shapes.add_picture(render("alzette", ALZETTE), Inches(9.4), Inches(1.9), width=Inches(3.6))

todo("Top-level block diagram", 3)
todo("Datapath", 3)
todo("Controller FSM", 3)
todo("Timing and latency", 3)

slide("Verification approach",
      ["Official C code reproduces all 1025 official KATs",
       "Extra KATs at block edges: 0, 1, 15, 16, 17, 32, 33 ... bytes",
       "Unit vectors double-checked by a Python model written from the spec",
       "Debug trace prints the state after every step",
       "Hardware mismatch: compare traces, fix the first difference"],
      render("verif", VERIF))

todo("Synthesis results", 3)
todo("Area optimizations", 4)
slide("AI tool usage and lessons learned",
      ["Claude Code used for setup, reference model, test vectors",
       "Every AI output checked by running tests",
       "Full log: docs/ai_log.md"])
todo("Conclusion", 4)

prs.save(OUT)
print("wrote", OUT, "-", len(prs.slides), "slides")
