#!/usr/bin/env python3
"""Regenerate the native catalog icons from the versioned Afterglow vector."""
import json
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def prepare():
    converter = shutil.which("magick") or shutil.which("convert")
    if not converter:
        raise SystemExit("Install ImageMagick to regenerate app icons")
    catalog = ROOT / "iRPC/Assets.xcassets/AppIcon.appiconset"
    source = ROOT / "Resources/Brand/AppIcon.svg"
    for image in json.loads((catalog / "Contents.json").read_text())["images"]:
        size = round(float(image["size"].split("x")[0]) * int(image["scale"][0]))
        destination = catalog / image["filename"]
        subprocess.run([converter, "-background", "none", str(source), "-resize", f"{size}x{size}!",
                        "-alpha", "off", "PNG24:" + str(destination)], check=True)
        assert struct.unpack_from(">II", destination.read_bytes(), 16) == (size, size)
    print("Prepared Afterglow app icons")


if __name__ == "__main__":
    prepare()
