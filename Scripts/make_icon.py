#!/usr/bin/env python3
"""Generate the QuickReminder app icon: a grey macOS squircle with the notch hanging from the
top edge and a checkmark inside it. Writes Resources/AppIcon.icns (and a 1024 px preview).

Only Pillow is needed:  python3 Scripts/make_icon.py
"""
from pathlib import Path
import math, subprocess, shutil, tempfile
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT_ICNS = ROOT / "Resources" / "AppIcon.icns"
PREVIEW = ROOT / "build" / "AppIcon-1024.png"

S = 4            # supersampling
N = 1024 * S     # working canvas

def squircle_mask(size, box, radius_ratio=0.225, exponent=5.0):
    """macOS-style continuous-corner rounded square (superellipse) as an L mask."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    r = min(w, h) * radius_ratio
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    # Build the outline as a polygon: straight edges + superellipse corners.
    pts = []
    def corner(cx, cy, sx, sy):
        for i in range(0, 91, 2):
            t = math.radians(i)
            px = cx + sx * r * (abs(math.cos(t)) ** (2 / exponent)) * (1 if math.cos(t) >= 0 else -1)
            py = cy + sy * r * (abs(math.sin(t)) ** (2 / exponent)) * (1 if math.sin(t) >= 0 else -1)
            pts.append((px, py))
    # top-right, bottom-right, bottom-left, top-left (clockwise)
    corner(x1 - r, y0 + r, 1, -1)
    pts_tr = pts[:]; pts = []
    corner(x1 - r, y1 - r, 1, 1)
    pts_br = pts[:]; pts = []
    corner(x0 + r, y1 - r, -1, 1)
    pts_bl = pts[:]; pts = []
    corner(x0 + r, y0 + r, -1, -1)
    pts_tl = pts[:]
    outline = list(reversed(pts_tr)) + pts_br + list(reversed(pts_bl)) + pts_tl
    d.polygon(outline, fill=255)
    return mask

def vertical_gradient(size, box, top, bottom):
    x0, y0, x1, y1 = box
    grad = Image.new("RGB", (size, size), bottom)
    d = ImageDraw.Draw(grad)
    for y in range(int(y0), int(y1) + 1):
        t = (y - y0) / max(1, (y1 - y0))
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c)
    return grad

def notch_path(cx, top, width, height, top_r, bottom_r):
    """Notch silhouette (flat top, outward top fillets, rounded bottom) as a polygon."""
    x0, x1 = cx - width / 2, cx + width / 2
    y1 = top + height
    pts = [(x0 - top_r, top)]
    # top-left outward fillet: quad curve from (x0 - r, top) to (x0, top + r), control (x0, top)
    def quad(p0, c, p1, n=24):
        return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t ** 2 * p1[0],
                 (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t ** 2 * p1[1]) for t in [i / n for i in range(n + 1)]]
    pts += quad((x0 - top_r, top), (x0, top), (x0, top + top_r))
    pts += [(x0, y1 - bottom_r)]
    pts += quad((x0, y1 - bottom_r), (x0, y1), (x0 + bottom_r, y1))
    pts += [(x1 - bottom_r, y1)]
    pts += quad((x1 - bottom_r, y1), (x1, y1), (x1, y1 - bottom_r))
    pts += [(x1, top + top_r)]
    pts += quad((x1, top + top_r), (x1, top), (x1 + top_r, top))
    return pts

def render(size=N):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # macOS icon grid: the shape sits inside ~ 80.5 % of the canvas.
    margin = size * 0.0975
    box = (margin, margin, size - margin, size - margin)
    w = box[2] - box[0]

    # Body: grey gradient inside a squircle, with a faint darker rim.
    mask = squircle_mask(size, box)
    body = vertical_gradient(size, box, (0xA9, 0xA9, 0xAE), (0x6A, 0x6A, 0x6F)).convert("RGBA")
    img.paste(body, (0, 0), mask)
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(rim).bitmap((0, 0), mask, fill=(0, 0, 0, 40))
    inner = squircle_mask(size, (box[0] + 3 * S, box[1] + 3 * S, box[2] - 3 * S, box[3] - 3 * S))
    rim_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rim_layer.paste((0, 0, 0, 45), (0, 0), mask)
    rim_layer.paste((0, 0, 0, 0), (0, 0), inner)
    img.alpha_composite(rim_layer)

    # Notch hanging from the top edge of the body.
    cx = size / 2
    notch_w, notch_h = w * 0.40, w * 0.17
    top_r, bottom_r = w * 0.028, w * 0.062
    notch = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(notch).polygon(notch_path(cx, box[1], notch_w, notch_h, top_r, bottom_r), fill=(0, 0, 0, 255))
    # keep the notch inside the squircle (the fillets reach the rounded top edge)
    notch_clip = Image.new("L", (size, size), 0)
    notch_clip.paste(mask, (0, 0))
    notch.putalpha(Image.composite(notch.getchannel("A"), Image.new("L", (size, size), 0), notch_clip))
    img.alpha_composite(notch)

    # Checkmark inside the notch.
    chk = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(chk)
    ch = notch_h * 0.52
    cw = ch * 1.35
    ccx, ccy = cx, box[1] + notch_h * 0.5
    p0 = (ccx - cw / 2, ccy + ch * 0.02)
    p1 = (ccx - cw * 0.12, ccy + ch / 2)
    p2 = (ccx + cw / 2, ccy - ch / 2)
    lw = int(notch_h * 0.135)
    d.line([p0, p1, p2], fill=(255, 255, 255, 255), width=lw, joint="curve")
    for p in (p0, p2):
        d.ellipse([p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2], fill=(255, 255, 255, 255))
    img.alpha_composite(chk)

    # Soft drop shadow like macOS icons.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (0, 0), mask)
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -size * 0.012))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.012))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(shadow)
    out.alpha_composite(img)
    return out.resize((size // S, size // S), Image.LANCZOS)

def main():
    icon = render()
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    icon.save(PREVIEW)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for px in (16, 32, 128, 256, 512):
            icon.resize((px, px), Image.LANCZOS).save(iconset / f"icon_{px}x{px}.png")
            icon.resize((px * 2, px * 2), Image.LANCZOS).save(iconset / f"icon_{px}x{px}@2x.png")
        OUT_ICNS.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT_ICNS)], check=True)
    print(f"wrote {OUT_ICNS} and {PREVIEW}")

if __name__ == "__main__":
    main()
