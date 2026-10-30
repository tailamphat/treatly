#!/usr/bin/env python3
"""All of Treatly's pixel art: the pets as tiny chibi sprites, their wardrobe,
the bowls, the banana trees, the treats and the poop. No dependencies.

Every pixel is placed by hand on a small grid (about 24 pixels wide): a big
head, a boxy body, stubby legs, flat colours with one shade, one-pixel eyes,
and a 1px dark outline added around the silhouette at the end.

Wardrobe items are drawn on overlay sheets with the same layout as the pet's
sheet, anchored to where the head is in each frame.

    python3 scripts/art/chibi.py            # writes Pets/ and Resources/Art/
    python3 scripts/art/chibi.py --preview  # also writes build/chibi-preview.png
"""
import json
import math
import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def hex_rgba(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)



def write_png(path, rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + b"".join(bytes(p or (0, 0, 0, 0)) for p in row) for row in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)



def sheet(rows_of_frames):
    """Stacks frames: one list of frames per sheet row."""
    fh, fw = len(rows_of_frames[0][0]), len(rows_of_frames[0][0][0])
    cols = max(len(r) for r in rows_of_frames)
    out = [[None] * (fw * cols) for _ in range(fh * len(rows_of_frames))]
    for ry, frames in enumerate(rows_of_frames):
        for cx, frame in enumerate(frames):
            for y in range(fh):
                for x in range(fw):
                    out[ry * fh + y][cx * fw + x] = frame[y][x]
    return out



def upscale(rows, k):
    return [[p for p in row for _ in range(k)] for row in rows for _ in range(k)]




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
    "husky": {
        "b": "#7A8494", "s": "#5C6574", "w": "#F4F6FA", "i": "#6EC1F5", "line": "#1E2430",
        "ears": "pointy", "tail": "curl", "marks": ["muzzle", "chest", "belly", "socks", "mask"],
    },
    "chihuahua": {
        "b": "#D9A672", "s": "#B5824F", "w": "#F7E6CF", "line": "#3E2616",
        "ears": "big", "tail": "thin", "marks": ["muzzle", "chest"], "small": True,
    },
    "corgi": {
        "b": "#E3833A", "s": "#BF6526", "w": "#FFF4E2", "line": "#3A2112",
        "ears": "big", "tail": "stub", "marks": ["muzzle", "chest", "belly", "socks", "brows"], "long": True,
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
    if "mask" in marks:
        g.rect(hx + 5, hy + 2, hx + 9, hy + 5, "w", round_=1)
        g.px([(hx + 6, hy + 1)], "w")
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
    elif cat or "i" in spec:
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
    elif kind == "stub":
        g.px([(bx - 1, by), (bx - 2, by), (bx - 2 - wag, by - 1)], role)
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
        if spec.get("long"):
            x0 = 3
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


# ---------------------------------------------------------------- Sheep
#
# A fluffy cloud of wool with a dark face and legs.

SHEEP = {"b": "#F7F3EA", "s": "#DCD4C4", "h": "#FFFFFF", "f": "#3E3946", "F": "#2C2833",
         "W": "#FFFFFF", "e": "#1A1418", "p": "#F29BAE", "c": "#E07A8E", "k": "#5A1E22", "line": "#4A4250"}


def wool(g, x0, y0, x1, y1):
    """A rounded wool blob with bumps along the top and back."""
    g.rect(x0, y0, x1, y1, "b", round_=2)
    for x in range(x0 + 1, x1 - 1, 3):
        g.px([(x, y0 - 1), (x + 1, y0 - 1)], "b")
    for y in range(y0 + 2, y1 - 1, 3):
        g.px([(x0 - 1, y)], "b")
    g.rect(x0 + 2, y1, x1 - 2, y1, "s")
    g.px([(x0 + 2, y0), (x0 + 3, y0), (x0 + 1, y0 + 1)], "h")


def sheep_head(g, hx, hy, mouth=False, blink=False):
    """Dark face, 7x7 from (hx, hy), with a wool cap and a floppy ear."""
    g.rect(hx - 2, hy + 2, hx - 1, hy + 3, "F")
    g.rect(hx, hy, hx + 6, hy + 6, "f", round_=2)
    g.px([(hx + 1, hy - 1), (hx + 2, hy - 1), (hx + 4, hy - 1), (hx, hy), (hx + 1, hy), (hx + 2, hy), (hx + 3, hy), (hx + 4, hy)], "b")
    if blink:
        g.px([(hx + 3, hy + 3), (hx + 4, hy + 3)], "W")
    else:
        g.px([(hx + 3, hy + 2), (hx + 4, hy + 2), (hx + 3, hy + 3)], "W")
        g.px([(hx + 4, hy + 3)], "e")
    g.px([(hx + 2, hy + 5)], "c")
    if mouth:
        g.px([(hx + 5, hy + 5), (hx + 6, hy + 5)], "k")
        g.px([(hx + 5, hy + 6)], "p")
    else:
        g.px([(hx + 6, hy + 5)], "p")
    # Anchors are shifted so items centre on the smaller head.
    return {"head": (hx - 2, hy, 7), "eye": (hx + 4, hy + 2), "neck": (hx - 1, hy + 6)}


def sheep(pose="stand", step=0, bob=0, mouth=False, blink=False, tilt=0, paw=False, breathe=0):
    g = Grid(W, H)
    if pose == "stand":
        by = G - 10 + bob
        for lx in (9, 15):
            g.rect(lx, by + 4, lx + 1, G, "F")
        wool(g, 5, by, 20, by + 5)
        g.px([(3, by + 2), (3, by + 3)], "b")
        for lx, d in ((6, step), (17, -step)):
            g.rect(lx, by + 5, lx + 1, G - 1, "f")
            g.px([(lx + d, G), (lx + 1 + d, G)], "f")
        return g, sheep_head(g, 19, by - 4, mouth=mouth, blink=blink)
    if pose == "sit":
        wool(g, 6, G - 8, 18, G)
        g.rect(15, G - 1, 16, G, "F")
        if paw:
            g.rect(19, G - 4, 20, G - 3, "f")
        else:
            g.rect(18, G - 2, 19, G, "f")
        return g, sheep_head(g, 16 + (1 if tilt else 0), G - 14 + tilt, mouth=mouth, blink=blink)
    wool(g, 5, G - 5 - breathe, 20, G)
    g.px([(21, G), (22, G)], "f")
    return g, sheep_head(g, 18, G - 7, blink=True)


def poses_sheep():
    walk = [sheep(step=s, bob=b) for s, b in ((1, 0), (0, -1), (-1, 0), (0, -1))]
    idle = [sheep(), sheep(), sheep(blink=True), sheep(bob=1)]
    sit = [sheep("sit")]
    bark = [sheep("sit", mouth=True), sheep("sit")]
    beg = [sheep("sit", tilt=1, paw=True), sheep("sit", tilt=1)]
    sleep = [sheep("sleep"), sheep("sleep", breathe=1)]
    return [idle, walk, sit, bark, beg, sleep]


# ---------------------------------------------------------------- Panda
#
# A round white body with black legs, a black shoulder band, black ears and eye patches.

PANDA = {"b": "#F7F5F0", "s": "#DCD8CE", "f": "#2E2C34", "F": "#1F1E24", "W": "#FFFFFF",
         "e": "#2E2C34", "n": "#1F1E24", "p": "#F29BAE", "c": "#F4A7B4", "k": "#5A1E22", "line": "#1A191E"}


def panda_head(g, hx, hy, mouth=False, blink=False):
    """Round white head, 10x8 from (hx, hy), facing right."""
    for ex in (hx + 1, hx + 6):
        g.rect(ex, hy - 2, ex + 2, hy - 1, "f", round_=1)
    g.rect(hx, hy, hx + 9, hy + 7, "b", round_=2)
    g.rect(hx + 10, hy + 4, hx + 10, hy + 6, "b")
    # A big droopy eye patch with a shiny eye in it.
    g.rect(hx + 5, hy + 2, hx + 8, hy + 4, "f", round_=1)
    g.px([(hx + 5, hy + 5), (hx + 6, hy + 5), (hx + 5, hy + 4)], "f")
    if not blink:
        g.px([(hx + 7, hy + 3)], "W")
        g.px([(hx + 7, hy + 2)], "e")
    g.px([(hx + 10, hy + 4)], "n")
    g.px([(hx + 7, hy + 6)], "c")
    if mouth:
        g.px([(hx + 8, hy + 6), (hx + 9, hy + 6), (hx + 10, hy + 6)], "k")
        g.px([(hx + 9, hy + 7)], "p")
    return {"head": (hx, hy, 10), "eye": (hx + 7, hy + 3), "neck": (hx + 1, hy + 7)}


PANDA_PAWS = [23, 16]  # where the treat is held while carrying, in frame pixels


def panda(pose="stand", step=0, bob=0, mouth=False, blink=False, tilt=0, paw=False, breathe=0):
    g = Grid(W, H)
    if pose == "stand":
        # Waddles upright on its hind legs, both paws out front to hold the treat.
        top = G - 10 + bob
        for lx, lift in ((12, step == 1), (17, step == -1)):
            g.rect(lx, top + 8, lx + 2, G - (1 if lift else 0), "f", round_=1 if lift else 0)
        g.px([(10, top + 5), (10, top + 6)], "b")
        g.rect(11, top, 20, top + 8, "b", round_=2)
        g.rect(13, top + 7, 18, top + 8, "s")
        g.rect(11, top, 20, top + 2, "f", round_=1)
        g.rect(17, top + 1, 21, top + 3, "F", round_=1)
        g.rect(18, top + 2, 23, top + 4, "f", round_=1)
        return g, panda_head(g, 13, top - 7, mouth=mouth, blink=blink)
    if pose == "sit":
        g.rect(7, G - 7, 18, G, "b", round_=3)
        g.rect(14, G - 8, 18, G - 4, "f", round_=1)
        g.rect(7, G - 1, 10, G, "f")
        if paw:
            g.rect(17, G - 6, 20, G - 5, "f")
        else:
            g.rect(16, G - 4, 17, G, "f")
        return g, panda_head(g, 12 + (1 if tilt else 0), G - 15 + tilt, mouth=mouth, blink=blink)
    if pose == "trip":
        # Face-plant: head on the ground, bottom and hind legs up in the air.
        g.rect(6, G - 13, 8, G - 10, "f", round_=1)
        g.rect(9, G - 12, 11, G - 9, "F", round_=1)
        g.rect(7, G - 10, 17, G - 3, "b", round_=2)
        g.rect(13, G - 9, 17, G - 4, "f", round_=1)
        g.rect(19, G - 1, 24, G, "f")
        return g, panda_head(g, 15, G - 8, blink=True)
    if pose == "flop":
        # Rolled onto its back, paws in the air.
        for lx in (8, 15):
            g.rect(lx, G - 10, lx + 2, G - 6, "f", round_=1)
        g.rect(6, G - 6, 19, G, "b", round_=3)
        g.rect(15, G - 6, 18, G - 3, "f", round_=1)
        return g, panda_head(g, 16, G - 8, mouth=True, blink=True)
    g.rect(5, G - 5 - breathe, 20, G, "b", round_=3)
    g.rect(14, G - 5 - breathe, 17, G, "f", round_=1)
    g.rect(6, G, 8, G, "f")
    g.px([(21, G), (22, G)], "f")
    return g, panda_head(g, 16, G - 8, blink=True)


# ---------------------------------------------------------------- Capybara
#
# A brown barrel with a long blunt head, tiny ears and very relaxed eyes.

CAPY = {"b": "#B07A4A", "s": "#8C5C32", "f": "#9A6A3E", "e": "#1E1410", "n": "#2A1A14",
        "p": "#F29BAE", "c": "#E9967A", "k": "#5A1E22", "line": "#3A2414"}


def capy_head(g, hx, hy, mouth=False, blink=False):
    """Long boxy head, 12x7 from (hx, hy), facing right."""
    g.px([(hx + 2, hy - 1), (hx + 3, hy - 1)], "s")
    g.rect(hx, hy, hx + 11, hy + 6, "b", round_=1)
    g.rect(hx + 9, hy + 1, hx + 11, hy + 6, "f", round_=1)
    # Half-closed eyes: a lid over a single pixel.
    if blink:
        g.px([(hx + 5, hy + 2), (hx + 6, hy + 2)], "e")
    else:
        g.px([(hx + 5, hy + 2), (hx + 6, hy + 2)], "s")
        g.px([(hx + 6, hy + 3)], "e")
    g.px([(hx + 11, hy + 2)], "n")
    g.px([(hx + 7, hy + 5)], "c")
    if mouth:
        g.px([(hx + 9, hy + 5), (hx + 10, hy + 5), (hx + 11, hy + 5)], "k")
        g.px([(hx + 10, hy + 6)], "p")
    else:
        g.px([(hx + 10, hy + 5), (hx + 11, hy + 5)], "s")
    return {"head": (hx, hy, 10), "eye": (hx + 6, hy + 2), "neck": (hx + 1, hy + 6)}


def capybara(pose="stand", step=0, bob=0, mouth=False, blink=False, tilt=0, paw=False, breathe=0):
    g = Grid(W, H)
    if pose == "stand":
        by = G - 9 + bob
        for lx in (8, 17):
            g.rect(lx, by + 5, lx + 1, G, "s")
        g.rect(3, by, 20, by + 6, "b", round_=3)
        g.rect(6, by + 6, 17, by + 6, "s")
        for lx, d in ((5, step), (17, -step)):
            g.rect(lx, by + 6, lx + 1, G - 1, "b")
            g.px([(lx + d, G), (lx + 1 + d, G)], "s")
        return g, capy_head(g, 16, by - 3, mouth=mouth, blink=blink)
    if pose == "sit":
        g.rect(6, G - 8, 17, G, "b", round_=3)
        g.rect(6, G, 9, G, "s")
        if paw:
            g.rect(16, G - 5, 19, G - 4, "b")
        else:
            g.rect(15, G - 3, 16, G, "b")
            g.px([(15, G), (16, G)], "s")
        return g, capy_head(g, 11 + (1 if tilt else 0), G - 14 + tilt, mouth=mouth, blink=blink)
    g.rect(4, G - 6 - breathe, 20, G, "b", round_=3)
    g.px([(21, G), (22, G)], "s")
    return g, capy_head(g, 15, G - 7, blink=True)


def poses_panda():
    """The usual six rows plus a seventh: tripping over its own feet."""
    return poses_simple(panda) + [[panda("trip"), panda("flop"), panda("sit", blink=True)]]


def poses_simple(draw):
    """The six rows for a pet drawn by one function, like the sheep."""
    walk = [draw(step=s, bob=b) for s, b in ((1, 0), (0, -1), (-1, 0), (0, -1))]
    idle = [draw(), draw(), draw(blink=True), draw(bob=1)]
    sit = [draw("sit")]
    bark = [draw("sit", mouth=True), draw("sit")]
    beg = [draw("sit", tilt=1, paw=True), draw("sit", tilt=1)]
    sleep = [draw("sleep"), draw("sleep", breathe=1)]
    return [idle, walk, sit, bark, beg, sleep]


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


def clover():
    return text_sprite([
        "...gg......",
        "..ghgg.....",
        "..gggg.gg..",
        "gg.gG.ghgg.",
        "ghggGGgggg.",
        "ggggGgg....",
        ".gg..s.....",
        "......s....",
    ], {"g": "#6CBF4A", "G": "#4C9A34", "h": "#A8E27E", "s": "#4C9A34"}, "#1F4A1A")


def banana():
    return text_sprite([
        "k.............",
        ".yy.........yk",
        ".hyy.......yy.",
        "..hyyy...yyys.",
        "...hyyyyyyys..",
        "....sssssss...",
    ], {"y": "#FFD84A", "h": "#FFF0A0", "s": "#E0A820", "k": "#6B4A1E"}, "#5A3A10")


POOP_ROWS = [
    "........hb.......",
    ".......hbbs......",
    "......hbbbbs.....",
    ".....hbbbbbbs....",
    "......oooooo.....",
    "....hbbbbbbbbs...",
    "...hbbbbbbbbbbs..",
    "..hbbbbbbbbbbbbs.",
    "...oooooooooooo..",
    ".hbbbbbbbbbbbbbs.",
    "hbbbewbbbbbewbbbs",
    "hbbbeebbbbbeebbbs",
    "bbppbbkbkbkbbppbs",
    "bsbbbbbkbkbbbbbss",
    ".sssssssssssssss.",
]
POOP_FACE = {"e": "#2A1A1A", "w": "#FFFFFF", "k": "#2A1A1A", "p": "#F79AB0"}
POOP_STYLES = ["cute", "classic", "golden", "rainbow"]


def poop(style="cute"):
    """Three tiers split by dark lines; most styles have a happy face."""
    rows = list(POOP_ROWS)
    pal = {"h": "#B98256", "b": "#946038", "s": "#714628", "o": "#3E2414", **POOP_FACE}
    line = "#3E2414"
    if style == "classic":
        rows = [r.translate(str.maketrans("ewkp", "bbbb")) for r in rows]
    elif style == "golden":
        pal.update({"h": "#FFF0A0", "b": "#F7C842", "s": "#D49A1E", "o": "#8A5A10"})
        line = "#6A4208"
        # Sparkles.
        rows = [r for r in rows]
        rows[1] = "..x...." + rows[1][7:]
        rows[6] = rows[6][:15] + "x."
        pal["x"] = "#FFFFFF"
    elif style == "rainbow":
        tiers = [("147", range(0, 4)), ("258", range(5, 8)), ("369", range(9, 15))]
        for chars, span in tiers:
            for i in span:
                rows[i] = rows[i].translate(str.maketrans("hbs", chars))
        pal.update({"1": "#FF9CC2", "4": "#FFD0E2", "7": "#E06A98",
                    "2": "#FFE37A", "5": "#FFF3BE", "8": "#E0B83A",
                    "3": "#8CC8FF", "6": "#CDE6FF", "9": "#5A98E0", "o": "#7A5A8A"})
        line = "#5A3E6A"
    return text_sprite(rows, pal, line)


# ---------------------------------------------------------------- Bowls
#
# Two layers so treats sit inside: the back (far rim and the cream inside)
# and the front (near lip and the body with a paw print).

# Five designs share one shape: a round bowl seen from a little above, with
# the opening on top so treats can sit inside. Keep in sync with BowlStyle.

BOWL_W, BOWL_H = 26, 17
BOWL_CX = 13
RIM = (5.0, 11.5, 4.5)      # outer rim ellipse: cy, rx, ry
OPENING = (5.3, 9.3, 3.2)   # the hole
BOWL_STYLES = ["classic", "steel", "ceramic", "puppy", "tub"]
SOURCES = {
    "appleReminders": {"m": "#F08A3A", "M": "#C2621F", "L": "#FFBD7A", "Lh": "#FFE6C8", "line": "#4A1E08"},
}
KIBBLE = {"1": "#B9773A", "2": "#8E5424", "3": "#D99A55"}
HAY = {"1": "#F2D27A", "2": "#D9B254", "3": "#FFE89A"}
FACE = {"w": "#FFFFFF", "e": "#2A1A1A", "p": "#F79AB0", "k": "#2A1A1A"}


def _in(x, y, ellipse):
    cy, rx, ry = ellipse
    return ((x + 0.5 - BOWL_CX) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1


def dish():
    """The shared shape. Roles: R rim, H rim shine, I inside wall, b body,
    h body shine, S right shade, s base, 1-3 food."""
    back = Grid(BOWL_W, BOWL_H)
    front = Grid(BOWL_W, BOWL_H)
    for y in range(BOWL_H):
        for x in range(BOWL_W):
            if _in(x, y, OPENING):
                if y + 0.5 < OPENING[0] - 0.6:
                    back.px([(x, y)], "I")
                else:
                    n = ((x * 73856093) ^ (y * 19349663)) % 7
                    back.px([(x, y)], "3" if n == 0 else "2" if n in (1, 2) else "1")
            elif _in(x, y, RIM):
                back.px([(x, y)], "H" if x < BOWL_CX - 3 and y <= 2 else "R")
                if y + 0.5 >= RIM[0]:
                    front.px([(x, y)], "R")
            elif y + 0.5 > RIM[0]:
                hw = RIM[1] + (y - RIM[0]) * 0.14
                dx = x + 0.5 - BOWL_CX
                if abs(dx) > hw:
                    continue
                bottom = 12 + 2 * max(0.0, 1 - (dx / hw) ** 2) ** 0.5
                if y > bottom:
                    continue
                if y > bottom - 1.5:
                    role = "s"
                elif dx > hw - 2.5:
                    role = "S"
                elif -hw + 1.5 <= dx < -hw + 2.5:
                    role = "h"
                else:
                    role = "b"
                front.px([(x, y)], role)
    return back, front


def _body(front):
    return [(x, y) for y in range(BOWL_H) for x in range(BOWL_W) if front.get(x, y) in ("b", "h", "S")]


def bowl(style, source):
    c = SOURCES[source]
    back, front = dish()
    pal = dict(KIBBLE, **FACE)
    line = c["line"]
    if style == "classic":
        # Plastic in the source colour with a white paw print.
        pal.update({"R": c["L"], "H": c["Lh"], "I": c["M"], "b": c["m"], "h": c["L"], "S": c["M"], "s": c["M"]})
        front.px([(10, 10), (12, 9), (14, 9), (16, 10)], "w")
        front.rect(11, 11, 15, 12, "w", round_=1)
    elif style == "steel":
        # Shiny stainless steel on a rubber base in the source colour.
        pal.update({"R": "#E8ECF2", "H": "#FFFFFF", "I": "#8A94A4", "b": "#C4CCD8", "h": "#F4F7FB",
                    "S": "#9AA4B4", "s": c["m"], "x": "#FFFFFF"})
        line = "#3A4250"
        front.px([(5, 9), (5, 10), (6, 10), (6, 11), (19, 9), (20, 10)], "x")
    elif style == "ceramic":
        # Cream ceramic with a coloured rim and a bone on the side.
        pal.update({"R": c["m"], "H": c["L"], "I": "#D8C8B0", "b": "#F6EEDF", "h": "#FFFFFF",
                    "S": "#DCCDB6", "s": "#C8B89E", "m": c["m"]})
        line = "#5A4A38"
        front.px([(9, 10), (9, 12), (17, 10), (17, 12)], "m")
        front.rect(9, 11, 17, 11, "m")
        front.px([(8, 10), (8, 12), (18, 10), (18, 12)], "m")
    elif style == "puppy":
        # A puppy face with floppy ears hanging over the sides.
        pal.update({"R": c["L"], "H": c["Lh"], "I": c["M"], "b": c["m"], "h": c["L"], "S": c["M"], "s": c["M"], "E": c["M"]})
        front.px([(10, 9), (10, 10), (15, 9), (15, 10)], "e")
        front.px([(8, 11), (17, 11)], "p")
        front.px([(12, 11), (13, 11)], "e")
        front.px([(11, 12), (12, 13), (13, 13), (14, 12)], "k")
        for x0 in (0, 23):
            front.rect(x0, 5, x0 + 2, 10, "E", round_=1)
            front.px([(x0 + 1, 11)], "E")
    elif style == "tub":
        # A countryside wooden tub full of hay, banded in the source colour.
        pal.update({"R": "#C98E52", "H": "#E3B07A", "I": "#6E431E", "b": "#B0733C", "h": "#E3B07A",
                    "S": "#8C5A2C", "s": "#6E431E", "P": "#7A4A22", "m": c["m"], "M": c["M"]})
        pal.update(HAY)
        line = "#3E2412"
        body = _body(front)
        front.px([(x, y) for x, y in body if x in (6, 10, 14, 18)], "P")
        front.px([(x, y) for x, y in body if y in (9, 12)], "m")
        front.px([(x, y) for x, y in body if y in (9, 12) and x >= 21], "M")
    return back.render(pal, line), front.render(pal, line)


# ---------------------------------------------------------------- Banana tree
#
# King Kong's version of a bowl: a little palm, bananas hang under the crown.

TREE_W, TREE_H = 38, 46
TREE_CROWN = (19, 14)
TREE = {"t": "#B07A44", "T": "#8C5A2C", "r": "#6E431E", "u": "#D9A066",
        "g": "#62C04E", "G": "#3E9132", "l": "#A4E47E",
        "q": "#3F9A3A", "Q": "#2A7028", "L": "#6CC452",
        "d": "#9A6A3E", "D": "#7A4E2A", "y": "#F7C842", "w": "#FFFFFF"}


def _bez(p0, p1, p2, t):
    return tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * c for a, b, c in zip(p0, p1, p2))


def _frond(g, control, end, role, thick=4.2):
    """A leaf along a curve: narrow at the crown, wide in the middle, pointed
    tip, with a midrib. Returns the midrib pixels."""
    rib = []
    for i in range(61):
        t = i / 60
        x, y = _bez(TREE_CROWN, control, end, t)
        r = thick * (0.35 + 0.65 * math.sin(math.pi * min(1.0, t * 1.05))) / 2
        for py in range(int(y - r - 1), int(y + r + 2)):
            for px in range(int(x - r - 1), int(x + r + 2)):
                if (px + 0.5 - x) ** 2 + (py + 0.5 - y) ** 2 <= r * r + 0.15:
                    g.px([(px, py)], role)
        if 0.2 < t < 0.85:
            rib.append((int(x), int(y)))
    return rib


def tree(source):
    c = SOURCES[source]
    g = Grid(TREE_W, TREE_H)
    # Ground mound with grass and a flower.
    g.rect(9, 42, 28, 43, "d", round_=1)
    g.rect(12, 41, 25, 41, "d")
    g.rect(13, 43, 28, 43, "D")
    g.px([(11, 41), (12, 40), (14, 40), (23, 40), (25, 40), (26, 41), (10, 42), (27, 42)], "g")
    g.px([(9, 40), (8, 41), (10, 41), (9, 42)], "w")
    g.px([(9, 41)], "y")
    # Trunk: leans a little, rings every few rows, lit on the left.
    for y in range(TREE_CROWN[1] + 2, 42):
        f = (y - TREE_CROWN[1]) / (42 - TREE_CROWN[1])
        cx = TREE_CROWN[0] - 3 * f * f + 1.5 * f
        half = 1.5 + 1.2 * f
        x0, x1 = round(cx - half), round(cx + half)
        g.rect(x0, y, x1, y, "r" if y % 3 == 0 else "t")
        if y % 3:
            g.px([(x0, y)], "u")
            g.px([(x1, y)], "T")
    # Ribbon in the source's colour.
    for y in (31, 32):
        for x in range(TREE_W):
            if g.get(x, y) in ("t", "u", "T", "r"):
                g.px([(x, y)], "m" if y == 31 else "M")
    g.px([(21, 33), (22, 34), (20, 33)], "m")
    # Fronds: darker ones at the back, brighter drooping ones in front,
    # each with a midrib so the leaves read separately.
    ribs = []
    for control, end, role in (((11, 0), (3, 9), "q"), ((27, 0), (35, 9), "q"), ((19, 0), (20, 1), "q"),
                               ((8, 6), (2, 21), "g"), ((30, 6), (36, 21), "g"), ((14, 3), (9, 4), "g"), ((24, 3), (29, 4), "g")):
        ribs.append((_frond(g, control, end, role), role))
    for base, light, shade in (("g", "l", "G"), ("q", "L", "Q")):
        leaf = [(x, y) for y in range(TREE_H) for x in range(TREE_W) if g.get(x, y) == base]
        g.px([(x, y) for x, y in leaf if g.get(x, y - 1) not in (base, light)], light)
        g.px([(x, y) for x, y in leaf if g.get(x, y + 1) is None], shade)
    for rib, role in ribs:
        g.px([p for p in rib if g.get(*p) in (role, "l" if role == "g" else "L")], "G" if role == "g" else "Q")
    # A couple of coconuts where the fronds meet.
    g.px([(17, 15), (18, 15), (20, 15), (21, 15), (17, 16), (21, 16)], "r")
    pal = dict(TREE, m=c["m"], M=c["M"])
    return g.render(pal, "#22401A")


# ---------------------------------------------------------------- App icon

# ---------------------------------------------------------------- Bamboo grove
#
# The panda's container: a few stalks on a grassy mound; cut bamboo stacks at the base.

GROVE_W, GROVE_H = 34, 44
GROVE = {"h": "#B6E486", "g": "#7CC04E", "G": "#5A9A34", "n": "#3E7A2A", "l": "#6CBF4A", "L": "#4C9A34",
         "d": "#9A6A3A", "D": "#7A4E26", "q": "#7DC25A", "Q": "#5FA542"}


def _stalk(g, x, top, bottom=40):
    for y in range(top, bottom + 1):
        g.px([(x, y)], "h")
        g.px([(x + 1, y)], "g")
        g.px([(x + 2, y)], "G")
        if (y - top) % 7 == 6:
            g.px([(x, y), (x + 1, y), (x + 2, y)], "n")
    g.px([(x, top - 1), (x + 1, top - 1)], "g")


def _leaf(g, x, y, d):
    """A slanted leaf from (x, y), d = 1 to the right, -1 to the left."""
    g.px([(x + d * i, y - i // 2) for i in range(1, 7)], "l")
    g.px([(x + d * i, y - i // 2 + 1) for i in range(2, 6)], "L")


def bamboo_grove(source):
    g = Grid(GROVE_W, GROVE_H)
    for x, top in ((7, 6), (15, 2), (23, 10)):
        _stalk(g, x, top)
    # Tufts at the tops plus a few leaves lower down.
    for x, y, d in ((7, 6, -1), (9, 5, 1), (15, 4, -1), (17, 4, 1), (17, 7, 1), (23, 11, -1), (25, 10, 1),
                    (7, 20, -1), (17, 18, 1), (25, 24, 1), (15, 26, -1)):
        _leaf(g, x, y, d)
    # Grassy mound.
    for y in range(38, GROVE_H - 1):
        for x in range(GROVE_W):
            if ((x + 0.5 - 17) / 16) ** 2 + ((y + 0.5 - 43) / 5.5) ** 2 <= 1:
                g.px([(x, y)], "q" if y <= 39 else "Q" if y == 40 else "D" if (x + y) % 5 == 0 else "d")
    return g.render(GROVE, "#24451A")


ICON_SIZES = [16, 32, 128, 256, 512]


def _downsample(rows, size):
    """Area-average down to `size` (alpha-weighted), for the tiny icon sizes."""
    k = len(rows) / size
    out = []
    for y in range(size):
        line = []
        for x in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            n = 0
            for yy in range(int(y * k), int((y + 1) * k)):
                for xx in range(int(x * k), int((x + 1) * k)):
                    p = rows[yy][xx]
                    n += 1
                    if p:
                        a = p[3] / 255
                        acc[0] += p[0] * a
                        acc[1] += p[1] * a
                        acc[2] += p[2] * a
                        acc[3] += a
            if acc[3] == 0:
                line.append(None)
            else:
                line.append(tuple(round(acc[i] / acc[3]) for i in range(3)) + (round(255 * acc[3] / n),))
        out.append(line)
    return out


def icon(size):
    """The Shiba on a rounded warm tile, macOS icon proportions."""
    if size < 128:
        return _downsample(icon(256), size)
    spec = DOGS["shiba"]
    g, _ = quad(spec, False)
    pet = g.render(palette_for(spec), spec["line"])
    # Crop to the sprite's pixels.
    rows = [y for y, r in enumerate(pet) if any(r)]
    cols = [x for x in range(len(pet[0])) if any(r[x] for r in pet)]
    pet = [r[cols[0]:cols[-1] + 1] for r in pet[rows[0]:rows[-1] + 1]]
    ph, pw = len(pet), len(pet[0])

    margin = size * 100 // 1024          # Apple's grid leaves ~10% around the tile
    tile = size - 2 * margin
    radius = tile * 0.225
    top, bottom = hex_rgba("#FFE7C2"), hex_rgba("#FFC98A")
    out = [[None] * size for _ in range(size)]
    for y in range(margin, margin + tile):
        t = (y - margin) / max(1, tile - 1)
        c = tuple(round(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
        for x in range(margin, margin + tile):
            dx = max(margin + radius - x - 0.5, 0, x + 0.5 - (margin + tile - radius))
            dy = max(margin + radius - y - 0.5, 0, y + 0.5 - (margin + tile - radius))
            if dx * dx + dy * dy <= radius * radius:
                out[y][x] = c
    # Whole-pixel scale so the art stays crisp.
    k = max(1, int(tile * 0.78) // pw)
    ox = (size - pw * k) // 2
    oy = (size - ph * k) // 2 + tile // 20
    for y in range(ph):
        for x in range(pw):
            p = pet[y][x]
            if p:
                for yy in range(oy + y * k, oy + (y + 1) * k):
                    out[yy][ox + x * k:ox + (x + 1) * k] = [p] * k
    return out


def bamboo():
    return text_sprite([
        "...........gg.",
        ".........gGg..",
        "hhhhhKhhhhhKhh",
        "bbbbbKbbbbbKbb",
        "sssssKsssssKss",
    ], {"h": "#C8EB8A", "b": "#8CCB52", "s": "#5E9A34", "K": "#3E6A22", "g": "#6CBF4A", "G": "#4C9A34"}, "#24451A")


BAMBOO_PAL = {"h": "#C8EB8A", "b": "#8CCB52", "s": "#5E9A34", "K": "#3E6A22", "g": "#6CBF4A", "G": "#4C9A34"}
# Ways the panda holds its bamboo, in degrees up from pointing forward. 0 is level;
# 120 leans back over its shoulder. treat.png covers the level one.
BAMBOO_HOLDS = {"up": 28, "steep": 55, "upright": 90, "shoulder": 125}


def bamboo_held(angle):
    """The bamboo at `angle` degrees, centred in its image so the paws hold the middle."""
    length = 13
    dx, dy = math.cos(math.radians(angle)), -math.sin(math.radians(angle))
    nx, ny = -dy, dx  # normal: the shine side
    cells = {}
    t = -length / 2
    while t <= length / 2:
        for off, role in ((-1, "h"), (0, "b"), (1, "s")):
            x, y = round(t * dx + off * nx), round(t * dy + off * ny)
            node = any(abs(t - n) < 0.5 for n in (-2.5, 2.5))
            if (x, y) not in cells or role == "b":
                cells[(x, y)] = "K" if node else role
        t += 0.25
    # A leaf sprouting from the top end, off to one side.
    tip = (length / 2 + 0.5)
    for i in range(1, 5):
        x = round(tip * dx + i * 0.8 * dx + (i * 0.6 + 1) * nx * -1)
        y = round(tip * dy + i * 0.8 * dy + (i * 0.6 + 1) * ny * -1)
        cells.setdefault((x, y), "g" if i < 4 else "G")
    xs = [x for x, _ in cells]; ys = [y for _, y in cells]
    r = max(max(xs), -min(xs)) + 1
    h = max(max(ys), -min(ys)) + 1
    g = Grid(2 * r + 1, 2 * h + 1)
    for (x, y), role in cells.items():
        g.px([(x + r, y + h)], role)
    return g.render(BAMBOO_PAL, "#24451A")


def orange():
    return text_sprite([
        "....kg...",
        "...kgg...",
        ".ohhooo..",
        "ohhooooo.",
        "ohooooos.",
        "oooooooS.",
        ".ooooSS..",
        "..SSSS...",
    ], {"o": "#FF9F2E", "h": "#FFD08A", "s": "#E8841A", "S": "#D06E10", "g": "#5DB04A", "k": "#3E7A2E"}, "#6A3608")


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


def animations(extra=None):
    return {**{
        "idle": {"row": 0, "count": 4, "fps": 2},
        "walk": {"row": 1, "count": 4, "fps": 8},
        "run": {"row": 1, "count": 4, "fps": 14},
        "sit": {"row": 2, "count": 1},
        "bark": {"row": 3, "count": 2, "fps": 5},
        "beg": {"row": 4, "count": 2, "fps": 1.5},
        "sleep": {"row": 5, "count": 2, "fps": 0.6},
    }, **(extra or {})}


# Pets with extra animation rows beyond the usual six.
EXTRA_ANIMATIONS = {
    "panda": {"fall": {"row": 6, "count": 3, "fps": 2, "once": True}},
}


def update_pack(pet_id, w, h, mouth, scale=2.5):
    """Points pet.json at the new sheet and lists the wardrobe."""
    path = os.path.join(ROOT, "Pets", pet_id, "pet.json")
    with open(path) as f:
        pack = json.load(f)
    old = pack["sheet"]
    pack["sheet"] = {
        "image": "sheet.png", "frameWidth": w, "frameHeight": h, "scale": scale,
        "footPadding": 1, "mouth": mouth, "animations": animations(EXTRA_ANIMATIONS.get(pet_id)), "wardrobe": WARDROBE,
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
    out["sheep"] = build(poses_sheep(), SHEEP, SHEEP["line"], W, H) + ((W, H), [26, 15])
    out["panda"] = build(poses_panda(), PANDA, PANDA["line"], W, H) + ((W, H), PANDA_PAWS)
    out["capybara"] = build(poses_simple(capybara), CAPY, CAPY["line"], W, H) + ((W, H), [28, 17])
    out["kong"] = build(poses_kong(), KONG, KONG["line"], KW, KH) + ((KW, KH), [34, 15])

    for pet_id, (pet, wears, (w, h), mouth) in out.items():
        folder = os.path.join(ROOT, "Pets", pet_id)
        write_png(os.path.join(folder, "sheet.png"), pet)
        for item, rows in wears.items():
            write_png(os.path.join(folder, f"wear-{item}.png"), rows)
        update_pack(pet_id, w, h, mouth)
        print("wrote", pet_id)

    extras = {f"Resources/Art/poop-{style}.png": poop(style) for style in POOP_STYLES}
    for pet_id, treat in (("shiba", bone), ("golden", bone), ("chihuahua", bone), ("husky", bone), ("corgi", bone), ("sheep", clover),
                          ("panda", bamboo), ("capybara", orange),
                          ("orange-tabby", fish), ("black-cat", fish), ("kong", banana)):
        extras[f"Pets/{pet_id}/treat.png"] = treat()
    for name, angle in BAMBOO_HOLDS.items():
        extras[f"Pets/panda/treat-{name}.png"] = bamboo_held(angle)
    for path, rows in extras.items():
        write_png(os.path.join(ROOT, path), rows)
        print("wrote", path)

    for source in SOURCES:
        write_png(os.path.join(ROOT, f"Resources/Art/tree-{source}.png"), tree(source))
        write_png(os.path.join(ROOT, f"Resources/Art/bamboo-{source}.png"), bamboo_grove(source))
    print("wrote trees")

    for style in BOWL_STYLES:
        for source in SOURCES:
            back, front = bowl(style, source)
            write_png(os.path.join(ROOT, f"Resources/Art/bowl-{style}-{source}-back.png"), back)
            write_png(os.path.join(ROOT, f"Resources/Art/bowl-{style}-{source}.png"), front)
            out_bowls.append([[f or b for b, f in zip(bl, fl)] for bl, fl in zip(back, front)])
        print("wrote bowl", style)

    # App icon: an .iconset for iconutil (run by scripts/bundle.sh).
    iconset = os.path.join(ROOT, "build", "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for n in ICON_SIZES:
        write_png(os.path.join(iconset, f"icon_{n}x{n}.png"), icon(n))
        write_png(os.path.join(iconset, f"icon_{n}x{n}@2x.png"), icon(n * 2))
    print("wrote build/AppIcon.iconset")

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
        tiles.append(out_bowls + [poop(style) for style in POOP_STYLES] + [bone(), fish(), banana(), clover(), bamboo(), orange()])
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
