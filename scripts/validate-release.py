"""Validate release identity before granting publishing jobs access to credentials."""
import re
import subprocess
import sys
from pathlib import Path


def validate_tag(tag):
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-(?:alpha|beta)\.\d+)?", tag):
        raise ValueError("Use a version tag such as v0.8.5, v0.8.6-beta.1 or v0.8.6-alpha.1")
    toc = Path("VirtuousCompanion.toc").read_text(encoding="utf-8-sig")
    version = re.search(r"^## Version:\s*(\S+)\s*$", toc, re.MULTILINE)
    if not version or version[1] != tag[1:]:
        raise ValueError("The tag must match ## Version in VirtuousCompanion.toc")
    tagged_commit = subprocess.check_output(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"], text=True).strip()
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if tagged_commit != head:
        raise ValueError("Checkout must point to the requested version tag")
    print(f"Validated {tag} at {head}")


if __name__ == "__main__":
    validate_tag(sys.argv[1])
