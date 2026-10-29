#!/usr/bin/env python3
"""Generates King Kong's banana trees as PNGs.

The pets, wardrobe, bowls, treats and poop come from chibi.py.

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


# ---------------------------------------------------------------- Banana trees
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
        "Resources/Art/tree-appleReminders.png": tree("orange"),
        "Resources/Art/tree-googleTasks.png": tree("blue"),
    }
    for path, rows in out.items():
        write_png(os.path.join(ROOT, path), rows)
        print("wrote", path)

    if "--preview" in sys.argv:
        bg = (236, 236, 240, 255)
        items = [tree("orange"), tree("blue")]
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
