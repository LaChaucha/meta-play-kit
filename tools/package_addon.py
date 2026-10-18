#!/usr/bin/env python3
"""Build a consumer ZIP containing only the installable MetaPlayKit addon."""

from __future__ import annotations

import argparse
import re
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_NAME = "metaplay_kit"
INCLUDED_PATHS = ("plugin.cfg", "plugin.gd", "plugin.gd.uid", "runtime", "assets", "README.md")


def package_version() -> str:
    config_text = (ROOT / "plugin.cfg").read_text(encoding="utf-8")
    match = re.search(r'^version\s*=\s*"([^"\r\n]+)"', config_text, re.MULTILINE)
    if match is None:
        raise ValueError("Could not read version from plugin.cfg")
    return match.group(1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Output ZIP path (defaults to dist/MetaPlayKit-<version>.zip).")
    arguments = parser.parse_args()

    version = package_version()
    output_path: Path = arguments.output or ROOT / "dist" / f"MetaPlayKit-{version}.zip"
    output_path = output_path.resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for relative_path in INCLUDED_PATHS:
            source = ROOT / relative_path
            if not source.exists():
                raise FileNotFoundError(f"Required package path is missing: {source}")
            paths = [source] if source.is_file() else sorted(source.rglob("*"))
            for path in paths:
                if path.is_file():
                    archive_name = Path(PACKAGE_NAME) / path.relative_to(ROOT)
                    archive.write(path, archive_name.as_posix())

    print(f"Created {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
