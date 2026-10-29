#!/usr/bin/env python3
"""Generates Treatly's own pixel art (King Kong, bowls, treats) as PNGs.

Shapes are drawn as solid parts; a lighting pass adds a top-left highlight and
bottom-right shade per material, and an outline pass adds a dark edge around
the silhouette and between overlapping parts. No dependencies.

    python3 scripts/art/generate.py            # writes into Pets/ and Resources/Art/
    python3 scripts/art/generate.py --preview  # also writes build/art-preview.png
"""
import math
import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def hex_rgba(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


# material: (light, base, shade, line)
MATERIALS = {
    "fur": ("#625F6B", "#47454F", "#312F37", "#141316"),
    "furD": ("#3B3A42", "#2F2E35", "#242328", "#111013"),
    # Kong's near arm: fur colors under another name so it gets its own outline.
    "arm": ("#625F6B", "#47454F", "#312F37", "#141316"),
    "skin": ("#94817A", "#735F57", "#56463F", "#1C1513"),
    "chest": ("#6E6974", "#58545E", "#45414B", "#141316"),
    "brow": ("#26252B", "#1E1D22", "#1E1D22", "#0E0D10"),
    "eye": ("#F4F1EA", "#F4F1EA", "#F4F1EA", "#0E0D10"),
    "ink": ("#111014", "#111014", "#111014", "#111014"),
    "mouth": ("#5A2A2A", "#3E1A1C", "#2A1012", "#111014"),
    "tongue": ("#F48A9A", "#F48A9A", "#F48A9A", "#111014"),
    "earIn": ("#F2A0AE", "#E88898", "#C86C7C", "#111014"),
    "poop": ("#A87446", "#7E5230", "#5C3A20", "#2A190C"),
    # Same colors under a second name, so the outline pass draws a line
    # between stacked tiers.
    "poop2": ("#A87446", "#7E5230", "#5C3A20", "#2A190C"),
    "bone": ("#FFFDF4", "#F1E6CE", "#CDBE9C", "#6B5A44"),
    "fish": ("#B4DBF7", "#73ABDD", "#4B80B2", "#22405D"),
    "fishBelly": ("#E6F3FC", "#CBE3F5", "#A9CBE6", "#22405D"),
    "banana": ("#FFF3A6", "#F4D44D", "#CFA82C", "#6B5216"),
    "stem": ("#8A6B3A", "#6B5128", "#4E3A1C", "#2E2210"),
    "orange": ("#FFC27A", "#F2994A", "#C8702A", "#5A2E0E"),
    "blue": ("#9CC2FF", "#4A86E8", "#2F62B8", "#13305E"),
    "bowlIn": ("#3A3A44", "#2C2C34", "#22222A", "#111116"),
    "trunk": ("#C29462", "#93673A", "#6A4625", "#2E1D0E"),
    "leaf": ("#9BDB63", "#62B23A", "#408527", "#163A0D"),
    "leafD": ("#5FA03A", "#447F2A", "#2F5F1D", "#12300B"),
    "wood": ("#C9A27A", "#A27B52", "#7A5634", "#3A2614"),
    "grass": ("#8CCB55", "#5E9F37", "#447A26", "#1C3A10"),
}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.mat = [[None] * w for _ in range(h)]
        self.part = [[-1] * w for _ in range(h)]
        self.flat = [[False] * w for _ in range(h)]
        self.z = 0
        # Pixels painted after outlining (thin details like whiskers).
        self.post = []

    def _put(self, x, y, material, flat=False):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.mat[y][x] = material
            self.part[y][x] = self.z
            self.flat[y][x] = flat

    def next_part(self):
        self.z += 1

    def ellipse(self, cx, cy, rx, ry, material, flat=False):
        self.next_part()
        for y in range(self.h):
            for x in range(self.w):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1:
                    self._put(x, y, material, flat)

    def rect(self, x0, y0, x1, y1, material, flat=False):
        self.next_part()
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self._put(x, y, material, flat)

    def line(self, p0, p1, width, material, flat=False):
        """A thick segment with round ends."""
        self.next_part()
        (x0, y0), (x1, y1) = p0, p1
        r = width / 2
        for y in range(self.h):
            for x in range(self.w):
                px, py = x + 0.5, y + 0.5
                vx, vy = x1 - x0, y1 - y0
                t = 0 if vx == vy == 0 else max(0, min(1, ((px - x0) * vx + (py - y0) * vy) / (vx * vx + vy * vy)))
                qx, qy = x0 + t * vx, y0 + t * vy
                if (px - qx) ** 2 + (py - qy) ** 2 <= r * r:
                    self._put(x, y, material, flat)

    def triangle(self, a, b, c, material):
        self.next_part()
        def side(p, q, r):
            return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])
        for y in range(self.h):
            for x in range(self.w):
                pt = (x + 0.5, y + 0.5)
                d1, d2, d3 = side(pt, a, b), side(pt, b, c), side(pt, c, a)
                if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
                    self._put(x, y, material)

    def pixels(self, points, material):
        self.next_part()
        for x, y in points:
            self._put(x, y, material, True)

    def render(self, outline=True):
        """Returns rows of RGBA tuples (None = transparent).

        Each part is shaded as a rounded form lit from the upper left: the
        normal comes from the gradient of the part's blurred coverage, so
        ellipses read as balls and lines as tubes. Outlines use the material's
        line color, lightened on the lit (top and left) side.
        """
        w, h = self.w, self.h
        mat, part = self.mat, self.part

        def m(x, y):
            return mat[y][x] if 0 <= x < w and 0 <= y < h else None

        # Coverage of each pixel's material, box-blurred (radius 2). Shading
        # a whole material region at once keeps a body made of several
        # ellipses smooth instead of lumpy.
        r = 2
        bounds = {}
        for y in range(h):
            for x in range(w):
                k = mat[y][x]
                if k is None:
                    continue
                t, bt = bounds.get(k, (y, y))
                bounds[k] = (min(t, y), max(bt, y))

        def coverage(x, y, k):
            total = 0
            for yy in range(y - r, y + r + 1):
                for xx in range(x - r, x + r + 1):
                    if 0 <= xx < w and 0 <= yy < h and mat[yy][xx] == k:
                        total += 1
            return total / ((2 * r + 1) ** 2)

        lx, ly = -0.55, -0.83  # toward the light: up and to the left
        out = [[None] * w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                k = mat[y][x]
                if k is None:
                    continue
                light, base, shade, line = MATERIALS[k]
                if self.flat[y][x]:
                    out[y][x] = hex_rgba(base)
                    continue
                behind = any(
                    0 <= nx < w and 0 <= ny < h and mat[ny][nx] not in (None, k) and part[ny][nx] > part[y][x] and not self.flat[ny][nx]
                    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))
                )
                if behind and outline:
                    out[y][x] = _mix(line, shade, 0.25)
                    continue
                gx = coverage(x + 1, y, k) - coverage(x - 1, y, k)
                gy = coverage(x, y + 1, k) - coverage(x, y - 1, k)
                lit = -(gx * lx + gy * ly)  # outward normal . light
                top, bottom = bounds[k]
                ty = (y - top) / max(1, bottom - top)
                i = 2.6 * lit - 0.28 * (ty - 0.35)
                if i >= 0.5 and lit > 0.15:
                    out[y][x] = _mix(light, "#FFFFFF", 0.35)
                elif i >= 0.16:
                    out[y][x] = hex_rgba(light)
                elif i >= -0.1:
                    out[y][x] = hex_rgba(base)
                elif i >= -0.32:
                    out[y][x] = _mix(base, shade, 0.55)
                else:
                    out[y][x] = hex_rgba(shade)
        if outline:
            edge = [[None] * w for _ in range(h)]
            for y in range(h):
                for x in range(w):
                    if mat[y][x] is not None:
                        continue
                    # Inside neighbor below or to the right means this is the
                    # lit top/left side of the shape: soften the line there.
                    for nx, ny, lit_side in ((x, y + 1, True), (x + 1, y, True), (x, y - 1, False), (x - 1, y, False)):
                        k = m(nx, ny)
                        if k is not None:
                            line, shade = MATERIALS[k][3], MATERIALS[k][2]
                            edge[y][x] = _mix(line, shade, 0.4) if lit_side else hex_rgba(line)
                            break
            for y in range(h):
                for x in range(w):
                    if edge[y][x]:
                        out[y][x] = edge[y][x]
        for x, y, color in self.post:
            if 0 <= int(x) < w and 0 <= int(y) < h:
                out[int(y)][int(x)] = hex_rgba(color)
        return out


def _mix(a, b, t):
    ca, cb = hex_rgba(a), hex_rgba(b)
    return tuple(round(ca[i] * (1 - t) + cb[i] * t) for i in range(3)) + (255,)


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


# ---------------------------------------------------------------- King Kong

KW, KH = 52, 42
GROUND = 38  # bottom row of the feet; rows below stay empty


def kong(arm=0.0, leg=0.0, bob=0, pound=None, mouth=False, breathe=0.0):
    """Side view, knuckle-walking, facing right.
    arm/leg swing the near limbs forward (+) or back (-); the far ones mirror.
    pound: None, "near" or "far" raises that fist to the chest.
    """
    c = Canvas(KW, KH)
    g = GROUND
    # Far limbs (darker, behind the body).
    c.line((15, 26 + bob), (13 - leg * 2, g - 2), 4.5, "furD")
    c.ellipse(12.5 - leg * 2, g - 0.5, 3.5, 1.8, "furD")
    if pound == "far":
        c.line((30, 19 + bob), (34, 25 + bob), 4.5, "furD")
    else:
        c.line((30, 19 + bob), (33 - arm * 3, g - 2), 4.5, "furD")
        c.ellipse(34 - arm * 3, g - 0.5, 3.2, 1.8, "furD")
    # Body: rump, torso and the big shoulder hump.
    c.ellipse(16, 25 + bob, 8, 7, "fur")
    c.ellipse(23, 21 + bob, 11.5 + breathe, 9 + breathe, "fur")
    c.ellipse(29, 16 + bob, 8, 7, "fur")
    c.ellipse(30, 24 + bob, 4.5, 5, "chest")
    # Near leg.
    c.line((17, 27 + bob), (16 + leg * 2, g - 2), 5.5, "fur")
    c.ellipse(17 + leg * 2, g - 0.5, 4, 2, "skin")
    # Head: crest, skull, face, muzzle.
    c.ellipse(36, 10 + bob, 4.5, 3.5, "fur")
    c.ellipse(38, 14 + bob, 6.5, 6, "fur")
    c.ellipse(41, 16 + bob, 4.5, 4.5, "skin")
    c.ellipse(43, 18.5 + bob, 3.5, 3, "skin")
    c.line((37, 13 + bob), (45, 13 + bob), 2, "brow")
    c.pixels([(41, 14 + bob)], "eye")
    c.pixels([(42, 14 + bob)], "ink")
    c.pixels([(45, 17 + bob), (46, 17 + bob)], "ink")
    if mouth:
        c.ellipse(43.5, 20.5 + bob, 2.2, 1.6, "mouth", flat=True)
    else:
        c.pixels([(42, 20 + bob), (43, 20 + bob), (44, 20 + bob)], "ink")
    # Near arm in front of everything.
    if pound == "near":
        c.line((32, 18 + bob), (35, 24 + bob), 5.5, "arm")
        c.ellipse(35.5, 25 + bob, 3, 2.6, "skin")
    else:
        c.line((32, 18 + bob), (35 + arm * 3, g - 2), 5.5, "arm")
        c.ellipse(36 + arm * 3, g - 0.5, 3.6, 2, "skin")
    return c.render()


def kong_sleeping(breathe=0.0):
    c = Canvas(KW, KH)
    g = GROUND
    c.ellipse(21, g - 6, 14, 7 + breathe, "fur")
    c.ellipse(13, g - 4, 6, 4.5, "fur")
    c.ellipse(36, g - 5, 6.5, 5.5, "fur")
    c.ellipse(39, g - 3.5, 4, 3.5, "skin")
    c.line((35, g - 7), (42, g - 7), 2, "brow")
    c.pixels([(38, g - 5), (39, g - 5), (40, g - 5)], "ink")
    c.line((25, g - 4), (33, g - 1), 5, "fur")
    c.ellipse(33.5, g - 0.5, 3.2, 1.8, "skin")
    return c.render()


def kong_sitting():
    """Upright sit, arms resting on the ground in front."""
    c = Canvas(KW, KH)
    g = GROUND
    c.line((30, 22), (33, g - 2), 4.5, "furD")
    c.ellipse(34, g - 0.5, 3, 1.8, "furD")
    c.ellipse(21, g - 7, 9, 7, "fur")
    c.ellipse(24, 22, 9, 11, "fur")
    c.ellipse(28, 24, 4.5, 6, "chest")
    c.ellipse(22, g - 1, 6, 2, "skin")
    c.ellipse(28, 9, 4.5, 3.5, "fur")
    c.ellipse(30, 13, 6.5, 6, "fur")
    c.ellipse(33, 15, 4.5, 4.5, "skin")
    c.ellipse(35, 17.5, 3.5, 3, "skin")
    c.line((29, 12), (37, 12), 2, "brow")
    c.pixels([(33, 13)], "eye")
    c.pixels([(34, 13)], "ink")
    c.pixels([(37, 16), (38, 16)], "ink")
    c.pixels([(34, 19), (35, 19), (36, 19)], "ink")
    c.line((30, 19), (35, g - 2), 5.5, "fur")
    c.ellipse(36, g - 0.5, 3.6, 2, "skin")
    return c.render()


def kong_sheet():
    walk = [kong(arm=a, leg=-a, bob=b) for a, b in ((1, 0), (0, -1), (-1, 0), (0, -1))]
    idle = [kong(breathe=0), kong(breathe=0.4), kong(breathe=0.6), kong(breathe=0.4)]
    bark = [kong(pound="near", mouth=True), kong(pound="far", mouth=True, bob=-1)]
    sit = [kong_sitting()]
    sleep = [kong_sleeping(0), kong_sleeping(0.5)]
    return sheet([idle, walk, bark, sit, sleep])


# ---------------------------------------------------------------- Dogs
#
# Side view, facing right. One function draws every pose; breeds differ in
# palette, ears, tail and markings.

DW, DH = 44, 34
DGROUND = 31

BREEDS = {
    "shiba": {
        "fur": ("#F4A866", "#DC8440", "#B4642C", "#3B2213"),
        "furD": ("#C46E30", "#A85C26", "#87471B", "#2E1A0C"),
        "mark": ("#FFFFFF", "#FBF3E8", "#E4D5C2", "#5A4636"),
        "collar": ("#F26464", "#D93A3A", "#A82424", "#4A0E0E"),
        "ears": "pointy", "tail": "curl", "marks": True,
    },
    "golden": {
        "fur": ("#F8D493", "#E6B064", "#C48E44", "#4A3014"),
        "furD": ("#D49E54", "#BA8642", "#986A32", "#3A250F"),
        "mark": ("#FFF4DC", "#F6E2B8", "#E0C48E", "#5A4020"),
        "collar": ("#62D4CC", "#2FB0A8", "#1E8A84", "#0C3A38"),
        "ears": "floppy", "tail": "plume", "marks": False,
    },
    "chihuahua": {
        "fur": ("#F6D3A6", "#DEB07C", "#BC8C58", "#4A2E14"),
        "furD": ("#C99A64", "#B08250", "#8E663C", "#3A2410"),
        "mark": ("#FFF6E8", "#F8E8D0", "#E2CCAA", "#5A4630"),
        "collar": ("#FF8AC8", "#F25AA8", "#C23A84", "#4A0E30"),
        "ears": "big", "tail": "thin", "marks": True,
    },
}


def _dog_materials(breed):
    b = BREEDS[breed]
    for key in ("fur", "furD", "mark", "collar"):
        MATERIALS[f"{breed}-{key}"] = b[key]
    return lambda key: f"{breed}-{key}"


def dog(breed, pose="stand", swing=0, bob=0, mouth=False, tilt=0):
    """pose: stand, sit, sleep. swing moves the legs for walking."""
    b = BREEDS[breed]
    m = _dog_materials(breed)
    c = Canvas(DW, DH)
    g = DGROUND

    if pose == "sleep":
        # Lying down: low body, head raised a little on the front paws,
        # tail curled in at the back, eyes closed.
        paw = m("mark") if b["marks"] else m("fur")
        c.ellipse(7.5, g - 8, 3.5, 3.5, m("mark") if b["marks"] else m("fur"))
        c.ellipse(21, g - 5, 11, 5.5, m("fur"))
        c.ellipse(12, g - 6.5, 6.5, 6.5, m("fur"))
        if b["marks"]:
            c.ellipse(22, g - 0.8, 8, 1.4, m("mark"))
        c.line((28, g - 6), (33, g - 2), 4, m("fur"))
        c.ellipse(36, g - 0.5, 4, 1.4, paw)
        hx, hy = 34, g - 9
        if b["ears"] == "pointy":
            c.triangle((hx - 4.5, hy - 2), (hx - 3, hy - 7), (hx - 0.5, hy - 3), m("furD"))
        c.ellipse(hx, hy, 5, 4.5, m("fur"))
        c.ellipse(hx + 5, hy + 2, 3.4, 2.3, m("mark") if b["marks"] else m("fur"))
        if b["marks"]:
            c.ellipse(hx + 2, hy + 3, 2.6, 1.7, m("mark"))
        if b["ears"] in ("pointy", "big"):
            c.triangle((hx - 3, hy - 3), (hx - 1, hy - 8), (hx + 1.5, hy - 3.5), m("fur"))
        else:
            c.ellipse(hx - 2.5, hy + 1.5, 2.2, 3.8, m("furD"))
        c.pixels([(hx + 1, hy), (hx + 2, hy), (hx + 3, hy - 1)], "ink")
        c.pixels([(hx + 8, hy + 1), (hx + 8, hy + 2)], "ink")
        return c.render()

    sit = pose == "sit"
    hx, hy = (33, 7 + tilt) if sit else (35, 10 + bob)  # head center
    by = bob

    # Tail, behind everything.
    if b["tail"] == "curl":
        tx, ty = (10, 20) if sit else (10, 16 + by)
        c.line((tx + 2, ty + 2), (tx - 2, ty - 3), 3.6, m("fur"))
        c.line((tx - 2, ty - 3), (tx + 2, ty - 6), 3.6, m("fur"))
        c.line((tx + 2, ty - 6), (tx + 4, ty - 3), 3, m("mark") if b["marks"] else m("fur"))
    elif b["tail"] == "thin":
        tx, ty = (11, 21) if sit else (10, 17 + by)
        c.line((tx + 1, ty + 1), (tx - 3, ty - 3), 2.2, m("fur"))
        c.line((tx - 3, ty - 3), (tx - 1, ty - 7), 2.2, m("fur"))
    else:
        tx, ty = (11, 22) if sit else (10, 18 + by)
        c.line((tx + 1, ty), (tx - 6, ty - 3), 4, m("fur"))
        c.line((tx - 6, ty - 3), (tx - 9, ty + 1), 3, m("fur"))
        c.line((tx - 4, ty), (tx - 8, ty + 2), 2, m("mark"))

    if sit:
        # Far front leg, haunches, body sloping up to the chest.
        c.line((29, 20), (29, g - 1), 3.2, m("furD"))
        c.ellipse(15, g - 6, 7, 6, m("fur"))
        c.ellipse(21, 20, 8, 6.5, m("fur"))
        c.ellipse(28, 17, 5.5, 6.5, m("fur"))
        if b["marks"]:
            c.ellipse(31, 19, 3, 5, m("mark"))
        c.ellipse(19, g - 1, 4, 1.6, m("mark") if b["marks"] else m("fur"))
        c.line((31, 20), (31, g - 1), 3.4, m("fur"))
        c.ellipse(32, g - 0.5, 2.4, 1.3, m("mark") if b["marks"] else m("fur"))
        neck = ((29, 14), (hx - 1, hy + 3))
    else:
        # Far legs (darker), body, near legs.
        c.line((13, 22 + by), (12 - swing, g - 1), 3.2, m("furD"))
        c.line((29, 22 + by), (30 + swing, g - 1), 3.2, m("furD"))
        c.ellipse(20, 19 + by, 11, 5.5, m("fur"))
        c.ellipse(11, 19 + by, 5, 5.5, m("fur"))
        c.ellipse(29, 18 + by, 5, 5.8, m("fur"))
        if b["marks"]:
            c.ellipse(22, 23 + by, 7, 1.6, m("mark"))
            c.ellipse(32, 20 + by, 2.6, 4, m("mark"))
        c.ellipse(13, 21 + by, 4.5, 4.5, m("fur"))
        c.line((14, 23 + by), (14 + swing, g - 1), 3.6, m("fur"))
        c.line((30, 22 + by), (31 - swing, g - 1), 3.4, m("fur"))
        paw = m("mark") if b["marks"] else m("fur")
        c.ellipse(15 + swing, g - 0.5, 2.4, 1.3, paw)
        c.ellipse(32 - swing, g - 0.5, 2.4, 1.3, paw)
        neck = ((30, 16 + by), (hx - 1, hy + 3))

    c.line(neck[0], neck[1], 6.5, m("fur"))
    c.line((neck[0][0] + 1, neck[0][1] + 1), (neck[1][0] + 1, neck[1][1] + 2), 1.6, m("collar"))

    # Back ear, head, snout, front ear.
    if b["ears"] == "pointy":
        c.triangle((hx - 4.5, hy - 2), (hx - 3, hy - 8), (hx - 0.5, hy - 3), m("furD"))
    elif b["ears"] == "big":
        c.triangle((hx - 6, hy - 1), (hx - 7, hy - 10), (hx - 1, hy - 3), m("furD"))
    c.ellipse(hx, hy, 5.5, 5, m("fur"))
    c.ellipse(hx + 5.5, hy + 2, 3.6, 2.6 if not mouth else 2.2, m("mark") if b["marks"] else m("fur"))
    if b["marks"]:
        c.ellipse(hx + 2, hy + 3, 3, 2, m("mark"))
    if b["ears"] == "pointy":
        c.triangle((hx - 3, hy - 3), (hx - 1, hy - 9), (hx + 1.5, hy - 3.5), m("fur"))
        c.pixels([(hx - 1, hy - 5), (hx - 1, hy - 6)], "mouth")
    elif b["ears"] == "big":
        c.triangle((hx - 4, hy - 2), (hx - 3, hy - 12), (hx + 2, hy - 3.5), m("fur"))
        c.pixels([(hx - 2, hy - 6), (hx - 2, hy - 7), (hx - 1, hy - 5), (hx - 2, hy - 8)], "earIn")
    else:
        c.ellipse(hx - 2.5, hy + 1.5, 2.4, 4.4, m("furD"))

    # Eye with a highlight, nose, mouth.
    c.pixels([(hx + 2, hy - 1), (hx + 3, hy - 1), (hx + 2, hy), (hx + 3, hy)], "ink")
    c.pixels([(hx + 2, hy - 1)], "eye")
    c.pixels([(hx + 8, hy), (hx + 9, hy), (hx + 8, hy + 1)], "ink")
    if mouth:
        c.ellipse(hx + 6, hy + 4.5, 2, 1.4, "mouth", flat=True)
        c.pixels([(hx + 6, hy + 5)], "tongue")
    else:
        c.pixels([(hx + 6, hy + 4), (hx + 7, hy + 4)], "ink")
    return c.render()


def dog_sheet(breed):
    walk = [dog(breed, swing=s, bob=b) for s, b in ((2, 0), (0, -1), (-2, 0), (0, -1))]
    idle = [dog(breed), dog(breed), dog(breed, bob=1), dog(breed)]
    sit = [dog(breed, "sit")]
    bark = [dog(breed, "sit", mouth=True), dog(breed, "sit", tilt=-1)]
    beg = [dog(breed, "sit", tilt=1), dog(breed, "sit", tilt=2)]
    sleep = [dog(breed, "sleep"), dog(breed, "sleep")]
    return sheet([idle, walk, sit, bark, beg, sleep])


# ---------------------------------------------------------------- Cats
#
# Same frame size and poses as the dogs, slimmer and with a long tail.

CATS = {
    "orange-tabby": {
        "fur": ("#F8AC62", "#E8873A", "#C0662A", "#4A2A10"),
        "furD": ("#CA7230", "#AE5E24", "#8C4A1A", "#3A2010"),
        "mark": ("#FFF4E2", "#F8E0C2", "#E2C49C", "#5A4020"),
        "stripe": "#B25A1A", "iris": "#7CC85A", "nose": "#F08A9A", "whisker": "#FFF4E2",
    },
    "black-cat": {
        "fur": ("#4C4C5A", "#32323C", "#24242C", "#0C0C10"),
        "furD": ("#2C2C35", "#23232B", "#19191F", "#08080B"),
        "mark": None,
        "stripe": None, "iris": "#F5D547", "nose": "#7A6672", "whisker": "#9A9AA8",
    },
}


def _cat_materials(name):
    c = CATS[name]
    for key in ("fur", "furD"):
        MATERIALS[f"{name}-{key}"] = c[key]
    MATERIALS[f"{name}-mark"] = c["mark"] or c["fur"]
    for key in ("stripe", "iris", "nose", "whisker"):
        if c[key]:
            MATERIALS[f"{name}-{key}"] = (c[key],) * 3 + ("#111014",)
    MATERIALS["earIn"] = ("#F2A0AE", "#E88898", "#C86C7C", "#111014")
    return lambda key: f"{name}-{key}"


def _cat_head(c, m, cat, hx, hy, mouth=False, closed=False):
    c.triangle((hx - 4.5, hy - 1.5), (hx - 4, hy - 8.5), (hx - 0.5, hy - 3), m("furD"))
    c.ellipse(hx, hy, 5, 4.5, m("fur"))
    c.ellipse(hx + 4, hy + 1.8, 2.6, 2, m("mark"))
    c.triangle((hx - 2, hy - 3), (hx, hy - 9.5), (hx + 3, hy - 3), m("fur"))
    c.pixels([(hx, hy - 6), (hx, hy - 5), (hx + 1, hy - 5)], "earIn")
    if closed:
        c.pixels([(hx + 1, hy), (hx + 2, hy), (hx + 3, hy - 1)], "ink")
    else:
        c.pixels([(hx + 1, hy - 1), (hx + 1, hy)], m("iris"))
        c.pixels([(hx + 2, hy - 1), (hx + 2, hy)], "ink")
    c.pixels([(hx + 6, hy + 1)], m("nose"))
    if mouth:
        c.ellipse(hx + 4.5, hy + 4, 1.6, 1.2, "mouth", flat=True)
    else:
        c.pixels([(hx + 5, hy + 3)], "ink")
    for x, y in ((hx + 7, hy + 2), (hx + 8, hy + 1), (hx + 7, hy + 3), (hx + 8, hy + 4)):
        c.post.append((x, y, cat["whisker"]))


def cat(name, pose="stand", swing=0, bob=0, mouth=False, tilt=0):
    k = CATS[name]
    m = _cat_materials(name)
    c = Canvas(DW, DH)
    g = DGROUND

    if pose == "sleep":
        # Curled up with the tail wrapped round the front.
        c.ellipse(20, g - 5, 11, 5.5, m("fur"))
        c.ellipse(12, g - 6, 5.5, 5.5, m("fur"))
        if k["stripe"]:
            for x in (13, 17, 21, 25):
                c.line((x, g - 10), (x - 1, g - 8), 1.2, m("stripe"), flat=True)
        _cat_head(c, m, k, 32, g - 8, closed=True)
        c.line((9, g - 2), (36, g - 1), 2.8, m("fur"))
        return c.render()

    if pose == "sit":
        hx, hy = 31, 8 + tilt
        c.line((10, g - 2), (16, g), 2.8, m("fur"))
        c.line((16, g), (26, g - 1), 2.8, m("fur"))
        c.line((24, 20), (24, g - 1), 2.4, m("furD"))
        c.ellipse(15, g - 5.5, 6, 5.5, m("fur"))
        c.ellipse(20, 19, 6.5, 7.5, m("fur"))
        c.ellipse(24, 16, 4.5, 6, m("fur"))
        if k["mark"]:
            c.ellipse(26.5, 18, 2.2, 4.5, m("mark"))
        if k["stripe"]:
            for y in (15, 19, 23):
                c.line((15, y), (17, y + 1), 1.2, m("stripe"), flat=True)
        c.line((26, 20), (26, g - 1), 2.6, m("fur"))
        c.ellipse(27, g - 0.5, 2, 1.2, m("mark"))
        c.line((24, 14), (hx - 1, hy + 3), 4.5, m("fur"))
        _cat_head(c, m, k, hx, hy, mouth=mouth)
        return c.render()

    hx, hy = 34, 11 + bob
    by = bob
    # Tail: up from the rump in an S-curve.
    for a, b in zip(_bezier((9, 18 + by), (1, 15 + by), (4, 5 + by), 10), _bezier((9, 18 + by), (1, 15 + by), (4, 5 + by), 10)[1:]):
        c.line(a, b, 2.8, m("fur"))
    c.line((4, 5 + by), (7, 3 + by), 2.4, m("fur"))
    # Far legs, body, near legs.
    c.line((12, 22 + by), (11 - swing, g - 1), 2.6, m("furD"))
    c.line((28, 22 + by), (29 + swing, g - 1), 2.4, m("furD"))
    c.ellipse(19, 19 + by, 10, 4.5, m("fur"))
    c.ellipse(11, 19 + by, 4.5, 4.8, m("fur"))
    c.ellipse(27, 19 + by, 4.2, 4.6, m("fur"))
    if k["mark"]:
        c.ellipse(21, 22.5 + by, 6, 1.4, m("mark"))
    if k["stripe"]:
        for x in (11, 15, 19, 23):
            c.line((x, 15 + by), (x - 1, 17.5 + by), 1.2, m("stripe"), flat=True)
    c.ellipse(12, 20.5 + by, 4, 4, m("fur"))
    c.line((13, 23 + by), (13 + swing, g - 1), 2.8, m("fur"))
    c.line((29, 22 + by), (30 - swing, g - 1), 2.6, m("fur"))
    c.ellipse(14 + swing, g - 0.5, 2, 1.2, m("mark"))
    c.ellipse(31 - swing, g - 0.5, 2, 1.2, m("mark"))
    c.line((28, 17 + by), (hx - 1, hy + 2), 4.8, m("fur"))
    _cat_head(c, m, k, hx, hy, mouth=mouth)
    return c.render()


def cat_sheet(name):
    walk = [cat(name, swing=s, bob=b) for s, b in ((2, 0), (0, -1), (-2, 0), (0, -1))]
    idle = [cat(name), cat(name), cat(name, bob=1), cat(name)]
    sit = [cat(name, "sit")]
    meow = [cat(name, "sit", mouth=True), cat(name, "sit", tilt=-1)]
    beg = [cat(name, "sit", tilt=1), cat(name, "sit", tilt=2)]
    sleep = [cat(name, "sleep"), cat(name, "sleep")]
    return sheet([idle, walk, sit, meow, beg, sleep])


# ---------------------------------------------------------------- Treats

def bone():
    c = Canvas(18, 10)
    for cx in (3, 15):
        c.ellipse(cx, 3, 2.6, 2.4, "bone")
        c.ellipse(cx, 7, 2.6, 2.4, "bone")
    c.rect(3, 3, 15, 6, "bone")
    return c.render()


def fish():
    c = Canvas(18, 10)
    c.triangle((0.5, 0.5), (0.5, 9.5), (6, 5), "fish")
    c.ellipse(10, 5, 6.5, 3.6, "fish")
    c.ellipse(10.5, 6.6, 4.5, 1.6, "fishBelly")
    c.pixels([(13, 3)], "ink")
    return c.render()


def banana():
    c = Canvas(18, 10)
    pts = [(2 + 13 * t, 3 + 4.5 * math.sin(math.pi * t)) for t in [i / 12 for i in range(13)]]
    for a, b in zip(pts, pts[1:]):
        c.line(a, b, 3.6, "banana")
    c.line((15.5, 3.5), (16.5, 1.5), 1.6, "stem")
    c.pixels([(1, 2), (2, 3)], "stem")
    return c.render()


def poop():
    """The classic three-tier swirl."""
    c = Canvas(16, 13)
    c.ellipse(8, 10, 7, 2.6, "poop")
    c.ellipse(8, 7, 5.2, 2.3, "poop2")
    c.ellipse(8.5, 4.3, 3.4, 2, "poop")
    c.line((9.5, 3), (11, 1), 1.8, "poop2")
    out = c.render()
    shine = hex_rgba("#D6A472")
    for x, y in ((4, 9), (5, 6), (7, 3)):
        out[y][x] = shine
    return out


# ---------------------------------------------------------------- Bowls
#
# A round ceramic pet bowl, shaded like a cylinder lit from the upper left.
# It comes in two layers so treats can sit inside: the back (far rim and the
# cream interior) and the front (near rim lip, body, paw decal).

BW, BH = 40, 22
BCX = 20
RIM_CY, RIM_RX, RIM_RY = 6.0, 19.0, 5.0
IN_CY, IN_RX, IN_RY = 6.4, 15.6, 3.3
BASE_Y = 19

RAMPS = {
    "orange": ["#5E2A0B", "#9E4A16", "#D06A24", "#EE8A3A", "#FFB264", "#FFE2BC"],
    "blue": ["#0F2552", "#1C4594", "#2C66CC", "#4686EE", "#80B0FF", "#D6E6FF"],
}
INTERIOR = ["#C9B697", "#E2D3B8", "#F4EADA", "#FFF8EC"]


def _inside(x, y, cy, rx, ry):
    dx, dy = (x + 0.5 - BCX) / rx, (y + 0.5 - cy) / ry
    return dx * dx + dy * dy <= 1


def _half_width(y):
    """Body half-width at row y: wide under the rim, tapering to the base."""
    t = (y + 0.5 - RIM_CY) / (BASE_Y + 1 - RIM_CY)
    return RIM_RX - 0.6 - 4.5 * t * t


def _in_body(x, y):
    if y + 0.5 < RIM_CY or y > BASE_Y + 1:
        return False
    hw = _half_width(y)
    if y >= BASE_Y:  # rounded foot
        hw -= (y - BASE_Y + 1) * 1.5
    return abs(x + 0.5 - BCX) <= hw


def _cyl(ramp, x, lift=0):
    """Cylinder shading across the bowl: bright left of center, dark edges."""
    u = (x + 0.5 - BCX) / RIM_RX
    light = 1 - min(1, abs(u + 0.3) / 1.05) ** 1.6
    i = 1 + round(light * 3) + lift
    return ramp[max(0, min(len(ramp) - 2, i))]


def _blend(rgba, hex_color, amount):
    other = hex_rgba(hex_color)
    return tuple(round(a * (1 - amount) + b * amount) for a, b in zip(rgba[:3], other[:3])) + (255,)


def bowl_layers(color):
    ramp = RAMPS[color]
    back = [[None] * BW for _ in range(BH)]
    front = [[None] * BW for _ in range(BH)]
    solid = [[False] * BW for _ in range(BH)]

    for y in range(BH):
        for x in range(BW):
            rim = _inside(x, y, RIM_CY, RIM_RX, RIM_RY)
            hole = _inside(x, y, IN_CY, IN_RX, IN_RY)
            near_half = y + 0.5 >= RIM_CY
            if rim and hole:
                # Cream interior; the far wall is shadowed by the rim.
                depth = (y + 0.5 - (IN_CY - IN_RY)) / (2 * IN_RY)
                shade = 0 if depth < 0.25 else 1 if depth < 0.45 else 2 if depth < 0.8 else 1
                if (x + 0.5 - BCX) / IN_RX < -0.55 and 0.3 < depth < 0.8:
                    shade = 3
                back[y][x] = hex_rgba(INTERIOR[shade])
                solid[y][x] = True
            elif rim:
                # The rim ring: the near half is the bright lip.
                c = hex_rgba(_cyl(ramp, x, lift=1))
                if not _inside(x, y - 1, RIM_CY, RIM_RX, RIM_RY) and (x + 0.5 - BCX) < 4:
                    c = hex_rgba(ramp[5])
                elif _inside(x, y - 1, IN_CY, IN_RX, IN_RY) or _inside(x, y + 1, IN_CY, IN_RX, IN_RY):
                    c = hex_rgba(ramp[2])  # thin edge where the lip meets the inside
                (front if near_half else back)[y][x] = c
                solid[y][x] = True
            elif _in_body(x, y):
                c = hex_rgba(_cyl(ramp, x))
                if y >= BASE_Y - 1:
                    c = hex_rgba(ramp[1])
                elif y <= RIM_CY + RIM_RY:
                    c = _blend(c, ramp[0], 0.18)  # shadow under the lip
                # Glossy streak on the left.
                u = (x + 0.5 - BCX) / RIM_RX
                if -0.62 < u < -0.5 and RIM_CY + RIM_RY + 1 <= y <= BASE_Y - 3:
                    c = hex_rgba(ramp[5])
                front[y][x] = c
                solid[y][x] = True

    # Paw print decal in the middle of the body.
    paw = {(19, 14), (20, 14), (21, 14), (18, 15), (19, 15), (20, 15), (21, 15), (22, 15), (19, 16), (20, 16), (21, 16),
           (17, 12), (19, 11), (21, 11), (23, 12)}
    for x, y in paw:
        if front[y][x]:
            front[y][x] = _blend(front[y][x], "#FFFFFF", 0.6)

    # Outline around the whole silhouette, split between the layers.
    line = hex_rgba(ramp[0])
    for y in range(BH):
        for x in range(BW):
            if solid[y][x]:
                continue
            if any(0 <= nx < BW and 0 <= ny < BH and solid[ny][nx] for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))):
                (front if y + 0.5 >= RIM_CY else back)[y][x] = line
    return back, front


def bowl_front(color):
    return bowl_layers(color)[1]


def bowl_preview(color):
    back, front = bowl_layers(color)
    return [[f or b for b, f in zip(br, fr)] for br, fr in zip(back, front)]


# ---------------------------------------------------------------- Banana tree
#
# King Kong's version of a bowl: a palm with the banana bunch hanging under
# the crown (the app draws one banana per task) and a signpost in the
# source's color.

TW, TH = 46, 62
CROWN = (25, 17)
# Where bananas hang, in tree pixels from the top-left; the app uses these.
TREE_HANGS = [(21, 21), (28, 21), (24, 24), (18, 25), (31, 25), (25, 28)]


def _bezier(p0, p1, p2, steps=14):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / steps for i in range(steps + 1)]]


def _frond(c, end, control, material, thick=4.2):
    pts = _bezier(CROWN, control, end)
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        w = thick * (1 - i / len(pts)) + 1.2
        c.line(a, b, w, material)


def tree(sign):
    c = Canvas(TW, TH)
    # Back fronds first (darker), then the trunk, then front fronds.
    _frond(c, (5, 13), (10, 1), "leafD", 3.6)
    _frond(c, (41, 12), (37, 0), "leafD", 3.6)
    trunk = _bezier((19, TH - 3), (14, 38), (CROWN[0], CROWN[1] + 2), 18)
    for i, (a, b) in enumerate(zip(trunk, trunk[1:])):
        c.line(a, b, 6.2 - 2.4 * i / len(trunk), "trunk")
    _frond(c, (1, 24), (6, 3), "leaf")
    _frond(c, (45, 23), (40, 3), "leaf")
    _frond(c, (6, 33), (8, 13), "leaf", 3.4)
    _frond(c, (42, 34), (41, 13), "leaf", 3.4)
    _frond(c, (14, 9), (17, 0), "leaf", 3.2)
    _frond(c, (35, 8), (32, 0), "leaf", 3.2)
    c.ellipse(CROWN[0], CROWN[1] + 1, 3.2, 2.6, "trunk")
    # Grass tuft and the signpost.
    c.ellipse(19, TH - 2.5, 7, 1.8, "grass")
    c.rect(35, TH - 12, 36, TH - 2, "wood")
    c.rect(30, TH - 16, 41, TH - 11, sign)
    out = c.render()
    # Trunk rings: darken every third row of trunk pixels.
    ring = hex_rgba(MATERIALS["trunk"][2])
    for y in range(CROWN[1] + 6, TH - 3, 3):
        for x in range(TW):
            if c.mat[y][x] == "trunk" and out[y][x] not in (None, hex_rgba(MATERIALS["trunk"][3])):
                out[y][x] = ring
    return out


# ---------------------------------------------------------------- Main

def upscale(rows, k):
    return [[p for p in row for _ in range(k)] for row in rows for _ in range(k)]


def main():
    out = {
        "Pets/kong/sheet.png": kong_sheet(),
        "Pets/kong/treat.png": banana(),
        "Pets/shiba/treat.png": bone(),
        "Pets/shiba/sheet.png": dog_sheet("shiba"),
        "Pets/golden/sheet.png": dog_sheet("golden"),
        "Pets/chihuahua/sheet.png": dog_sheet("chihuahua"),
        "Pets/chihuahua/treat.png": bone(),
        "Pets/orange-tabby/sheet.png": cat_sheet("orange-tabby"),
        "Pets/black-cat/sheet.png": cat_sheet("black-cat"),
        "Pets/golden/treat.png": bone(),
        "Pets/orange-tabby/treat.png": fish(),
        "Pets/black-cat/treat.png": fish(),
        "Resources/Art/bowl-appleReminders-back.png": bowl_layers("orange")[0],
        "Resources/Art/bowl-appleReminders.png": bowl_front("orange"),
        "Resources/Art/bowl-googleTasks-back.png": bowl_layers("blue")[0],
        "Resources/Art/bowl-googleTasks.png": bowl_front("blue"),
        "Resources/Art/poop.png": poop(),
        "Resources/Art/tree-appleReminders.png": tree("orange"),
        "Resources/Art/tree-googleTasks.png": tree("blue"),
    }
    for path, rows in out.items():
        write_png(os.path.join(ROOT, path), rows)
        print("wrote", path)

    if "--preview" in sys.argv:
        bg = (236, 236, 240, 255)
        t = tree("orange")
        for hx, hy in TREE_HANGS:
            b = [row[::2] for row in banana()[::2]]
            for y, row in enumerate(b):
                for x, p in enumerate(row):
                    if p and 0 <= hy - 2 + y < TH and 0 <= hx - 4 + x < TW:
                        t[hy - 2 + y][hx - 4 + x] = p
        items = [poop(), dog_sheet("shiba"), dog_sheet("golden"), t, bowl_preview("orange"), bowl_preview("blue"), bone(), fish(), banana()]
        width = max(len(i[0]) for i in items)
        rows = []
        for item in items:
            for row in item:
                rows.append([p or bg for p in row] + [bg] * (width - len(row)))
            rows.append([bg] * width)
        write_png(os.path.join(ROOT, "build/art-preview.png"), upscale(rows, 4))
        print("wrote build/art-preview.png")


if __name__ == "__main__":
    main()
