#!/usr/bin/env python3
"""Build a complete pet atlas from every source, at one single scale.

The creature must be the same size and stand in the same place whether it
is idling, walking or watering a plant. That does not happen by itself:
each sheet is its own render, and scaling every row to fill the cell makes
the creature shrink exactly where something tall — a balloon, a cat — rises
above it. So the character itself is the measure.

Every source contributes one neutral reference pose, the plain cube in its
first column. All of them are scaled so that reference is identical, and
the shared scale is chosen as the largest one at which every frame fits its
cell vertically and around the cell's horizontal centre. Each frame is then
seated on its own lowest visible pixel, so feet land on the ground and only
what should rise above the creature does.

Usage:
  build-atlas.py <out.webp> --walk <sheet> <frames> --idle <image>
                 [--activities <sheet> <cols> <rows> <name,...>]
                 [--poses <name=row:col,...>]
"""
import argparse
import itertools
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

FW, FH = 192, 208
COLUMNS = 8
GROUND = 4                 # air kept under the lowest visible pixel
HEADROOM = 2               # never let a frame touch the top of its cell
SIDE_ROOM = 2              # or either side after centring the source cell
# A performance is a small story told in six pictures, watched out of the
# corner of an eye. It has to be slow enough to follow at a glance and long
# enough to be worth glancing at.
TARGET_TOTAL = 10500       # how long one pass through a row should last
MIN_HOLD, MAX_HOLD = 900, 3200
FINALE = 2.0               # how much longer a closing frame lingers
SHAPE = 0.45               # how far the picture's own rhythm bends the timing
STANDARD_ROWS = 9          # the Codex/Petdex rows every reader expects
SUPPORTED_POSES = ("working", "error", "waiting", "success", "sleep")


class BuildError(RuntimeError):
    pass


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def image_size(path):
    raw = run(["magick", "identify", "-format", "%w %h", str(path)]).split()
    if len(raw) != 2:
        raise BuildError(f"cannot read one image size from {path}")
    try:
        return tuple(int(value) for value in raw)
    except ValueError as error:
        raise BuildError(f"cannot read image size from {path}") from error


def grid_size(path, cols, rows, label):
    width, height = image_size(path)
    if width % cols or height % rows:
        raise BuildError(
            f"{label} is {width}x{height}, not exactly divisible by {cols}x{rows}"
        )
    return width // cols, height // rows


def has_alpha(path):
    return run(["magick", "identify", "-format", "%A", str(path)]).strip().lower() in ("blend", "true", "on")


def prepare(path, dst):
    """The artwork with a trustworthy alpha channel.

    A sheet that brings its own transparency keeps it: keying a background
    out by colour also takes the artwork's dark outline, which is invisible
    on a dark desktop and a bright halo on a white window.
    """
    if has_alpha(path):
        run(["magick", str(path), str(dst)])
    else:
        run(["magick", str(path), "-fuzz", "8%", "-transparent", "black", str(dst)])


def strip_edge_bleed(path, share=0.08):
    """Remove what leaked in from the neighbouring cell.

    Sheets are cut on a grid, and a pose that reaches past its row leaves a
    sliver in the cell next door. Such a sliver is recognisable: it is small,
    it is separate from the figure, and it is pressed flat against the top or
    bottom edge of the cell — where a drawn balloon, a sparkle or a floating
    z never sits, because those are placed inside the frame.

    The sliver is cut away rather than masked out. Masking meant trusting a
    labelled image to say which pixels were figure and which were background,
    and where the figure happened to be labelled zero that reading inverted
    and filled the cell with a black slab. A crop cannot invert.
    """
    mask = path.with_name(path.stem + "_mask.png")
    run(["magick", str(path), "-alpha", "extract", "-threshold", "20%", str(mask)])
    width, height = (int(v) for v in run(["magick", "identify", "-format", "%w %h", str(mask)]).split())
    out = run(["magick", str(mask), "-define", "connected-components:verbose=true",
               "-define", "connected-components:area-threshold=6",
               "-connected-components", "8", "null:"])
    parts = parse_connected_components(out, path)
    if len(parts) < 2:
        return
    figure = max(parts, key=lambda p: p["area"])
    slivers = [p for p in parts
               if p is not figure and p["area"] < figure["area"] * share
               and (p["top"] <= 0 or p["bottom"] >= height)]
    if not slivers:
        return

    top_cut = max([p["bottom"] for p in slivers if p["top"] <= 0], default=0)
    bottom_cut = min([p["top"] for p in slivers if p["bottom"] >= height], default=height)
    # Never cut into the creature itself.
    top_cut = min(top_cut, figure["top"])
    bottom_cut = max(bottom_cut, figure["bottom"])
    if top_cut <= 0 and bottom_cut >= height:
        return
    run(["magick", str(path), "-crop", f"{width}x{bottom_cut - top_cut}+0+{top_cut}",
         "+repage", "-background", "none", "-gravity", "North",
         "-extent", f"{width}x{height}", str(path)])


def parse_connected_components(output, path):
    """Read ImageMagick's foreground records without leaking parser errors."""
    parts = []
    for line in output.splitlines():
        if "gray(255)" not in line:
            continue
        fields = line.split()
        geometry = fields[1] if len(fields) > 1 else ""
        match = re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", geometry)
        try:
            area = int(fields[3])
        except (IndexError, ValueError) as error:
            raise BuildError(
                f"cannot parse ImageMagick connected-components output for {path}: "
                f"{line.strip()!r}"
            ) from error
        if match is None:
            raise BuildError(
                f"cannot parse ImageMagick connected-components output for {path}: "
                f"{line.strip()!r}"
            )
        _, height, _, y = (int(value) for value in match.groups())
        parts.append({"area": area, "top": y, "bottom": y + height})
    return parts


def bbox(path):
    box = run(["magick", str(path), "-alpha", "extract", "-threshold", "20%",
               "-format", "%@", "info:"]).strip()
    m = re.match(r"(\d+)x(\d+)\+(\d+)\+(\d+)", box)
    return tuple(int(v) for v in m.groups()) if m else None


def rmse(a, b):
    r = subprocess.run(["magick", "compare", "-metric", "RMSE", str(a), str(b), "null:"],
                       capture_output=True, text=True)
    detail = r.stderr.strip() or r.stdout.strip()
    if r.returncode not in (0, 1):
        raise BuildError(
            f"ImageMagick compare failed for {a} and {b} "
            f"(exit {r.returncode}): {detail or 'no diagnostic'}"
        )
    try:
        value = float(detail.split()[0])
    except (ValueError, IndexError) as error:
        raise BuildError(f"ImageMagick returned no parseable RMSE for {a} and {b}: {detail!r}") from error
    if not math.isfinite(value):
        raise BuildError(f"ImageMagick returned a non-finite RMSE for {a} and {b}: {detail!r}")
    return value


def frame_holds(frames):
    """How long each frame of an activity stays on screen.

    A frame's weight shows partly in how much the picture changes after it —
    a screen reading LUNCH.exe is followed by something entirely different,
    two frames of chewing barely differ — and the closing frame is held
    longest, because nothing follows it to measure.

    But how much the pixels change is not how much the moment means. A face
    going from startled to crestfallen barely moves and carries the whole
    story; timed on pixels alone it flashes past in a quarter second, which
    is what happened to the balloon drifting away. So the change is only
    allowed to bend the rhythm around an even pace, never to set it, and no
    frame drops below a floor you can actually read.
    """
    n = len(frames)
    if n < 2:
        return [int(TARGET_TOTAL)] * n
    change = [rmse(frames[i], frames[i + 1]) for i in range(n - 1)]
    change.append(max(change) * FINALE)
    total = sum(change) or 1.0
    holds = []
    for c in change:
        share = (1.0 - SHAPE) / n + SHAPE * (c / total)
        holds.append(int(max(MIN_HOLD, min(MAX_HOLD, round(TARGET_TOTAL * share)))))
    return holds


def smoothest_cycle(frames):
    """The playback order whose neighbouring frames differ least.

    Rendered poses are not always a sequence, and the order that reads as
    continuous motion is the closed cycle with the smallest total change.
    """
    n = len(frames)
    dist = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            dist[i][j] = dist[j][i] = rmse(frames[i], frames[j])
    best = None
    for perm in itertools.permutations(range(1, n)):
        order = (0,) + perm
        cost = sum(dist[order[k]][order[(k + 1) % n]] for k in range(n))
        if best is None or cost < best[0]:
            best = (cost, order)
    return best[1]


class Source:
    """One sheet cut into frames, with the reference pose that sizes it.

    Everything is measured in the source's own pixels: `reference` is the
    width of its plain standing cube, and `span` is how tall its tallest
    frame is once the empty room above the artwork is discarded. Those two
    numbers, plus the furthest visible pixel on either side of the cell's
    centre, are all it takes to place every source at one shared scale.
    """

    def __init__(self, name, frames):
        self.name = name
        if not frames or not frames[0][1]:
            raise BuildError(f"{name} has no visible reference frame in column 0")
        self.frames = [(p, b) for p, b in frames if b]
        self.top = min(b[3] for _, b in self.frames)
        self.reference = frames[0][1][0]
        self.span = max(b[3] + b[1] for _, b in self.frames) - self.top
        self.side_span = 0.0
        for path, box in self.frames:
            width, _ = image_size(path)
            _, _, x, _ = box
            centre = width / 2.0
            self.side_span = max(self.side_span, centre - x, x + box[0] - centre)

    def cube_limit(self, height_room, side_room):
        """The widest this cube may be while every visible pixel fits."""
        height_limit = height_room * self.reference / max(1, self.span)
        side_limit = side_room * self.reference / max(1, self.side_span)
        return min(height_limit, side_limit)


def cut_grid(sheet, tmp, cols, rows, tag):
    """Cut a sheet on its own grid, one shared vertical window per row."""
    prepared = tmp / f"{tag}.png"
    prepare(sheet, prepared)
    gw, gh = grid_size(sheet, cols, rows, "activity sheet")
    out = []
    for r in range(rows):
        band = []
        for c in range(cols):
            cell = tmp / f"{tag}_{r}_{c}.png"
            run(["magick", str(prepared), "-crop", f"{gw}x{gh}+{c * gw}+{r * gh}", "+repage", str(cell)])
            strip_edge_bleed(cell)
            band.append((cell, bbox(cell)))
        out.append(band)
    return out


def place(src, dst, box, top, scale, mirror=False):
    """Scale a frame and seat it on the ground of its cell.

    The cut runs from the source's shared top down to this frame's own
    lowest visible pixel: the head keeps its height across the animation,
    the empty rows under the feet go away, and what is left lands on the
    ground rather than hovering above it.
    """
    w, h, x, y = box
    span = y + h - top
    img_w = int(run(["magick", "identify", "-format", "%w", str(src)]))
    scaled_w = max(1, round(img_w * scale))
    scaled_h = max(1, round(span * scale))
    run(["magick", str(src), "-crop", f"{img_w}x{span}+0+{top}", "+repage"] +
        (["-flop"] if mirror else []) +
        ["-resize", f"{scaled_w}x{scaled_h}!",
         "-background", "none", "-gravity", "South", "-extent", f"{FW}x{FH}-0-{GROUND}",
         "PNG32:" + str(dst)])


def parse_cli(argv):
    parser = argparse.ArgumentParser(
        description="Build one aligned, unclipped animated pet atlas.",
        allow_abbrev=False,
    )
    parser.add_argument("out", type=Path, metavar="OUT.webp")
    parser.add_argument("--walk", required=True, nargs=2, metavar=("SHEET", "FRAMES"))
    parser.add_argument("--idle", required=True, nargs=1, metavar=("IMAGE",))
    parser.add_argument(
        "--activities", nargs=4, metavar=("SHEET", "COLS", "ROWS", "NAMES")
    )
    parser.add_argument("--poses", metavar="NAME=ROW:COL,...")

    for flag in ("--walk", "--idle", "--activities", "--poses"):
        uses = sum(token == flag or token.startswith(flag + "=") for token in argv)
        if uses > 1:
            parser.error(f"{flag} may only be specified once")

    args = parser.parse_args(argv)

    try:
        args.walk_n = int(args.walk[1])
    except ValueError:
        parser.error("--walk FRAMES must be an integer")
    if not 1 <= args.walk_n <= COLUMNS:
        parser.error(f"--walk FRAMES must be between 1 and {COLUMNS}")
    args.walk_sheet = Path(args.walk[0])
    args.idle_image = Path(args.idle[0])

    args.activity_sheet = None
    args.activity_cols = 0
    args.activity_rows = 0
    args.activity_names = []
    if args.activities:
        args.activity_sheet = Path(args.activities[0])
        try:
            args.activity_cols = int(args.activities[1])
            args.activity_rows = int(args.activities[2])
        except ValueError:
            parser.error("--activities COLS and ROWS must be integers")
        if not 1 <= args.activity_cols <= COLUMNS:
            parser.error(f"--activities COLS must be between 1 and {COLUMNS}")
        if args.activity_rows <= 0:
            parser.error("--activities ROWS must be greater than zero")
        args.activity_names = [name.strip() for name in args.activities[3].split(",")]
        if len(args.activity_names) != args.activity_rows:
            parser.error("--activities NAMES must contain exactly one name per row")
        if any(not name for name in args.activity_names):
            parser.error("--activities NAMES may not contain an empty name")
        seen = set()
        repeated = set()
        for name in args.activity_names:
            if name in seen:
                repeated.add(name)
            seen.add(name)
        if repeated:
            parser.error("--activities NAMES may not repeat: " + ", ".join(sorted(repeated)))

    args.pose_cells = {}
    if args.poses is not None:
        if not args.activities:
            parser.error("--poses requires --activities")
        for entry in args.poses.split(","):
            if "=" not in entry:
                parser.error(f"invalid pose {entry!r}; expected NAME=ROW:COL")
            name, where = entry.split("=", 1)
            name = name.strip()
            parts = where.split(":")
            if not name or len(parts) != 2:
                parser.error(f"invalid pose {entry!r}; expected NAME=ROW:COL")
            if name not in SUPPORTED_POSES:
                parser.error(
                    f"unsupported pose {name!r}; expected one of {', '.join(SUPPORTED_POSES)}"
                )
            try:
                row, col = (int(value) for value in parts)
            except ValueError:
                parser.error(f"invalid pose {entry!r}; row and column must be integers")
            if row < 0 or col < 0:
                parser.error(f"pose {name} row and column must be non-negative")
            if row >= args.activity_rows or col >= args.activity_cols:
                parser.error(f"pose {name} points outside the activity sheet")
            if name in args.pose_cells:
                parser.error(f"pose {name} is repeated")
            args.pose_cells[name] = (row, col)
    return args


def main(argv=None):
    args = parse_cli(sys.argv[1:] if argv is None else argv)
    out = args.out

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        sources = {}

        # --- the walk, on its own grid with one shared window --------------
        walk_sheet, walk_n = args.walk_sheet, args.walk_n
        prepared = tmp / "walk.png"
        prepare(walk_sheet, prepared)
        grid, _ = grid_size(walk_sheet, walk_n, 1, "walk sheet")
        walk_frames = []
        for i in range(walk_n):
            cell = tmp / f"walk_{i}.png"
            run(["magick", str(prepared), "-crop", f"{grid}x100000+{i * grid}+0", "+repage", str(cell)])
            walk_frames.append((cell, bbox(cell)))
        if any(box is None for _, box in walk_frames):
            raise BuildError("every walk frame must contain visible pixels")
        # Frame 0 stands with its feet together and nothing extended: the
        # reference the whole atlas is measured against.
        sources["walk"] = Source("walk", walk_frames)

        # --- the resting pose ---------------------------------------------
        idle_prepared = tmp / "idle_src.png"
        prepare(args.idle_image, idle_prepared)
        ib = bbox(idle_prepared)
        if ib is None:
            raise BuildError("idle image must contain visible pixels")
        idle_cut = tmp / "idle.png"
        run(["magick", str(idle_prepared), "-crop", f"{ib[0]}x{ib[1]}+{ib[2]}+{ib[3]}", "+repage", str(idle_cut)])
        sources["idle"] = Source("idle", [(idle_cut, bbox(idle_cut))])

        # --- the activities ------------------------------------------------
        act_rows, act_names = [], []
        if args.activity_sheet is not None:
            sheet, cols, rows = args.activity_sheet, args.activity_cols, args.activity_rows
            act_rows = cut_grid(sheet, tmp, cols, rows, "act")
            act_names = args.activity_names
            for r, band in enumerate(act_rows):
                # Column 0 of every activity row is the same plain cube.
                sources[f"act{r}"] = Source(f"act{r}", band)

        # --- one scale for the whole character -----------------------------
        # The cube is the measure. Each source says how wide its own cube is
        # and how tall its tallest frame is; the shared cube width is simply
        # the largest that keeps every frame, everywhere, inside its cell.
        room = FH - GROUND - HEADROOM
        side_room = FW / 2.0 - SIDE_ROOM
        limits = {k: s.cube_limit(room, side_room) for k, s in sources.items()}
        limiting = min(limits, key=limits.get)
        target = limits[limiting]
        scales = {k: target / s.reference for k, s in sources.items()}
        print(f"cube {target:.0f}px of {FW} across every row (limited by {limiting})")

        blank = tmp / "blank.png"
        run(["magick", "-size", f"{FW}x{FH}", "canvas:none", "PNG32:" + str(blank)])

        # --- rows ----------------------------------------------------------
        order = smoothest_cycle([p for p, _ in walk_frames])
        print(f"walk cycle: {order}")

        def walk_row(mirror):
            row = []
            for i in order:
                p, b = walk_frames[i]
                dst = tmp / f"w{'l' if mirror else 'r'}{i}.png"
                place(p, dst, b, sources["walk"].top, scales["walk"], mirror)
                row.append(str(dst))
            return row

        idle_cell = tmp / "idle_cell.png"
        place(idle_cut, idle_cell, bbox(idle_cut), sources["idle"].top, scales["idle"])
        idle_row = [str(idle_cell)] * 6

        # Activity cells first: the standard poses are picked out of the same
        # sheet, so they arrive at the same scale as everything else.
        act_cells = []
        activities = []
        for r, band in enumerate(act_rows):
            cells = []
            for c, (p, b) in enumerate(band):
                dst = tmp / f"a{r}_{c}_cell.png"
                if b:
                    place(p, dst, b, sources[f"act{r}"].top, scales[f"act{r}"])
                else:
                    run(["magick", str(blank), str(dst)])
                cells.append(str(dst))
            act_cells.append(cells)
            activities.append({
                "name": act_names[r],
                "row": STANDARD_ROWS + r,
                "frames": len(cells),
                "holds": frame_holds(cells),
            })

        # A named pose is one cell of the activity sheet, held still: the face
        # the creature wears while the agent works, waits, fails or finishes.
        poses = {}
        for name, (row, col) in args.pose_cells.items():
            poses[name] = act_cells[row][col]

        def held(name):
            """Six frames of one pose: still, but alive to a reader that loops."""
            return [poses[name]] * 6 if name in poses else idle_row

        rows_out = [
            idle_row,                 # 0 idle
            walk_row(False),          # 1 right
            walk_row(True),           # 2 left
            idle_row,                 # 3 wave — kept as the idle pose so a
            idle_row,                 # 4 jump — standard reader sees something
            held("error"),            # 5 error
            held("waiting"),          # 6 waiting
            held("working"),          # 7 working
            held("success"),          # 8 success
        ]
        rows_out.extend(act_cells)

        sleep_row = None
        if "sleep" in poses:
            sleep_row = len(rows_out)
            rows_out.append([poses["sleep"]] * 6)

        flat = []
        for row in rows_out:
            padded = list(row) + [str(blank)] * (COLUMNS - len(row))
            flat.extend(padded[:COLUMNS])

        run(["magick", "montage"] + flat +
            ["-tile", f"{COLUMNS}x{len(rows_out)}", "-geometry", "+0+0", "-background", "none",
             "PNG32:" + str(tmp / "atlas.png")])
        run(["magick", str(tmp / "atlas.png"), "-define", "webp:lossless=true", str(out)])

        # A row whose frames are all the same picture is a still pose, and
        # animating it repaints identical pixels forever. Saying which rows
        # those are lets the creature simply stop.
        still = []
        for index, row in enumerate(rows_out):
            drawn = [c for c in row if c != str(blank)]
            if len(drawn) <= 1 or all(rmse(drawn[0], c) < 1.0 for c in drawn[1:]):
                still.append(index)

        meta = {
            "spritesheetPath": out.name,
            "stillRows": still,
            "rows": len(rows_out),
            "walkFrames": len(order),
            "activities": activities,
        }
        if sleep_row is not None:
            meta["sleepRow"] = sleep_row
        print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    try:
        main()
    except BuildError as error:
        sys.exit(f"build-atlas.py: {error}")
