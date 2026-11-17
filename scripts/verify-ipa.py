#!/usr/bin/env python3
"""Check the actual portable bundle, including resources and Mach-O dependencies."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def dylibs(binary):
    magic, _, _, _, count, _, _, _ = struct.unpack_from("<8I", binary)
    assert magic == 0xFEEDFACF, "Expected a 64-bit little-endian Mach-O executable"
    offset = 32
    result = []
    for _ in range(count):
        command, size = struct.unpack_from("<II", binary, offset)
        assert size >= 8 and offset + size <= len(binary), "Invalid Mach-O load command"
        if command in (0xC, 0x18 | 0x80000000, 0x1F | 0x80000000):
            name_offset = struct.unpack_from("<I", binary, offset + 8)[0]
            result.append(binary[offset + name_offset:offset + size].split(b"\0", 1)[0].decode())
        offset += size
    return result


def verify(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "Corrupt IPA archive"
        names = archive.namelist()
        plist_name = next(n for n in names if n.startswith("Payload/") and n.count("/") == 2 and n.endswith("/Info.plist"))
        prefix = plist_name.removesuffix("Info.plist")
        info = plistlib.loads(archive.read(plist_name))
        assert info["CFBundleIdentifier"] == "dev.adrian.ios.iRPC"
        assert info["MinimumOSVersion"] == "17.6"
        assert info["NSAppleMusicUsageDescription"]
        assert info["BGTaskSchedulerPermittedIdentifiers"] == [info["CFBundleIdentifier"] + ".presence"]
        assert "processing" in info["UIBackgroundModes"]
        assert info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconFiles"]
        assert prefix + "embedded.mobileprovision" not in names, "Expected an unsigned/unprovisioned bundle"
        assert not any(n.startswith(prefix) and n.endswith("Contents.json") for n in names), "Catalog JSON leaked into bundle"
        icons = ROOT / "iRPC/Assets.xcassets/AppIcon.appiconset"
        for icon in json.loads((icons / "Contents.json").read_text())["images"]:
            source = icons / icon["filename"]
            assert archive.read(prefix + source.name) == source.read_bytes(), source.name
        glyph = archive.read(prefix + "Discord@3x.png")
        assert glyph.startswith(b"\x89PNG\r\n\x1a\n"), "Missing/invalid Discord glyph PNG"
        assert struct.unpack_from(">I", glyph, 16)[0] == 96, "Unexpected Discord glyph resolution"
        binary = archive.read(prefix + info["CFBundleExecutable"])
        offset = 32
        for _ in range(struct.unpack_from("<I", binary, 16)[0]):
            command, size = struct.unpack_from("<II", binary, offset)
            assert command != 0x1D, "Expected app executable without a code signature"
            offset += size
        dependencies = dylibs(binary)
        assert not any("SwiftData" in name for name in dependencies), dependencies
        for required in ("MusicKit", "BackgroundTasks", "discord_partner_sdk"):
            assert any(required in name for name in dependencies), (required, dependencies)
        framework = prefix + "Frameworks/discord_partner_sdk.framework/discord_partner_sdk"
        assert framework in names, "Discord dynamic framework was not embedded"
        print("Verified:", path)
        print("Bundle:", info["CFBundleIdentifier"], "minimum iOS", info["MinimumOSVersion"])
        print("Linked libraries:", *dependencies, sep="\n  ")
        print("IPA SHA-256:", hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == "__main__":
    candidates = sorted((ROOT / "xtool").rglob("*.ipa"), key=lambda p: p.stat().st_mtime)
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else (candidates[-1] if candidates else None)
    if path is None:
        raise SystemExit("No IPA found under xtool/. Check build/xtool-build.log.")
    verify(path)
