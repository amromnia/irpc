#!/usr/bin/env python3
"""Read allowlisted public .env values without executing shell code."""
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEYS = {"DISCORD_APPLICATION_ID", "APP_DISPLAY_NAME", "APP_BUNDLE_IDENTIFIER"}


def configuration(root=ROOT, environment=None):
    environment = os.environ if environment is None else environment
    values = {"APP_DISPLAY_NAME": "Afterglow", "APP_BUNDLE_IDENTIFIER": "com.amromnia.afterglow"}
    path = root / ".env"
    if path.exists():
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, separator, value = line.partition("=")
            if not separator or key.strip() not in KEYS:
                raise ValueError("Only public build keys from .env.example are supported")
            values[key.strip()] = value.strip().strip('"\'')
    values.update({key: environment[key] for key in KEYS if key in environment})
    app_id = values.get("DISCORD_APPLICATION_ID", "")
    if not re.fullmatch(r"[0-9]{17,20}", app_id) or not 0 < int(app_id) < 2**64:
        raise ValueError("Set a valid public DISCORD_APPLICATION_ID in .env or the build environment")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}", values["APP_DISPLAY_NAME"]):
        raise ValueError("APP_DISPLAY_NAME must be 1–40 plain letters, numbers, spaces, dots, underscores, or hyphens")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}", values["APP_BUNDLE_IDENTIFIER"]):
        raise ValueError("APP_BUNDLE_IDENTIFIER must be a reverse-DNS identifier")
    return values


def write(root=ROOT, environment=None):
    environment = os.environ if environment is None else environment
    values = configuration(root, environment)
    unsigned_settings = "CODE_SIGNING_ALLOWED = NO\n" if environment.get("IRPC_XTOOL") == "1" else ""
    output = root / "Config"
    output.mkdir(exist_ok=True)
    (output / "Local.xcconfig").write_text("// Generated public build values; do not edit.\n" +
        "".join(f"{key} = {value}\n" for key, value in sorted(values.items())) + unsigned_settings, encoding="utf-8")
    (output / "BuildIdentity.json").write_text(json.dumps(values, indent=2) + "\n", encoding="utf-8")
    print("Configured", values["APP_DISPLAY_NAME"], "with Discord application", values["DISCORD_APPLICATION_ID"])


if __name__ == "__main__":
    write()
