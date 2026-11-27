"""Build UI and platform sizes from the preserved Magpie image sources.

Requires Pillow. Run from any directory with ``python scripts/generate_icons.py``.
The generator returned an opaque white atlas; its green strokes are extracted
without redrawing them. Native illustration transparency is preserved.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source"
ICON_NAMES = (
    "today", "library", "stats", "settings",
    "arrow_right", "pencil", "plus", "search",
    "check", "refresh", "download", "upload",
    "arrow_left", "close", "warning", "cards",
)
RESAMPLE = Image.Resampling.LANCZOS


def extract_white_background(image: Image.Image) -> Image.Image:
    """Recover alpha for the generated green strokes, including their interiors."""
    pixels = []
    rgba = image.convert("RGBA")
    source_pixels = rgba.load()
    for red, green, blue, original_alpha in (
        source_pixels[x, y] for y in range(rgba.height) for x in range(rgba.width)
    ):
        # The source contains only forest/sage artwork on near-white paper.
        # Ignore the slight neutral compression noise in the white canvas.
        if green - red < 6 or green - blue < 6 or min(red, green, blue) > 245:
            pixels.append((red, green, blue, 0))
            continue
        coverage = min(1.0, (245 - min(red, green, blue)) / 65)
        pixels.append((red, green, blue, min(original_alpha, round(coverage * 255))))
    result = Image.new("RGBA", image.size)
    result.putdata(pixels)
    return result


def save_png(image: Image.Image, target: Path, size: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), RESAMPLE).save(target, optimize=True)


def main() -> None:
    atlas = Image.open(SOURCE / "ui-icon-atlas.png").convert("RGBA")
    if atlas.size != (1024, 1024):
        raise ValueError(f"Expected 1024x1024 atlas, got {atlas.size}")
    atlas = extract_white_background(atlas)
    for index, name in enumerate(ICON_NAMES):
        left, top = (index % 4) * 256, (index // 4) * 256
        tile = atlas.crop((left, top, left + 256, top + 256))
        bbox = tile.getchannel("A").point(lambda value: 255 if value > 32 else 0).getbbox()
        if bbox is None:
            raise ValueError(f"Empty icon: {name}")
        artwork = tile.crop(bbox)
        scale = 200 / max(artwork.size)
        artwork = artwork.resize((round(artwork.width * scale), round(artwork.height * scale)), RESAMPLE)
        output = Image.new("RGBA", (256, 256))
        output.alpha_composite(artwork, ((256 - artwork.width) // 2, (256 - artwork.height) // 2))
        save_png(output, ROOT / "assets" / "icons" / f"{name}.png", 256)

    # Preserve the generated illustration's actual alpha; its invisible pixels
    # contain magenta RGB data, which must not be mistaken for an opaque matte.
    books = Image.open(SOURCE / "study-books.png").convert("RGBA")
    if books.getchannel("A").getextrema()[0] != 0:
        raise ValueError("The study illustration must have a genuine transparent background")
    save_png(books, ROOT / "assets" / "images" / "study-books.png", 512)

    # The generated mark has white rounded outer corners. This inner square
    # crops them away while preserving the complete central book artwork.
    app = Image.open(SOURCE / "app-icon.png").convert("RGB").crop((40, 40, 984, 984))
    save_png(app, ROOT / "assets" / "images" / "app-icon.png", 512)
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save_png(app, ROOT / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher.png", size)
    for platform in ("ios", "macos"):
        folder = ROOT / platform / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
        contents = json.loads((folder / "Contents.json").read_text(encoding="utf-8-sig"))
        for item in contents["images"]:
            size = round(float(item["size"].split("x")[0]) * float(item["scale"].rstrip("x")))
            save_png(app, folder / item["filename"], size)
    windows = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    app.resize((256, 256), RESAMPLE).save(windows, format="ICO", sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
    print("Generated 16 transparent UI icons, 2 image assets, and Android/iOS/macOS/Windows icons.")


if __name__ == "__main__":
    main()
