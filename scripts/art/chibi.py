#!/usr/bin/env python3
"""Treatly's pets as tiny chibi pixel sprites, their wardrobe and the bowls.

Every pixel is placed by hand on a small grid (about 24 pixels wide): a big
head, a boxy body, stubby legs, flat colours with one shade, one-pixel eyes,
and a 1px dark outline added around the silhouette at the end.

Wardrobe items are drawn on overlay sheets with the same layout as the pet's
sheet, anchored to where the head is in each frame.

    python3 scripts/art/chibi.py            # writes Pets/*/sheet.png and wear-*.png
    python3 scripts/art/chibi.py --preview  # also writes build/chibi-preview.png
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from generate import ROOT, hex_rgba, sheet, upscale, write_png  # noqa: E402

W, H = 32, 26
G = 23  # bottom row of the feet; row 24 is outline, row 25 stays empty
KW, KH = 38, 30
KG = 27


class Grid:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.cells = [[None] * w for _ in range(h)]

    def px(self, points, role):
        for x, y in points:
            if 0 <= x < self.w and 0 <= y < self.h:
                self.cells[y][x] = role

    def rect(self, x0, y0, x1, y1, role, round_=0):
        """Inclusive rect; round_ cuts that many corner pixels."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if round_:
                    dx = min(x - x0, x1 - x)
                    dy = min(y - y0, y1 - y)
                    if dx + dy < round_:
                        continue
                self.px([(x, y)], role)

    def get(self, x, y):
        return self.cells[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def render(self, palette, outline):
        """Fills colours and adds a 1px outline around everything (4-neighbour)."""
        out = [[None] * self.w for _ in range(self.h)]
        line = hex_rgba(outline)
        for y in range(self.h):
            for x in range(self.w):
                role = self.cells[y][x]
                if role is not None:
                    out[y][x] = hex_rgba(palette.get(role, outline))
                elif any(self.get(x + dx, y + dy) is not None for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    out[y][x] = line
        return out


# ---------------------------------------------------------------- Breeds
#
# Roles: b base, s shade, w markings, m stripes/spots, e eye, i iris,
# n nose, p pink, c cheek blush, k open mouth.

DOGS = {
    "shiba": {
        "b": "#E8873A", "s": "#C26A28", "w": "#FFF4E2", "line": "#3A2112",
        "ears": "pointy", "tail": "curl", "marks": ["muzzle", "chest", "belly", "socks", "brows"],
    },
    "golden": {
        "b": "#E7B45C", "s": "#C48F3E", "w": "#F6D79A", "line": "#4A2E12",
        "ears": "floppy", "tail": "plume", "marks": ["muzzle"],
    },
    "chihuahua": {
        "b": "#D9A672", "s": "#B5824F", "w": "#F7E6CF", "line": "#3E2616",
        "ears": "big", "tail": "thin", "marks": ["muzzle", "chest"], "small": True,
    },
}

CATS = {
    "orange-tabby": {
        "b": "#F09A48", "s": "#CC7330", "w": "#FFE8CC", "m": "#C2601E", "i": "#7ACB5A", "line": "#40220E",
        "marks": ["muzzle", "chest", "stripes"],
    },
    "black-cat": {
        "b": "#34323F", "s": "#24222C", "w": "#34323F", "i": "#F2D04A", "line": "#0E0D12",
        "marks": [], "nose": "#C77B8E",
    },
}

COMMON = {"e": "#1E1410", "n": "#2A1A14", "p": "#F29BAE", "c": "#F7A7A0", "k": "#5A1E22"}


def palette_for(spec):
    pal = dict(COMMON)
    pal.update({k: v for k, v in spec.items() if isinstance(v, str) and len(k) == 1})
    if "nose" in spec:
        pal["n"] = spec["nose"]
    if spec.get("b", "").upper() in ("#34323F",):
        pal["e"] = "#0E0D12"
    return pal


# ---------------------------------------------------------------- Parts

def head(g, spec, cat, hx, hy, mouth=False, blink=False, look_up=False):
    """Head box is 10x9 from (hx, hy), facing right. Returns anchors."""
    marks = spec["marks"]
    # Ears first so the head covers their base.
    ears = "cat" if cat else spec["ears"]
    if ears in ("pointy", "cat"):
        for ex, role in ((hx + 1, "s"), (hx + 5, "b")):
            g.px([(ex + 1, hy - 3)], role)
            g.px([(ex, hy - 2), (ex + 1, hy - 2), (ex + 2, hy - 2)], role)
            g.px([(ex, hy - 1), (ex + 1, hy - 1), (ex + 2, hy - 1)], role)
        g.px([(hx + 6, hy - 1)], "p")
        if cat:
            g.px([(hx + 6, hy - 2)], "p")
    elif ears == "big":
        for ex, role in ((hx, "s"), (hx + 4, "b")):
            g.px([(ex, hy - 5)], role)
            g.px([(ex, hy - 4), (ex + 1, hy - 4)], role)
            g.px([(ex, hy - 3), (ex + 1, hy - 3), (ex + 2, hy - 3)], role)
            g.px([(ex + i, hy - 2) for i in range(4)], role)
            g.px([(ex + i, hy - 1) for i in range(4)], role)
        g.px([(hx + 5, hy - 3), (hx + 5, hy - 2), (hx + 6, hy - 2)], "p")

    g.rect(hx, hy, hx + 9, hy + 8, "b", round_=2 if cat else 1)
    if cat:
        g.rect(hx + 1, hy + 6, hx + 9, hy + 8, "b", round_=1)

    # Muzzle sticks out for dogs; cats have a flat face.
    if not cat:
        g.rect(hx + 10, hy + 4, hx + 11, hy + 7, "w" if "muzzle" in marks else "b", round_=1)
        g.px([(hx + 10, hy + 4)], "w" if "muzzle" in marks else "b")
    if "muzzle" in marks:
        g.rect(hx + 5, hy + 6, hx + 9 if cat else hx + 10, hy + 8, "w", round_=1)
        g.px([(hx + 7, hy + 5), (hx + 8, hy + 5), (hx + 9, hy + 5)] if not cat else [(hx + 8, hy + 5)], "w")
    if "brows" in marks:
        g.px([(hx + 6, hy + 2)], "w")
    if "stripes" in marks:
        g.px([(hx + 3, hy), (hx + 3, hy + 1), (hx + 5, hy), (hx + 5, hy + 1), (hx + 1, hy + 3), (hx + 1, hy + 4)], "m")
    if ears == "floppy":
        g.rect(hx + 2, hy + 1, hx + 4, hy + 6, "s", round_=1)
        g.px([(hx + 3, hy + 7)], "s")

    # Eye: two pixels tall, or a closed line.
    ex, ey = hx + 7, hy + 3
    if look_up:
        ey -= 1
    if blink:
        g.px([(ex - 1, ey + 1), (ex, ey + 1)], "e")
    elif cat:
        g.px([(ex, ey)], "i")
        g.px([(ex, ey + 1)], "e")
    else:
        g.px([(ex, ey), (ex, ey + 1)], "e")
    g.px([(ex - 1, ey + 3)], "c")

    if cat:
        g.px([(hx + 9, hy + 5)], "n")
        if mouth:
            g.px([(hx + 8, hy + 7), (hx + 9, hy + 7)], "k")
            g.px([(hx + 8, hy + 8)], "p")
    else:
        g.px([(hx + 11, hy + 4)], "n")
        if mouth:
            g.px([(hx + 9, hy + 7), (hx + 10, hy + 7), (hx + 11, hy + 7)], "k")
            g.px([(hx + 10, hy + 8)], "p")
    return {"head": (hx, hy, 10), "eye": (ex, ey), "neck": (hx + 1, hy + 8)}


def tail(g, spec, cat, bx, by, wag=0):
    """bx, by is where the tail meets the top of the back."""
    role = "b"
    if cat:
        tip = "m" if "stripes" in spec["marks"] else "b"
        g.px([(bx - 1, by + 1), (bx - 2, by), (bx - 3, by - 1), (bx - 3, by - 2), (bx - 3, by - 3)], role)
        g.px([(bx - 3 + wag, by - 4), (bx - 2 + wag, by - 5)], tip)
        return
    kind = spec["tail"]
    if kind == "curl":
        g.px([(bx - 2, by - 3), (bx - 1, by - 3), (bx - 3, by - 2), (bx, by - 2), (bx - 3, by - 1), (bx, by - 1),
              (bx - 2, by), (bx - 1, by), (bx, by)], role)
        g.px([(bx - 1, by - 1)], "w" if "muzzle" in spec["marks"] and spec["w"] != spec["b"] else role)
    elif kind == "plume":
        g.px([(bx - 1, by), (bx - 2, by), (bx - 2, by - 1), (bx - 3, by - 1), (bx - 3 - wag, by - 2), (bx - 4 - wag, by - 2),
              (bx - 4 - wag, by - 3), (bx - 3, by)], role)
        g.px([(bx - 4 - wag, by - 1)], "w")
    else:
        g.px([(bx - 1, by), (bx - 2, by - 1), (bx - 2, by - 2), (bx - 3 - wag, by - 3)], role)


def quad(spec, cat, pose="stand", step=0, bob=0, mouth=False, blink=False, tilt=0, paw=False, breathe=0):
    """A dog or cat in one pose. Returns (grid, anchors)."""
    g = Grid(W, H)
    marks = spec["marks"]
    small = spec.get("small", False)
    sock = "w" if "socks" in marks else None

    if pose == "stand":
        by = G - 6 + bob - (1 if cat else 0)  # body top
        x0, x1 = (7, 20) if small else (5, 21)
        if cat:
            x0, x1 = 6, 21
        tail(g, spec, cat, x0 + 1, by, wag=step % 2)
        legs_top = by + 4
        # Far legs, shaded, a step out of phase with the near legs.
        for lx in ((x0 + 3, x1 - 3) if not small else (x0 + 3, x1 - 3)):
            g.rect(lx, legs_top, lx, G, "s")
        g.rect(x0, by, x1, by + 4 + (0 if not cat else -1), "b", round_=1)
        if "belly" in marks:
            g.rect(x0 + 2, by + 4, x1 - 3, by + 4, "w")
        elif not cat:
            g.rect(x0 + 2, by + 4, x1 - 2, by + 4, "s")
        if "chest" in marks:
            g.rect(x1 - 2, by + 1, x1, by + 3, "w")
        if "stripes" in marks:
            for sx in range(x0 + 3, x1 - 3, 3):
                g.px([(sx, by), (sx, by + 1)], "m")
        for lx, d in ((x0, step), (x1 - 1, -step)):
            g.rect(lx, legs_top, lx + 1, G - 1, "b")
            g.px([(lx + d, G), (lx + 1 + d, G)], sock or "b")
        anchors = head(g, spec, cat, x1 - 4, by - 7 + (1 if cat else 0), mouth=mouth, blink=blink)
        return g, anchors

    if pose == "sit":
        x0 = 7
        tail(g, spec, cat, x0 + 2, G - 5, wag=step)
        # Haunch, chest, front legs.
        g.rect(x0, G - 5, x0 + 8, G, "b", round_=2)
        g.rect(x0 + 6, G - 9, x0 + 12, G - 1, "b", round_=1)
        if "chest" in marks or "belly" in marks or "muzzle" in marks and not cat:
            g.rect(x0 + 10, G - 7, x0 + 12, G - 3, "w")
        if "stripes" in marks:
            g.px([(x0 + 2, G - 4), (x0 + 2, G - 3), (x0 + 4, G - 5), (x0 + 4, G - 4)], "m")
        g.rect(x0 + 10, G - 3, x0 + 10, G, "s")
        if paw:
            g.rect(x0 + 12, G - 5, x0 + 13, G - 4, "b")
            g.px([(x0 + 14, G - 5)], sock or "b")
        else:
            g.rect(x0 + 12, G - 3, x0 + 13, G - 1, "b")
            g.px([(x0 + 12, G), (x0 + 13, G)], sock or "b")
        g.px([(x0 + 1, G), (x0 + 2, G), (x0 + 3, G)], sock or "b")
        anchors = head(g, spec, cat, x0 + 6 + (1 if tilt else 0), G - 16 + tilt, mouth=mouth, blink=blink, look_up=bool(tilt))
        return g, anchors

    # Sleep: a low loaf with the head down on the front paws.
    x0 = 6 if not small else 8
    top = G - 4 - breathe
    if cat:
        g.px([(x0 - 1, G), (x0 - 2, G), (x0 - 3, G - 1), (x0 - 3, G - 2)], "b")
    else:
        tail(g, spec, cat, x0 + 1, G - 2)
    g.rect(x0, top, 20, G, "b", round_=2)
    if "stripes" in marks:
        for sx in range(x0 + 3, 18, 3):
            g.px([(sx, top), (sx, top + 1)], "m")
    g.rect(21, G, 25, G, sock or "w" if "muzzle" in marks else "b")
    anchors = head(g, spec, cat, 15, G - 8, blink=True)
    return g, anchors


# ---------------------------------------------------------------- Kong

KONG = {"b": "#4A4752", "s": "#35333C", "w": "#9C8C80", "f": "#B9A797", "line": "#16151A",
        "e": "#1A1414", "n": "#3A2E2A", "k": "#5A1E22", "p": "#E88A98", "c": "#C99A8E"}


def kong_head(g, hx, hy, mouth=False, blink=False):
    g.rect(hx, hy, hx + 9, hy + 8, "b", round_=2)
    g.px([(hx + 1, hy + 3), (hx, hy + 4)], "s")  # ear
    g.rect(hx + 4, hy + 3, hx + 10, hy + 8, "f", round_=1)
    g.rect(hx + 4, hy + 2, hx + 9, hy + 2, "s")  # brow
    if blink:
        g.px([(hx + 7, hy + 4), (hx + 8, hy + 4)], "e")
    else:
        g.px([(hx + 8, hy + 3), (hx + 8, hy + 4)], "e")
    g.px([(hx + 10, hy + 5)], "n")
    if mouth:
        g.rect(hx + 7, hy + 6, hx + 10, hy + 7, "k")
        g.px([(hx + 8, hy + 7)], "p")
    else:
        g.px([(hx + 8, hy + 7), (hx + 9, hy + 7)], "s")
    return {"head": (hx, hy, 10), "eye": (hx + 8, hy + 3), "neck": (hx + 1, hy + 8)}


def kong(pose="stand", step=0, bob=0, mouth=False, pound=0, breathe=0, blink=False):
    g = Grid(KW, KH)
    if pose == "stand":
        top = KG - 13 + bob
        # Far arm and leg, then the body sloping down to the rump.
        g.rect(13, top + 8, 14, KG, "s")
        g.rect(23, top + 5, 24, KG, "s")
        g.rect(5, top + 3, 26, top + 10, "b", round_=3)
        g.rect(13, top, 26, top + 4, "b", round_=2)
        g.rect(20, top + 4, 24, top + 8, "f", round_=1)
        g.rect(7, top + 9, 9, KG - 1, "b")
        g.px([(7 + step, KG), (8 + step, KG), (9 + step, KG)], "b")
        g.rect(25, top + 5, 27, KG - 1, "b")
        g.px([(25 - step, KG), (26 - step, KG), (27 - step, KG), (28 - step, KG)], "s")
        return g, kong_head(g, 24, top - 6, mouth=mouth, blink=blink)
    if pose == "sit":
        top = KG - 15
        g.rect(8, top + 2, 24, KG, "b", round_=3)
        g.rect(16, top + 4, 22, KG - 3, "f", round_=2)
        g.rect(9, KG - 1, 14, KG, "s")
        g.rect(19, KG - 1, 25, KG, "s")
        if pound:
            # Arms up beating the chest, one at a time.
            ax = 18 if pound == 1 else 20
            g.rect(ax, top + 4, ax + 4, top + 6, "b", round_=1)
            g.rect(24, top + 3, 26, top + 9, "b", round_=1)
        else:
            g.rect(23, top + 4, 25, KG - 1, "b", round_=1)
            g.px([(24, KG), (25, KG), (26, KG)], "s")
        return g, kong_head(g, 14, top - 7, mouth=mouth or bool(pound), blink=blink)
    # Sleep: dozing sitting up, head nodding down onto the chest.
    top = KG - 15 + breathe
    g.rect(8, top + 2, 24, KG, "b", round_=3)
    g.rect(16, top + 4, 22, KG - 3, "f", round_=2)
    g.rect(9, KG - 1, 14, KG, "s")
    g.rect(19, KG - 1, 25, KG, "s")
    g.rect(21, top + 6, 24, KG - 1, "b", round_=1)
    return g, kong_head(g, 13, top - 5, blink=True)


# ---------------------------------------------------------------- Wardrobe

WARDROBE = ["party-hat", "bow", "crown", "bandana", "glasses", "flower"]
WEAR_PALETTE = {
    "r": "#E8485A", "y": "#F7D046", "Y": "#D9A520", "b": "#5AA0F0", "p": "#F48FB8", "P": "#D9608E",
    "g": "#58B368", "k": "#22202A", "l": "#BFE6FF", "w": "#FFFFFF", "o": "#F79A3E",
}
WEAR_LINE = "#2A1E24"


def wear(item, anchors, w, h):
    """An overlay grid for one item, positioned from the frame's anchors."""
    g = Grid(w, h)
    hx, hy, hw = anchors["head"]
    ex, ey = anchors["eye"]
    nx, ny = anchors["neck"]
    if item == "party-hat":
        cx = hx + 5
        g.px([(cx, hy - 6)], "y")
        g.px([(cx, hy - 5)], "r")
        g.px([(cx - 1, hy - 4), (cx, hy - 4), (cx + 1, hy - 4)], "b")
        g.px([(cx - 1, hy - 3), (cx, hy - 3), (cx + 1, hy - 3)], "r")
        g.px([(cx + i, hy - 2) for i in range(-2, 3)], "y")
        g.px([(cx + i, hy - 1) for i in range(-2, 3)], "b")
    elif item == "bow":
        cx = hx + 4
        g.px([(cx - 2, hy - 2), (cx - 2, hy - 1), (cx - 1, hy - 1), (cx + 2, hy - 2), (cx + 2, hy - 1), (cx + 1, hy - 1)], "p")
        g.px([(cx - 1, hy - 2), (cx + 1, hy - 2)], "p")
        g.px([(cx, hy - 1)], "P")
    elif item == "crown":
        cx = hx + 5
        g.px([(cx - 2, hy - 4), (cx, hy - 4), (cx + 2, hy - 4)], "y")
        g.px([(cx + i, hy - 3) for i in range(-2, 3)], "y")
        g.px([(cx + i, hy - 2) for i in range(-2, 3)], "Y")
        g.px([(cx, hy - 3)], "r")
    elif item == "bandana":
        g.px([(nx + i, ny) for i in range(0, 7)], "r")
        g.px([(nx + i, ny + 1) for i in range(1, 6)], "r")
        g.px([(nx + i, ny + 2) for i in range(2, 4)], "r")
        g.px([(nx + 2, ny), (nx + 5, ny)], "w")
    elif item == "glasses":
        g.px([(ex - 1, ey), (ex, ey), (ex + 1, ey), (ex - 1, ey + 1), (ex, ey + 1), (ex + 1, ey + 1)], "k")
        g.px([(ex - 1, ey)], "l")
        g.px([(ex - 2, ey), (ex - 3, ey)], "k")
    elif item == "flower":
        fx, fy = hx + 2, hy - 1
        g.px([(fx, fy - 1), (fx - 1, fy), (fx + 1, fy), (fx, fy + 1)], "w")
        g.px([(fx, fy)], "y")
        g.px([(fx + 1, fy + 1)], "g")
    return g


# ---------------------------------------------------------------- Treats and poop
#
# Text pixel grids; the outline is added around them like the pets.

def text_sprite(rows, pal, line):
    width = max(len(r) for r in rows)
    g = Grid(width + 2, len(rows) + 2)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                g.px([(x + 1, y + 1)], ch)
    return g.render(pal, line)


def bone():
    return text_sprite([
        ".hh.........hh.",
        "hhbb.......hbbs",
        ".hbbbbbbbbbbbs.",
        ".bbbbbbbbbbbbs.",
        "hbbs.......bbbs",
        ".ss.........ss.",
    ], {"h": "#FFFFFF", "b": "#F3E6CC", "s": "#D2BE98"}, "#6B5536")


def fish():
    return text_sprite([
        "ss....bbbb.....",
        "sbs.bbbbbbbb...",
        ".sbbbbbbbbebb..",
        ".sbbbbbbbbbbbb.",
        "sbs.hhhhhhhhh..",
        "ss....hhhh.....",
    ], {"b": "#7FB6E0", "s": "#4F86B8", "h": "#CFE6F5", "e": "#1E1410"}, "#1E3550")


def banana():
    return text_sprite([
        "k.............",
        ".yy.........yk",
        ".hyy.......yy.",
        "..hyyy...yyys.",
        "...hyyyyyyys..",
        "....sssssss...",
    ], {"y": "#FFD84A", "h": "#FFF0A0", "s": "#E0A820", "k": "#6B4A1E"}, "#5A3A10")


def poop():
    """A cute three-tier swirl with a face."""
    return text_sprite([
        ".......hb......",
        "......hbbs.....",
        ".....hbbbbs....",
        ".....bbbbbs....",
        "......sssss....",
        "....hbbbbbbbs..",
        "...hbbbbbbbbbs.",
        "...bbbbbbbbbbs.",
        "....sssssssss..",
        "..hbbbbbbbbbbbs",
        ".hbbbbbbbbbbbbs",
        ".bbbewbbbbewbbs",
        ".bbbeebbbbeebbs",
        ".bpbbbbkkbbbpbs",
        "..sssssssssss..",
    ], {"h": "#B07A4E", "b": "#8A5A34", "s": "#6A4224", "e": "#1E1410", "w": "#FFFFFF", "k": "#4A2414", "p": "#D98A7A"}, "#3A2212")


# ---------------------------------------------------------------- Bowls
#
# Two layers so treats sit inside: the back (far rim and the cream inside)
# and the front (near lip and the body with a paw print).

BOWL_W, BOWL_H = 28, 16
BOWLS = {
    "appleReminders": {"R": "#FFC98A", "b": "#F7A04E", "s": "#D97B32", "h": "#FFE3BE", "line": "#5A2C12"},
    "googleTasks": {"R": "#A9D2FF", "b": "#5E9FEC", "s": "#3F7BCB", "h": "#D8EBFF", "line": "#1C2F5A"},
}
BOWL_INSIDE = {"d": "#F6E9D2", "D": "#DCC6A2", "w": "#FFFFFF"}


def bowl(colors):
    pal = dict(colors, **BOWL_INSIDE)
    back = Grid(BOWL_W, BOWL_H)
    back.rect(6, 1, 21, 1, "R")
    back.rect(3, 2, 24, 2, "R")
    back.rect(2, 3, 25, 3, "R")
    back.rect(1, 4, 26, 5, "R")
    back.rect(7, 2, 20, 2, "D")
    back.rect(4, 3, 23, 3, "D")
    back.rect(3, 4, 24, 5, "d")

    front = Grid(BOWL_W, BOWL_H)
    front.rect(1, 6, 26, 6, "R")
    front.rect(4, 6, 7, 6, "h")
    for y, (x0, x1) in enumerate([(1, 26), (1, 26), (2, 25), (2, 25), (3, 24), (4, 23), (6, 21)], start=7):
        front.rect(x0, y, x1, y, "s" if y == 13 else "b")
        front.px([(x1 - 1, y), (x1, y)], "s")
    front.px([(3, 8), (3, 9), (4, 10)], "h")
    # Paw print.
    front.px([(11, 9), (13, 8), (14, 8), (16, 9)], "w")
    front.rect(12, 10, 15, 12, "w", round_=1)
    return back.render(pal, colors["line"]), front.render(pal, colors["line"])


# ---------------------------------------------------------------- Sheets

def poses_quad(spec, cat):
    walk = [quad(spec, cat, step=s, bob=b) for s, b in ((1, 0), (0, -1), (-1, 0), (0, -1))]
    idle = [quad(spec, cat), quad(spec, cat), quad(spec, cat, blink=True), quad(spec, cat, bob=1)]
    sit = [quad(spec, cat, "sit")]
    bark = [quad(spec, cat, "sit", mouth=True, step=1), quad(spec, cat, "sit")]
    beg = [quad(spec, cat, "sit", tilt=1, paw=True), quad(spec, cat, "sit", tilt=1)]
    sleep = [quad(spec, cat, "sleep"), quad(spec, cat, "sleep", breathe=1)]
    return [idle, walk, sit, bark, beg, sleep]


def poses_kong():
    walk = [kong(step=s, bob=b) for s, b in ((1, 0), (0, -1), (-1, 0), (0, -1))]
    idle = [kong(), kong(), kong(blink=True), kong(bob=1)]
    sit = [kong("sit")]
    bark = [kong("sit", pound=1), kong("sit", pound=2)]
    beg = [kong("sit", blink=True), kong("sit")]
    sleep = [kong("sleep"), kong("sleep", breathe=1)]
    return [idle, walk, sit, bark, beg, sleep]


def build(poses, palette, outline, w, h):
    pet = sheet([[g.render(palette, outline) for g, _ in row] for row in poses])
    wears = {}
    for item in WARDROBE:
        wears[item] = sheet([[wear(item, a, w, h).render(WEAR_PALETTE, WEAR_LINE) for _, a in row] for row in poses])
    return pet, wears


def animations():
    return {
        "idle": {"row": 0, "count": 4, "fps": 2},
        "walk": {"row": 1, "count": 4, "fps": 8},
        "run": {"row": 1, "count": 4, "fps": 14},
        "sit": {"row": 2, "count": 1},
        "bark": {"row": 3, "count": 2, "fps": 5},
        "beg": {"row": 4, "count": 2, "fps": 1.5},
        "sleep": {"row": 5, "count": 2, "fps": 0.6},
    }


def update_pack(pet_id, w, h, mouth, scale=2.5):
    """Points pet.json at the new sheet and lists the wardrobe."""
    path = os.path.join(ROOT, "Pets", pet_id, "pet.json")
    with open(path) as f:
        pack = json.load(f)
    old = pack["sheet"]
    pack["sheet"] = {
        "image": "sheet.png", "frameWidth": w, "frameHeight": h, "scale": scale,
        "footPadding": 1, "mouth": mouth, "animations": animations(), "wardrobe": WARDROBE,
    }
    if old.get("facing"):
        pack["sheet"]["facing"] = old["facing"]
    pack["credit"] = "Treatly contributors, MIT (scripts/art/chibi.py)"
    with open(path, "w") as f:
        json.dump(pack, f, indent=2)
        f.write("\n")


def main():
    out = {}
    out_bowls = []
    for pet_id, spec in DOGS.items():
        out[pet_id] = build(poses_quad(spec, False), palette_for(spec), spec["line"], W, H) + ((W, H), [29, 15])
    for pet_id, spec in CATS.items():
        out[pet_id] = build(poses_quad(spec, True), palette_for(spec), spec["line"], W, H) + ((W, H), [27, 17])
    out["kong"] = build(poses_kong(), KONG, KONG["line"], KW, KH) + ((KW, KH), [34, 15])

    for pet_id, (pet, wears, (w, h), mouth) in out.items():
        folder = os.path.join(ROOT, "Pets", pet_id)
        write_png(os.path.join(folder, "sheet.png"), pet)
        for item, rows in wears.items():
            write_png(os.path.join(folder, f"wear-{item}.png"), rows)
        update_pack(pet_id, w, h, mouth)
        print("wrote", pet_id)

    extras = {"Resources/Art/poop.png": poop()}
    for pet_id, treat in (("shiba", bone), ("golden", bone), ("chihuahua", bone),
                          ("orange-tabby", fish), ("black-cat", fish), ("kong", banana)):
        extras[f"Pets/{pet_id}/treat.png"] = treat()
    for path, rows in extras.items():
        write_png(os.path.join(ROOT, path), rows)
        print("wrote", path)

    for source, colors in BOWLS.items():
        back, front = bowl(colors)
        write_png(os.path.join(ROOT, f"Resources/Art/bowl-{source}-back.png"), back)
        write_png(os.path.join(ROOT, f"Resources/Art/bowl-{source}.png"), front)
        out_bowls.append([[f or b for b, f in zip(bl, fl)] for bl, fl in zip(back, front)])
        print("wrote bowl", source)

    if "--preview" in sys.argv:
        bg = (44, 44, 50, 255)
        tiles = []
        for pet_id, (pet, wears, (w, h), _) in out.items():
            # Each pose's first frame, then the idle frame in every wardrobe item.
            row = []
            for r in range(6):
                row.append([line[0:w] for line in pet[r * h:(r + 1) * h]])
            for item in WARDROBE:
                frame = [line[0:w] for line in pet[0:h]]
                over = [line[0:w] for line in wears[item][0:h]]
                row.append([[o or p for p, o in zip(pl, ol)] for pl, ol in zip(frame, over)])
            tiles.append(row)
        tiles.append(out_bowls + [poop(), bone(), fish(), banana()])
        tw = max(len(r[0][0]) for r in tiles)
        th = max(len(r[0]) for r in tiles)
        cols = max(len(r) for r in tiles)
        canvas = [[bg] * (cols * (tw + 2)) for _ in range(len(tiles) * (th + 2))]
        for ry, row in enumerate(tiles):
            for cx, tile in enumerate(row):
                oy = ry * (th + 2) + (th - len(tile))
                for y, line in enumerate(tile):
                    for x, p in enumerate(line):
                        if p:
                            canvas[oy + y][cx * (tw + 2) + x] = p
        write_png(os.path.join(ROOT, "build/chibi-preview.png"), upscale(canvas, 4))
        print("wrote build/chibi-preview.png")


if __name__ == "__main__":
    main()
