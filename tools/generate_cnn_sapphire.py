"""Run with Efinity bin/python3.bat using the supplied IP Manager Python API."""
import json
import os
from pathlib import Path
import sys

project = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[1]
project.relative_to((root / "artifacts").resolve())
sys.path.append(str(Path(os.environ["EFXIPM_HOME"]) / "bin"))
from ipm_api_service.design import IPMDesignAPI
from ipm_api_service.projectxml import ProjectXML
from gui.api_wrapper import ResultCode

design = IPMDesignAPI("Ti60F225", "Titanium", project_path=project, is_verbose=True)
created = design.create_ip("SapphireSoc", "efinixinc.com", "soc", "efx_soc")
if not created:
    raise RuntimeError("Sapphire IP unavailable")
config = json.loads((project / "sapphire_config.json").read_text())
design.config_ip("SapphireSoc", config)
valid, diagnostics, _ = design.validate_ip("SapphireSoc")
if not valid:
    raise RuntimeError(f"IP parameter validation failed: {diagnostics}")
if design.generate_ip("SapphireSoc") != ResultCode.SUCCESS:
    raise RuntimeError("IP generation failed")
xml = ProjectXML(project_xml_path=project / "cnn_static.xml", is_verbose=True)
if not xml.is_ip_exists(module_name="SapphireSoc"):
    xml.add_ip(module_name="SapphireSoc")
    xml.save()
required = ["ip/SapphireSoc/SapphireSoc.v", "ip/SapphireSoc/SapphireSoc_tmpl.v",
            "embedded_sw/SapphireSoc/bsp/efinix/EfxSapphireSoc/include/soc.h"]
for name in required:
    if not (project / name).is_file():
        raise FileNotFoundError(project / name)
print("PASS: Sapphire RTL, template and matching BSP generated")
