"""Add a JTAG-visible status record to the already adapted official EVSoC app.

Only replaces the derived static main; the official runtime and hardware stay put.
Refuses unrecorded edits. Run build_evsoc_application.py afterwards.
"""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "artifacts/evsoc-system-r1"
APP = PROJECT / "embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_gesture"
SOURCE = APP / "src/main.cc"
MARKER = "// Replacement for the YOLO demo's main() during static accelerator validation."


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    report = json.loads((PROJECT / "official_build_report.json").read_text(encoding="utf-8"))
    original = SOURCE.read_text(encoding="utf-8")
    prior = PROJECT / "debug_firmware_preparation.json"
    prepared = json.loads(prior.read_text(encoding="utf-8")) if prior.exists() else None
    expected_sha = prepared["main_sha256"] if prepared else report["main_sha256"]
    if sha(SOURCE) != expected_sha:
        raise RuntimeError("main.cc differs from the last build report; inspect it first")
    if "CNN_DDR3_PERIPHERALS" not in original or original.count(MARKER) != 1:
        raise RuntimeError("Expected the adapted DDR3 official application")
    backup = PROJECT / "history/static-before-debug"
    if not prepared:
        backup.mkdir(parents=True, exist_ok=False)
        shutil.copy2(SOURCE, backup / "main.cc")
        shutil.copy2(APP / "build/evsoc_tinyml_gesture.elf", backup)
        shutil.copy2(PROJECT / "official_build_report.json", backup)
    template = ROOT / "firmware/evsoc_gesture/debug_main.inc"
    SOURCE.write_text(original.split(MARKER)[0] + template.read_text(encoding="utf-8"), encoding="utf-8")
    result = {"previous_main_sha256": (prepared or report).get("previous_main_sha256", report["main_sha256"]), "main_sha256": sha(SOURCE),
              "template_sha256": sha(template), "board_run_verified": False,
              "purpose": "JTAG-readable stages and three static INT8 results; no camera inference"}
    (PROJECT / "debug_firmware_preparation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
