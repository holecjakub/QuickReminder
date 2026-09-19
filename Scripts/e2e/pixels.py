#!/usr/bin/env python3
"""Pixel-level assertions for QuickReminder E2E screenshots.

All coordinates on this module's CLI are in POINTS, relative to the
top-left corner of the screenshot PNG itself (i.e. relative to whatever
region was passed to `screencapture -R`, not to the global screen). Points
are converted to raw image pixels using a scale factor (default 2, this
machine's Retina backing scale factor for the built-in display); override
with the PIXELS_SCALE env var if a screenshot was taken at a different
scale.

Sub-commands (each prints a single line to stdout):

  dark_count <png> <x> <y> <w> <h> [max_channel]
      Count pixels within the sub-region (points) whose max(R,G,B) is
      below `max_channel` (default 20). Prints the count.

  bright_count <png> <x> <y> <w> <h> [min_channel]
      Count pixels within the sub-region whose max(R,G,B) is above
      `min_channel` (default 200).

  color_count <png> <x> <y> <w> <h> <hex> [tolerance]
      Count pixels within the sub-region close to the given #RRGGBB color
      (default tolerance 40 per channel).

  silhouette_width <png> <y> [max_channel]
      At the given row y (points), measure the width in POINTS of the
      contiguous dark run that contains the image's horizontal centre
      column (max(R,G,B) < max_channel, default 20). Used to detect the
      notch hover swell. Prints 0 if the centre pixel at that row is not
      dark (i.e. no silhouette at that row).

Exit code is 0 with a bare number/result on stdout on success, 1 with a
message on stderr on error (bad file, bad args, etc).
"""
import os
import sys
from PIL import Image

SCALE = float(os.environ.get("PIXELS_SCALE", "2"))


def load(png_path):
    return Image.open(png_path).convert("RGB")


def _px_rect(img, x_pt, y_pt, w_pt, h_pt):
    x0 = max(0, int(round(x_pt * SCALE)))
    y0 = max(0, int(round(y_pt * SCALE)))
    x1 = min(img.width, int(round((x_pt + w_pt) * SCALE)))
    y1 = min(img.height, int(round((y_pt + h_pt) * SCALE)))
    return x0, y0, x1, y1


def cmd_dark_count(args):
    png, x, y, w, h = args[0], float(args[1]), float(args[2]), float(args[3]), float(args[4])
    max_channel = int(args[5]) if len(args) > 5 else 20
    img = load(png)
    px = img.load()
    x0, y0, x1, y1 = _px_rect(img, x, y, w, h)
    count = 0
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            r, g, b = px[xx, yy]
            if max(r, g, b) < max_channel:
                count += 1
    print(count)


def cmd_bright_count(args):
    png, x, y, w, h = args[0], float(args[1]), float(args[2]), float(args[3]), float(args[4])
    min_channel = int(args[5]) if len(args) > 5 else 200
    img = load(png)
    px = img.load()
    x0, y0, x1, y1 = _px_rect(img, x, y, w, h)
    count = 0
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            r, g, b = px[xx, yy]
            if max(r, g, b) > min_channel:
                count += 1
    print(count)


def cmd_color_count(args):
    png, x, y, w, h, hexcolor = args[0], float(args[1]), float(args[2]), float(args[3]), float(args[4]), args[5]
    tol = int(args[6]) if len(args) > 6 else 40
    hexcolor = hexcolor.lstrip("#")
    tr, tg, tb = int(hexcolor[0:2], 16), int(hexcolor[2:4], 16), int(hexcolor[4:6], 16)
    img = load(png)
    px = img.load()
    x0, y0, x1, y1 = _px_rect(img, x, y, w, h)
    count = 0
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            r, g, b = px[xx, yy]
            if abs(r - tr) <= tol and abs(g - tg) <= tol and abs(b - tb) <= tol:
                count += 1
    print(count)


def cmd_silhouette_width(args):
    png, y_pt = args[0], float(args[1])
    max_channel = int(args[2]) if len(args) > 2 else 20
    img = load(png)
    px = img.load()
    yy = int(round(y_pt * SCALE))
    if yy < 0 or yy >= img.height:
        print(0)
        return
    cx = img.width // 2
    r, g, b = px[cx, yy]
    if max(r, g, b) >= max_channel:
        print(0)
        return
    left = cx
    while left > 0:
        r, g, b = px[left - 1, yy]
        if max(r, g, b) >= max_channel:
            break
        left -= 1
    right = cx
    while right < img.width - 1:
        r, g, b = px[right + 1, yy]
        if max(r, g, b) >= max_channel:
            break
        right += 1
    width_px = right - left + 1
    print(round(width_px / SCALE, 1))


def main():
    if len(sys.argv) < 2:
        print("usage: pixels.py <dark_count|bright_count|color_count|silhouette_width> ...", file=sys.stderr)
        sys.exit(1)
    cmd = sys.argv[1]
    args = sys.argv[2:]
    try:
        if cmd == "dark_count":
            cmd_dark_count(args)
        elif cmd == "bright_count":
            cmd_bright_count(args)
        elif cmd == "color_count":
            cmd_color_count(args)
        elif cmd == "silhouette_width":
            cmd_silhouette_width(args)
        else:
            print(f"unknown command: {cmd}", file=sys.stderr)
            sys.exit(1)
    except Exception as exc:  # noqa: BLE001 - CLI tool, report and exit
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
