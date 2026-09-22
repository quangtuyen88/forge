#!/usr/bin/env python3.13
"""Turn 1024px exercise art JPEGs into asset-catalog imagesets named ex-<id>. Requires Pillow."""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App/Forge/Assets.xcassets/ExerciseArt"
MIN_BYTES = 20 * 1024
LIGHT_CORNER = 225


def whiten(im: Image.Image) -> bool:
  """Flood the flat background to pure white from the edges. False when the corner is too dark to do safely."""
  w, h = im.size
  corner = min(sum(im.getpixel(p)) // 3 for p in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)))
  if corner < LIGHT_CORNER:
    return False
  for xy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)):
    ImageDraw.floodfill(im, xy, (255, 255, 255), thresh=14)
  return True


def main() -> None:
  if len(sys.argv) != 2:
    sys.exit("usage: import-exercise-art.py <art-dir>")
  src_dir = Path(sys.argv[1])
  catalog_contents = '{"info":{"author":"xcode","version":1}}'
  CATALOG.mkdir(parents=True, exist_ok=True)
  (CATALOG / "Contents.json").write_text(catalog_contents)
  imported = skipped = 0
  dark: list[str] = []
  for src in sorted(src_dir.glob("*.jpg")):
    size = src.stat().st_size
    if size < MIN_BYTES:
      print(f"skipped {src.name} ({size} bytes, under 20 KB)")
      skipped += 1
      continue
    name = f"ex-{src.stem}"
    imageset = CATALOG / f"{name}.imageset"
    imageset.mkdir(exist_ok=True)
    with Image.open(src) as im:
      rgb = im.convert("RGB")
      if whiten(rgb) is False:
        dark.append(src.stem)
      rgb.resize((600, 600), Image.LANCZOS).save(imageset / f"{name}.jpg", "JPEG", quality=82, optimize=True)
    (imageset / "Contents.json").write_text(
      '{"images":[{"filename":"%s.jpg","idiom":"universal"}],"info":{"author":"xcode","version":1}}' % name
    )
    imported += 1
  if dark:
    print(f"dark background, left as is ({len(dark)}): {' '.join(dark)}")
  print(f"imported {imported}, skipped {skipped}")


if __name__ == "__main__":
  main()
