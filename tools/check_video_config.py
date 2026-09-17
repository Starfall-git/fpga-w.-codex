"""Check the 720p recovery baseline without requiring FPGA hardware.

Run: python tools/check_video_config.py
This checks configuration consistency, not electrical operation or RTL timing.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NS = {"p": "http://www.efinixinc.com/peri_design_db"}


def rtl(path):
    # Vendor comments use mixed legacy encodings; HDL tokens are ASCII.
    text = path.read_text(encoding="utf-8", errors="replace")
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def main():
    top = rtl(ROOT / "example_top.v")
    sensor = rtl(ROOT / "src/cmos_i2c/I2C_OV5640_1280720_Config.v")
    timing = rtl(ROOT / "src/lcd_para.v")
    assert re.search(r"IMAGE_WIDTH\s*=\s*16'd1280", sensor)
    assert re.search(r"IMAGE_HEIGHT\s*=\s*16'd720", sensor)
    assert re.search(r"`define\s+VGA_1280_720_60FPS_74_25MHz", timing)
    assert not re.search(r"`define\s+VGA_1920_1080", timing)
    for name in ("IMAGE_HSIZE_SOURCE", "IMAGE_HSIZE_TARGET"):
        assert re.search(rf"\.{name}\s*\(1280\s*\*\s*2\s*/\s*CSI_STRB_WIDTH\)", top)
    for name in ("IMAGE_VSIZE_SOURCE", "IMAGE_YSIZE_TARGET"):
        assert re.search(rf"\.{name}\s*\(720\s*\)", top)
    assert re.search(r"\.C_RD_END_ADDR\(1280\s*\*\s*2\s*\*\s*720\)", top)
    assert "sys_pll_lock && ddr_pll_lock && cam_pll_lock" in top
    assert "assign cam_pll_rstn_o = sys_pll_lock" in top
    assert "parameter HDMI_TEST_PATTERN = 0" in top

    peri = ET.parse(ROOT / "Ti60_Demo.peri.xml").getroot()
    ref = ET.parse(ROOT / "02-1_Ti60_OV5640_LCD-HDMI_1080P60/work_pt/peri_load.bak").getroot()
    cam = peri.find("p:gpio_info/p:comp_gpio[@name='cmos_xclk']", NS)
    assert cam is not None, "Camera XCLK pad was removed"
    assert cam.get("gpio_def") == "GPIOR_16" and cam.get("mode") == "clkout"
    assert cam.find("p:output_config", NS).get("clock_name") == "clk_cam_xclk"
    pll = peri.find("p:pll_info/p:pll[@name='cam_pll']", NS)
    assert pll is not None and pll.get("pll_def") == "PLL_TR0"
    assert pll.get("ref_clock_name") == "clk_sys"
    assert pll.get("reset_name") == "cam_pll_rstn_o"
    assert pll.get("locked_name") == "cam_pll_lock"
    clocks = {c.get("name"): c for c in pll.findall("p:comp_output_clock", NS)}
    assert set(clocks) == {"clk_cam_feedback", "clk_cam_xclk"}
    assert clocks["clk_cam_feedback"].get("out_divider") == "28"
    assert clocks["clk_cam_xclk"].get("out_divider") == "84"

    def semantic(node):
        return node.tag, dict(node.attrib), [semantic(c) for c in node]

    for name in ("sys_pll", "ddr_pll"):
        query = f"p:pll_info/p:pll[@name='{name}']"
        assert semantic(peri.find(query, NS)) == semantic(ref.find(query, NS)), name
    lanes = peri.findall("p:lvds_info/p:lvds", NS)
    assert {c.get("name") for c in lanes} == {"hdmi_txc", "hdmi_txd0", "hdmi_txd1", "hdmi_txd2"}
    for lane in lanes:
        old = ref.find(f"p:lvds_info/p:lvds[@name='{lane.get('name')}']", NS)
        assert semantic(lane) == semantic(old), lane.get("name")
    print("PASS: 720p sensor/crop/frame/display configuration")
    print("PASS: camera reference clock route and reset dependency")
    print("PASS: system/DDR PLLs and all four HDMI lanes match original demo")


if __name__ == "__main__":
    main()
