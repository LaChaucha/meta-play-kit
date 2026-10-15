"""Extract the small set of legacy visuals used by the Godot 4 demo.

The archived Godot 3 project remains untouched under ``interfaces/testAddons``.
This script delegates all image writes to the Godot skill's ``process_image``
operation so the extraction is reproducible and independently verifiable.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


PROJECT = Path(__file__).resolve().parents[2]
SKILL = Path(os.environ.get(
    "GODOT_SKILL_PATH",
    r"C:\Users\edgam\.codex-personal\skills\godot",
))
DISPATCHER = SKILL / "scripts" / "core" / "dispatcher.gd"
DEFAULT_GODOT = Path(os.environ.get(
    "METAPLAY_GODOT",
    shutil.which("godot") or "",
))
ATLAS = "interfaces/testAddons/modules/ttp-gui/assets/sprites/atlas/home-0.png"


CROPS: tuple[tuple[str, int, int, int, int], ...] = (
    ("loading_background", 1, 1, 1280, 720),
    ("panel_large", 1, 723, 561, 445),
    ("panel_result", 564, 723, 444, 377),
    ("level_selector", 1283, 1, 674, 225),
    ("icon_settings", 1959, 179, 85, 85),
    ("icon_store", 1682, 1108, 128, 128),
    ("icon_levels", 1552, 1108, 128, 128),
    ("icon_video", 1918, 412, 109, 109),
    ("icon_music", 1741, 982, 118, 118),
    ("icon_sfx", 1812, 1102, 118, 118),
    ("icon_coin", 1993, 1024, 51, 56),
    ("star_on", 1931, 1024, 60, 61),
    ("star_off", 1861, 1024, 68, 71),
    ("icon_next", 1763, 700, 109, 109),
    ("icon_retry", 1877, 826, 109, 109),
    ("icon_cancel", 1939, 523, 102, 103),
    ("icon_confirm", 1939, 727, 97, 97),
    ("icon_reward", 1574, 531, 187, 185),
)


def dispatch(godot: Path, payload: dict[str, object]) -> None:
    command = [
        str(godot),
        "--headless",
        "--path",
        str(PROJECT),
        "--script",
        str(DISPATCHER),
        "process_image",
        json.dumps(payload, separators=(",", ":")),
    ]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stdout + result.stderr)


def main() -> int:
    godot = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT_GODOT
    if not godot.is_file():
        print(f"Godot console executable not found: {godot}", file=sys.stderr)
        return 2

    for asset_name, x, y, width, height in CROPS:
        dispatch(godot, {
            "input_path": ATLAS,
            "output_path": f"addons/metaplay_kit/assets/ui/{asset_name}.png",
            "operations": [{
                "type": "crop",
                "x": x,
                "y": y,
                "width": width,
                "height": height,
            }],
            "ascii": False,
            "describe": False,
        })
        print(f"extracted addons/metaplay_kit/assets/ui/{asset_name}.png")

    dispatch(godot, {
        "input_path": "interfaces/testAddons/assets/sprites/Concept_A.png",
        "output_path": "demo/assets/world/home_room.png",
        "operations": [
            {"type": "crop", "x": 58, "y": 55, "width": 1282, "height": 720},
            {"type": "resize", "width": 1280, "height": 720, "filter": "lanczos"},
        ],
        "ascii": False,
        "describe": False,
    })
    print("extracted demo/assets/world/home_room.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
