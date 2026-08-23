#!/usr/bin/env python3
"""Build a face sheet: one creature, one drawing per mood, no motion.

A pet does not have to move to be alive. This takes a grid of renders that
show the same body wearing different expressions and lays them out as a
sheet the plugin can index by mood.

The one thing that has to be right is that the body lands in exactly the
same place in every cell — a face that shifts two pixels when the mood
changes reads as a glitch rather than a feeling. Generated renders are not
pixel-aligned, and several of these carry decorations (a question mark,
sparkles, a heart) fused to the body, so the body is found by eroding those
thin attachments away, and every cell is then cut relative to the body's own
left edge and footing rather than to the grid it was drawn on.

Usage:
  tools/build-faces.py out.webp source.png COLS ROWS name,name,... [--height N]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ALPHA_ON = 32          # what counts as drawn rather than empty
ERODE = 10             # enough to detach a sparkle, not enough to eat the body
MARGIN = 8             # breathing room around the widest cell, in *output* pixels
SLIDE = 8              # how far a body may be nudged to line up with the first


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def load_rgba(path):
    import numpy as np
    w, h = run("magick", "identify", "-format", "%w %h", str(path)).split()
    w, h = int(w), int(h)
    with tempfile.NamedTemporaryFile(suffix=".rgba") as tmp:
        run("magick", str(path), "-depth", "8", f"rgba:{tmp.name}")
        data = np.fromfile(tmp.name, dtype=np.uint8)
    return data.reshape(h, w, 4), w, h


def erode(mask, times):
    a = mask
    for _ in range(times):
        b = a.copy()
        b[1:, :] &= a[:-1, :]
        b[:-1, :] &= a[1:, :]
        b[:, 1:] &= a[:, :-1]
        b[:, :-1] &= a[:, 1:]
        a = b
    return a


def share_out(mask, cores, tile_of=None):
    """Give every drawn pixel to the body it is nearest to *through the
    drawing*, not across the gap between them.

    A sleeping creature's zZz reaches far enough right to brush the cube
    beside it, so asking what each blob is joined to gives it to both, and
    asking which centre it is closer to cuts it in half. Growing all the
    bodies outwards at once and letting them meet where they meet keeps the
    zZz whole and gives it to the creature it actually trails from.
    """
    import numpy as np
    owner = np.full(mask.shape, -1, dtype=np.int16)
    for i, core in enumerate(cores):
        owner[core & mask] = i
    while True:
        spread = owner.copy()
        for shift in range(4):
            moved = np.full_like(owner, -1)
            if shift == 0: moved[1:, :] = owner[:-1, :]
            elif shift == 1: moved[:-1, :] = owner[1:, :]
            elif shift == 2: moved[:, 1:] = owner[:, :-1]
            else: moved[:, :-1] = owner[:, 1:]
            take = (spread < 0) & (moved >= 0) & mask
            spread[take] = moved[take]
        if (spread == owner).all():
            break
        owner = spread

    # A decoration that touches nothing — a question mark floating beside a
    # puzzled face — is never reached by growing outwards from a body, and
    # would simply vanish. It belongs to the drawing it was drawn in, which
    # is the cell of the sheet it lies in: asking which body centre is
    # nearest instead hands a sparkle that sits low in its own cell to the
    # creature in the row below, whose middle happens to be closer.
    import numpy as np
    stray = mask & (owner < 0)
    centres = [np.argwhere(core & mask).mean(axis=0) for core in cores]
    while stray.any():
        ys, xs = np.where(stray)
        blob = np.zeros_like(stray)
        blob[ys[0], xs[0]] = True
        while True:
            bigger = blob.copy()
            bigger[1:, :] |= blob[:-1, :]
            bigger[:-1, :] |= blob[1:, :]
            bigger[:, 1:] |= blob[:, :-1]
            bigger[:, :-1] |= blob[:, 1:]
            bigger &= stray
            if bigger.sum() == blob.sum():
                break
            blob = bigger
        here = np.argwhere(blob).mean(axis=0)
        home = tile_of(here) if tile_of is not None else None
        if home is None:
            home = min(range(len(centres)), key=lambda i: ((centres[i] - here) ** 2).sum())
        owner[blob] = home
        stray &= ~blob
    return owner


def bodies(mask, cols, rows):
    """The body in each cell, found without the decorations fused to it."""
    import numpy as np
    small = erode(mask, ERODE)
    with tempfile.TemporaryDirectory() as d:
        raw = Path(d) / "e.gray"
        png = Path(d) / "e.png"
        (small * 255).astype(np.uint8).tofile(raw)
        h, w = mask.shape
        run("magick", "-size", f"{w}x{h}", "-depth", "8", f"gray:{raw}", str(png))
        listing = run("magick", str(png), "-threshold", "50%",
                      "-define", "connected-components:verbose=true",
                      "-define", "connected-components:area-threshold=15000",
                      "-connected-components", "8", "null:")
    found = []
    for line in listing.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 5 or not parts[-1].startswith("gray(255"):
            continue
        wh, x, y = parts[1].split("+")
        bw, bh = (int(v) for v in wh.split("x"))
        found.append((int(x) - ERODE, int(y) - ERODE, bw + 2 * ERODE, bh + 2 * ERODE))
    if len(found) != cols * rows:
        raise SystemExit(f"build-faces: found {len(found)} bodies, expected {cols * rows}")
    found.sort(key=lambda b: b[1])
    ordered = []
    for r in range(rows):
        band = sorted(found[r * cols:(r + 1) * cols], key=lambda b: b[0])
        ordered.append(band)
    return ordered


def main(argv):
    import numpy as np
    if len(argv) < 5:
        raise SystemExit(__doc__)
    out, source, cols, rows = argv[0], argv[1], int(argv[2]), int(argv[3])
    names = [n.strip() for n in argv[4].split(",")]
    height = 208
    if "--height" in argv:
        height = int(argv[argv.index("--height") + 1])
    if len(names) != cols * rows:
        raise SystemExit(f"build-faces: {len(names)} names for {cols * rows} cells")

    img, W, H = load_rgba(source)
    mask = img[:, :, 3] > ALPHA_ON
    luma = ((img[:, :, 0] * 0.3 + img[:, :, 1] * 0.59 + img[:, :, 2] * 0.11) * mask).astype(np.float32)
    grid = bodies(mask, cols, rows)

    # Where the body stands, per cell: its left edge and the ground under it.
    anchors = [[(b[0], b[1] + b[3]) for b in row] for row in grid]

    # Anchoring on the body's own edges gets within a pixel or two, which is
    # still a visible twitch when the face changes and the body appears to
    # step sideways. The remainder is measured directly: each body is slid
    # against the first one until they line up, and the anchor takes the
    # correction. Only the body is compared — a sparkle or a heart would pull
    # the match towards itself.
    ref_ax, ref_ay = anchors[0][0]
    ref_w, ref_h = grid[0][0][2], grid[0][0][3]

    def patch(ax, ay, dx=0, dy=0):
        # The window above the footing, clamped to the image so a body near an
        # edge yields a full-size patch (zero-padded) rather than a short slice
        # that will not broadcast against the reference.
        y0, x0 = ay - ref_h + dy, ax + dx
        out = np.zeros((ref_h, ref_w), np.float32)
        sy0, sx0 = max(0, y0), max(0, x0)
        sy1, sx1 = min(H, y0 + ref_h), min(W, x0 + ref_w)
        if sy1 > sy0 and sx1 > sx0:
            out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = luma[sy0:sy1, sx0:sx1]
        return out - out.mean()

    reference = patch(ref_ax, ref_ay)
    for r in range(rows):
        for c in range(cols):
            ax, ay = anchors[r][c]
            best = None
            for dy in range(-SLIDE, SLIDE + 1):
                for dx in range(-SLIDE, SLIDE + 1):
                    score = float((reference * patch(ax, ay, dx, dy)).sum())
                    if best is None or score > best[0]:
                        best = (score, dx, dy)
            _, dx, dy = best
            anchors[r][c] = (ax + dx, ay + dy)

    # How far the drawing reaches from that footing, taking the widest of
    # every cell so one box fits them all and nothing is clipped.
    # What belongs to each cell is exactly what its body is joined to. A
    # decoration reaches past the halfway line to its neighbour — a question
    # mark, the points of a sparkle — so splitting on geometry either clips
    # them off or drags the neighbour in. Each drawing is one connected
    # piece, so the cell is grown outwards from its own body instead.
    # Every drawn pixel goes to the body it is nearest to through the drawing.
    small = erode(mask, ERODE)
    cores = []
    for r in range(rows):
        for c in range(cols):
            bx, by, bw, bh = grid[r][c]
            core = np.zeros_like(mask)
            core[by:by + bh, bx:bx + bw] = small[by:by + bh, bx:bx + bw]
            cores.append(core)
    # The sheet is a regular grid of drawings, so the cell a stray decoration
    # was drawn in is simply the tile it lies in.
    def tile_of(point):
        r = int(point[0] * rows // H)
        c = int(point[1] * cols // W)
        r = min(max(r, 0), rows - 1)
        c = min(max(c, 0), cols - 1)
        return r * cols + c

    owner = share_out(mask, cores, tile_of)

    owned = [[None] * cols for _ in range(rows)]
    left = up = right = down = 0
    for r in range(rows):
        for c in range(cols):
            ax, ay = anchors[r][c]
            region = owner == r * cols + c
            owned[r][c] = region
            ys, xs = np.where(region)
            left = max(left, ax - xs.min())
            right = max(right, xs.max() + 1 - ax)
            up = max(up, ay - ys.min())
            down = max(down, ys.max() + 1 - ay)

    # Breathing room is what stops a neighbouring cell bleeding in once the
    # sheet is scaled down and filtered, so it has to be measured in the
    # pixels it will be drawn at, not the ones it was drawn in.
    rough = height / (up + down)
    pad = max(1, round(MARGIN / rough))
    left += pad; right += pad; up += pad; down += pad
    cell_w, cell_h = left + right, up + down
    scale = height / cell_h
    out_w, out_h = round(cell_w * scale), height
    body_h = round(grid[0][0][3] * scale)
    ground = round((up) * scale)

    with tempfile.TemporaryDirectory() as d:
        tiles = []
        for r in range(rows):
            for c in range(cols):
                ax, ay = anchors[r][c]
                x0, y0 = ax - left, ay - up
                # The cell holds this drawing and nothing else: everything
                # the body is not joined to is cleared before it is cut.
                cut = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
                sx0, sy0 = max(0, x0), max(0, y0)
                sx1, sy1 = min(W, x0 + cell_w), min(H, y0 + cell_h)
                piece = img[sy0:sy1, sx0:sx1].copy()
                keep = owned[r][c][sy0:sy1, sx0:sx1]
                piece[~keep] = 0
                cut[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = piece
                raw = Path(d) / f"{r}-{c}.rgba"
                tile = Path(d) / f"{r}-{c}.png"
                cut.tofile(raw)
                run("magick", "-size", f"{cell_w}x{cell_h}", "-depth", "8", f"rgba:{raw}",
                    "-filter", "Lanczos", "-resize", f"{out_w}x{out_h}!", str(tile))
                tiles.append(str(tile))
        run("magick", "montage", *tiles, "-tile", f"{cols}x{rows}",
            "-geometry", "+0+0", "-background", "none", "-define", "webp:lossless=true", out)

    faces = {}
    for r in range(rows):
        for c in range(cols):
            faces[names[r * cols + c]] = [r, c]
    print(json.dumps({
        "spritesheetPath": Path(out).name,
        "rows": rows, "columns": cols, "faces": faces,
        "_cell": [out_w, out_h], "_bodyHeight": body_h, "_groundLine": ground,
    }, indent=2))


if __name__ == "__main__":
    main(sys.argv[1:])
