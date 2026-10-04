"""Prepare an isolated DDR3/Sapphire hardware workspace; never programs a board.

Vendor RTL stays in ignored artifacts. The official 2026 SoC configuration is
adapted explicitly; a generated BSP is required before rebuilding firmware.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NS = "http://www.efinixinc.com/enf_proj"
ET.register_namespace("efx", NS)


def prepare(vendor, upstream, out):
    vendor, upstream, out = (Path(x).resolve() for x in (vendor, upstream, out))
    out.relative_to((ROOT / "artifacts").resolve())
    if out.exists():
        raise FileExistsError(out)
    old_project = vendor / "Ti60F225_tinyml_helloworld.xml"
    official = upstream / "tinyml_hello_world/Ti60F225_tinyml_hello_world/ip/SapphireSoc/settings.json"
    config = json.loads(official.read_text())
    tree = ET.parse(old_project)
    out.mkdir(parents=True)
    for folder in ("src", "sdc", "ip"):
        shutil.copytree(vendor / folder, out / folder,
                        ignore=shutil.ignore_patterns("sapphire_soc", "__pycache__"))
    shutil.copy2(vendor / "debug_top.v", out / "debug_top.v")
    shutil.copy2(vendor / "Ti60F225_tinyml_helloworld.peri.xml", out / "cnn_static.peri.xml")
    project = tree.getroot()
    # Do not inherit the historical 'pass' state of the vendor build.
    for key in list(project.attrib):
        if key not in ("name", "description") and not key.startswith("{"):
            del project.attrib[key]
    project.set("name", "cnn_static")
    project.set("sw_version", "2026.1.132.3.9")
    for node in project.iter():
        if node.tag == f"{{{NS}}}timing_model":
            node.set("name", "C4")
        for key, value in list(node.attrib.items()):
            node.set(key, value.replace("Ti60F225_tinyml_helloworld", "cnn_static").replace("sapphire_soc", "SapphireSoc"))
    tree.write(out / "cnn_static.xml", encoding="utf-8", xml_declaration=True)
    top = out / "src/tinyml_soc_top.v"
    content = top.read_bytes().replace(b"sapphire_soc u_sapphire_soc", b"SapphireSoc u_sapphire_soc")
    # Return AXI write status; never leave active SoC inputs floating.
    replacements = {
        b".io_ddrA_b_payload_resp             (                                  )":
            b".io_ddrA_b_payload_resp             (axi_inter_s0_bresp                 )",
        b".system_spi_0_io_data_2_read        (                                   )":
            b".system_spi_0_io_data_2_read        (1'b0                               )",
        b".system_spi_0_io_data_3_read        (                                   )":
            b".system_spi_0_io_data_3_read        (1'b0                               )",
        b".userInterruptB                     (userInterruptB)":
            b".userInterruptB                     (1'b0)",
    }
    for old, new in replacements.items():
        if content.count(old) != 1:
            raise ValueError(f"Vendor wrapper changed: {old!r}")
        content = content.replace(old, new)
    top.write_bytes(content)
    # The original peripheral PLL output remains 100 MHz; make CPU equal to it.
    peri_path = out / "cnn_static.peri.xml"
    peri = ET.parse(peri_path)
    changes = 0
    for node in peri.iter():
        if node.tag.endswith("}comp_output_clock") and node.get("name") == "i_sysclk":
            assert node.get("out_divider") == "9"
            node.set("out_divider", "27")
            changes += 1
    assert changes == 1
    peri.write(peri_path, encoding="utf-8", xml_declaration=True)
    for sdc in (out / "sdc").glob("*.sdc"):
        content = sdc.read_text()
        content = content.replace("create_clock -period 3.333 -name i_sysclk", "create_clock -period 10.000 -name i_sysclk")
        sdc.write_text(content)
    overrides = {"DEVKIT": "0", "Frequency": "100", "PeriFrequency": "100",
                 "DDR_AXI4": "1'b1", "DDRCLK_DOMAIN": "1", "DDR_OPT": "1",
                 "GPIO0": "1'b0", "I2C0": "1'b0", "APBSlave1": "1'b0",
                 "DEVKIT_CUSTOM": '"Single RS232-HS"',
                 "DDRSize": "32'd268435456", "LDSize": "131068",
                 "HexFile_PathEnable": "1'b0", "HexFile_Path": '"\'\'"'}
    config["conf"].update(overrides)
    (out / "sapphire_config.json").write_text(json.dumps(config["conf"], indent=2))
    report = {"vendor": str(vendor), "official_settings": str(official),
              "official_settings_sha256": hashlib.sha256(official.read_bytes()).hexdigest(),
              "overrides": overrides, "timing_model": "C4", "cpu_clock_mhz": 100,
              "hardware_compiled": False, "programmed": False,
              "note": "Candidate only: old DDR3 wrapper/RTL ports and SDC still require validation"}
    (out / "prepare_report.json").write_text(json.dumps(report, indent=2))
    print(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vendor", required=True, type=Path)
    parser.add_argument("--upstream", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    prepare(args.vendor, args.upstream, args.output)
