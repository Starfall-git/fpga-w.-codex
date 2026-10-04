"""Create a separate FT232H adapter config from the generated Titanium BSP.

This does not launch OpenOCD, program flash, or reset the board.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def prepare(project):
    project = project.resolve()
    project.relative_to((ROOT / "artifacts").resolve())
    folder = project / "embedded_sw/SapphireSoc/bsp/efinix/EfxSapphireSoc/openocd"
    source = folder / "ftdi_ti.cfg"
    content = source.read_text(encoding="utf-8")
    replacements = {
        'ftdi device_desc "Single RS232-HS"': 'ftdi device_desc "Single RS232-HS"',
        'ftdi vid_pid 0x0403 0x6011': 'ftdi vid_pid 0x0403 0x6014',
        'ftdi channel 1': 'ftdi channel 0',
        'ftdi_vid_pid 0x0403 0x6011': 'ftdi_vid_pid 0x0403 0x6014',
        'ftdi_channel 1': 'ftdi_channel 0',
    }
    for old, new in replacements.items():
        if content.count(old) != 1:
            raise ValueError(f"Unexpected generated adapter config: {old}")
        content = content.replace(old, new)
    target = folder / "cnn_ft232h_ti.cfg"
    target.write_text(content, encoding="utf-8")
    report = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "adapter_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
              "vid_pid": "0403:6014", "channel": 0,
              "target_id": "0x10660a79", "board_programmed": False}
    (project / "debug_adapter_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    prepare(parser.parse_args().project)
