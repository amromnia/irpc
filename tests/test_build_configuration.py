import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("build_configuration", Path(__file__).parents[1] / "scripts/configure-app.py")
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class BuildConfigurationTests(unittest.TestCase):
    def test_local_values_and_explicit_environment_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".env").write_text("DISCORD_APPLICATION_ID=1572242579049808028\nAPP_DISPLAY_NAME=Afterglow\n")
            config.write(root, {"APP_DISPLAY_NAME": "My Soundtrack"})
            result = json.loads((root / "Config/BuildIdentity.json").read_text())
            self.assertEqual(result["APP_DISPLAY_NAME"], "My Soundtrack")
            self.assertEqual(result["DISCORD_APPLICATION_ID"], "1572242579049808028")
            self.assertIn("APP_DISPLAY_NAME = My Soundtrack", (root / "Config/Local.xcconfig").read_text())

    def test_configuration_rejects_secrets_and_code(self):
        for line in ("DISCORD_CLIENT_SECRET=secret", "APP_DISPLAY_NAME=$(run-me)", "APP_BUNDLE_IDENTIFIER=bad/path"):
            with self.subTest(line=line), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / ".env").write_text("DISCORD_APPLICATION_ID=1572242579049808028\n" + line)
                with self.assertRaises(ValueError):
                    config.configuration(root, {})

    def test_portable_build_disables_signing_for_embedded_extensions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            values = {"DISCORD_APPLICATION_ID": "1572242579049808028", "IRPC_XTOOL": "1"}
            config.write(root, values)
            self.assertIn("CODE_SIGNING_ALLOWED = NO", (root / "Config/Local.xcconfig").read_text())
            values.pop("IRPC_XTOOL")
            config.write(root, values)
            self.assertNotIn("CODE_SIGNING_ALLOWED", (root / "Config/Local.xcconfig").read_text())

    def test_an_application_id_is_required(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                config.configuration(Path(directory), {})


if __name__ == "__main__":
    unittest.main()
