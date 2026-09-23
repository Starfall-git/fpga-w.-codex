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
    # V0.7 / 34: check the active AR0135 configuration, not the retained OV LUT.
    sensor = rtl(ROOT / "src/cmos_i2c/I2C_AR0135_1280720_Config.v")
    timing = rtl(ROOT / "src/lcd_para.v")
    registers = {int(a, 16): int(b, 16) for a, b in
                 re.findall(r"\{16'h([0-9a-fA-F]+),\s*16'h([0-9a-fA-F]+)\}", sensor)}
    assert registers[0x3008] - registers[0x3004] + 1 == 1280
    assert registers[0x3006] - registers[0x3002] + 1 == 720
    assert registers[0x3064] & 0x180 == 0x180  # AE metadata/stats retained
    assert registers[0x3028] == 0x10  # launch falling, capture rising
    assert 27 * registers[0x3030] / registers[0x302E] / registers[0x302C] / registers[0x302A] == 74.25
    assert re.search(r"`define\s+VGA_1280_720_60FPS_74_25MHz", timing)
    assert not re.search(r"`define\s+VGA_1920_1080", timing)
    assert "ar0135_capture" in top and ".WIDTH(1280), .HEIGHT(720), .EMBEDDED_ROWS(2)" in top
    assert ".C_W_WIDTH(16)" in top
    assert re.search(r"assign\s+cmos_ctl1_oe\s*=\s*0", top)
    assert "I2C_OV5640_1280720_Config" not in top
    assert re.search(r"\.C_RD_END_ADDR\(1280\s*\*\s*2\s*\*\s*720\)", top)
    assert "sys_pll_lock && ddr_pll_lock && cam_pll_lock" in top
    assert "assign cam_pll_rstn_o = sys_pll_lock" in top
    assert "parameter HDMI_TEST_PATTERN = 0" in top

    peri = ET.parse(ROOT / "Ti60_AR0135.peri.xml").getroot()
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
    assert clocks["clk_cam_feedback"].get("out_divider") == "27"
    assert clocks["clk_cam_xclk"].get("out_divider") == "48"
    for name in [f"cmos_data[{i}]" for i in range(8)] + ["cmos_href", "cmos_vsync"]:
        config = peri.find(f"p:gpio_info/p:comp_gpio[@name='{name}']/p:input_config", NS)
        assert config.get("clock_name") == "cmos_pclk" and config.get("is_clock_inverted") == "false"
    sdc = (ROOT / "Ti60_AR0135.pt.sdc").read_text()
    assert "create_clock -period 37.0370 clk_cam_xclk" in sdc
    assert "create_clock -period 13.4680 [get_ports {cmos_pclk}]" in sdc
    # V0.7: dedicated entry avoids the already-open OV project overwriting new files.
    project = (ROOT / "Ti60_AR0135.xml").read_text()
    assert "src/cmos_i2c/ar0135_init.v" in project and "src/cmos_i2c/ar0135_capture.v" in project
    assert 'name="Ti60_AR0135.peri.xml"' in project
    assert 'name="Ti60_AR0135.pt.sdc"' in project

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
