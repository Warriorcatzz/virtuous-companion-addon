"""Check the distributable contains the main addon only, with its real TOC files."""
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath


def verify_archive(archive_path):
    root = "VirtuousCompanion/"
    toc_name = root + "VirtuousCompanion.toc"
    with zipfile.ZipFile(archive_path) as archive:
        names = [item.filename for item in archive.infolist() if not item.is_dir()]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate archive entries")
        if any(".." in PurePosixPath(name).parts or "\\" in name or not name.startswith(root) for name in names):
            raise ValueError("All files must be inside VirtuousCompanion/")
        toc = archive.read(toc_name).decode("utf-8-sig")
        if not re.search(r"^## Interface:\s*16001\s*$", toc, re.MULTILINE):
            raise ValueError("The Forever interface must stay 16001")
        if not re.search(r"^## AllowLoadGameType:\s*camelot\s*$", toc, re.MULTILINE):
            raise ValueError("The package must target the Forever/Camelot client")
        if not re.search(r"^## OptionalDeps:\s*VirtuousCompanion_Data\s*$", toc, re.MULTILINE):
            raise ValueError("Generated user data must remain an optional separate addon")
        version = re.search(r"^## Version:\s*(\S+)\s*$", toc, re.MULTILINE)
        if not version or not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:alpha|beta)\.\d+)?", version[1]):
            raise ValueError("The packaged addon needs a concrete version")
        expected_lua = {"Core.lua", "Bridge.lua", "DiscordRoster.lua", "GuildRanks.lua", "UI.lua"}
        toc_files = {line.strip() for line in toc.splitlines() if line.strip() and not line.lstrip().startswith("#")}
        if toc_files != expected_lua:
            raise ValueError("Unexpected runtime files in the TOC; review the packaging allowlist")
        required = {root + name for name in expected_lua} | {toc_name}
        allowed = required | {root + "CHANGELOG.md"}
        if set(names) - allowed or required - set(names):
            raise ValueError(f"Unexpected or missing packaged files: {sorted((set(names) - allowed) | (required - set(names)))}")
        for name in required:
            if not archive.read(name):
                raise ValueError(f"Empty runtime file: {name}")
    print(f"Verified {Path(archive_path).name}: version {version[1]}, {len(names)} files, Forever 1.60.1, main addon only")


if __name__ == "__main__":
    archives = list(Path(".release").glob("*.zip")) if len(sys.argv) == 1 else [Path(name) for name in sys.argv[1:]]
    if len(archives) != 1:
        raise ValueError("Expected exactly one addon ZIP")
    verify_archive(archives[0])
