import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_package", ROOT / "scripts/verify-package.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class PackageTest(unittest.TestCase):
    def package(self, extra=None, omit=None, toc=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        filename = Path(temporary.name) / "addon.zip"
        names = ["VirtuousCompanion.toc", "Core.lua", "Bridge.lua", "DiscordRoster.lua", "GuildRanks.lua", "UI.lua"]
        with zipfile.ZipFile(filename, "w") as archive:
            for name in names:
                if name == omit:
                    continue
                content = toc if name.endswith(".toc") and toc is not None else (ROOT / name).read_bytes()
                archive.writestr("VirtuousCompanion/" + name, content)
            archive.writestr("VirtuousCompanion/CHANGELOG.md", "Release notes")
            for name, content in (extra or {}).items():
                archive.writestr(name, content)
        return filename

    def test_accepts_main_addon_and_keeps_savedvariables_declaration(self):
        verifier.verify_archive(self.package())

    def test_rejects_generated_member_data_and_saved_databases(self):
        for filename in ["VirtuousCompanion_Data/Data.lua", "VirtuousCompanion/Data.lua", "VirtuousCompanion/SavedVariables/VirtuousCompanion.lua"]:
            with self.subTest(filename=filename), self.assertRaises(ValueError):
                verifier.verify_archive(self.package(extra={filename: "private data"}))

    def test_rejects_development_files_and_credentials(self):
        for filename in ["VirtuousCompanion/.env", "VirtuousCompanion/tests/example.lua", "VirtuousCompanion/scripts/upload.py", "VirtuousCompanion/Companion.exe"]:
            with self.subTest(filename=filename), self.assertRaises(ValueError):
                verifier.verify_archive(self.package(extra={filename: "development only"}))

    def test_rejects_unsafe_paths(self):
        for filename in ["../Data.lua", "/VirtuousCompanion/Data.lua", "VirtuousCompanion/../Data.lua", "VirtuousCompanion\\Data.lua"]:
            with self.subTest(filename=filename), self.assertRaises(ValueError):
                verifier.verify_archive(self.package(extra={filename: "unexpected"}))

    def test_rejects_wrong_client(self):
        toc = (ROOT / "VirtuousCompanion.toc").read_text().replace("16001", "120100")
        with self.assertRaisesRegex(ValueError, "Forever interface"):
            verifier.verify_archive(self.package(toc=toc))

    def test_rejects_missing_runtime_file(self):
        with self.assertRaises(ValueError):
            verifier.verify_archive(self.package(omit="GuildRanks.lua"))


if __name__ == "__main__":
    unittest.main()
