"""Prepare the actual DDR3 video checkout plus an official EVSoC Sapphire config.
No IP generation, compilation, download or original-project mutation is implicit.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def prepare(output):
    out = Path(output).resolve()
    out.relative_to((ROOT / "artifacts").resolve())
    if out.exists():
        raise FileExistsError(out)
    official = ROOT / "artifacts/evsoc-gesture-r1"
    settings = official / "ip/SapphireSoc/settings.json"
    original = json.loads(settings.read_text())["conf"]
    config = dict(original)
    # Keep the official combined 128-bit DDR interface and custom instruction
    # configuration. All three SoC clocks will use the existing 96 MHz AXI clock.
    overrides = {"DEVKIT": "0", "DEVKIT_CUSTOM": '\"Single RS232-HS\"',
                 "Frequency": "96", "PeriFrequency": "96",
                 "DDR_AXI4": "1'b0", "DDRCLK_DOMAIN": "1", "DDR_OPT": "1",
                 "DDRSize": "32'd67108864", "LDSize": "65532",
                 "GPIO0": "1'b0", "I2C0": "1'b0", "APBSlave0": "1'b0",
                 "APBSlave1": "1'b1", "HexFile_PathEnable": "1'b0",
                 "HexFile_Path": '\"\'\'\"'}
    config.update(overrides)
    out.mkdir(parents=True)
    ignore = shutil.ignore_patterns("work", "outflow", "__pycache__", "*.log", "ooc")
    for folder in ("src", "sdc", "ip"):
        if (ROOT / folder).is_dir():
            shutil.copytree(ROOT / folder, out / folder, ignore=ignore)
    for name in ("example_top.v", "Ti60_AR0135.xml", "Ti60_AR0135.peri.xml"):
        shutil.copy2(ROOT / name, out / name)
    # Vendor sources stay in ignored artifacts; preserve licensing and provenance.
    shutil.copytree(official / "source", out / "official_source", ignore=ignore)
    (out / "sapphire_config.json").write_text(json.dumps(config, indent=2))
    inputs = [ROOT / "example_top.v", ROOT / "Ti60_AR0135.xml", ROOT / "Ti60_AR0135.peri.xml",
              ROOT / "ip/DdrCtrl/settings.json", settings, official / "edge_vision_soc.v"]
    report = {"source_checkout": str(ROOT), "output": str(out), "overrides": overrides,
              "inputs_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
              "axi_cpu_peripheral_mhz": 96, "physical_ddr_configuration_changed": False,
              "logical_ai_memory_bytes": 67108864,
              "planned_physical_ai_base": "0x04000000",
              "memory_translation_implemented": False, "top_integrated": False,
              "hardware_compiled": False, "programmed": False,
              "notes": ["48 MiB video storage must remain protected.",
                        "Both CPU and accelerator need the same checked logical-to-physical translation.",
                        "SoC IP is not yet wired into example_top; generated BSP is not board-ready."]}
    (out / "prepare_report.json").write_text(json.dumps(report, indent=2))
    print(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    prepare(parser.parse_args().output)
