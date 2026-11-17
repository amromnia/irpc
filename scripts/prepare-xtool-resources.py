#!/usr/bin/env python3
"""Derive loose PNG resources from the original Xcode catalog; never edit the catalog."""
import copy
import json
import shutil
import subprocess
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "iRPC/Assets.xcassets"
OUTPUT = ROOT / "Resources/Xtool"


def prepare():
    supported = {"AppIcon.appiconset", "AccentColor.colorset", "Discord.symbolset", "Contents.json"}
    unsupported = {entry.name for entry in CATALOG.iterdir()} - supported
    if unsupported:
        raise SystemExit("Add portable resource handling for new catalog entries: " + ", ".join(sorted(unsupported)))
    colors = json.loads((CATALOG / "AccentColor.colorset/Contents.json").read_text())["colors"]
    if any("color" in entry for entry in colors):
        raise SystemExit("AccentColor now specifies a color. Add a matching portable color before building.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    icons = CATALOG / "AppIcon.appiconset"
    for entry in json.loads((icons / "Contents.json").read_text())["images"]:
        shutil.copyfile(icons / entry["filename"], OUTPUT / entry["filename"])

    # This catalog contains an SF Symbol template sheet, not an ordinary image.
    # Preserve the Regular-M glyph used at the default weight, excluding guides
    # and all other variants. Match native template rendering with an alpha PNG.
    svg = ET.parse(CATALOG / "Discord.symbolset/Discord Icon.svg").getroot()
    glyph = next(node for node in svg.iter() if node.get("id") == "Regular-M")
    output = ET.Element("{http://www.w3.org/2000/svg}svg", {
        "width": "3300", "height": "2200", "viewBox": "0 0 3300 2200"
    })
    output.append(copy.deepcopy(glyph))
    converter = shutil.which("magick") or shutil.which("convert")
    if not converter:
        raise SystemExit("Install ImageMagick (sudo apt install imagemagick) to rasterize the Discord symbol.")
    subprocess.run([
        converter, "-background", "none", "svg:-", "-trim", "+repage",
        "-resize", "96x96", "PNG32:" + str(OUTPUT / "Discord@3x.png")
    ], input=ET.tostring(output), check=True)
    print("Prepared loose icons and the original Discord glyph in", OUTPUT)


if __name__ == "__main__":
    prepare()
