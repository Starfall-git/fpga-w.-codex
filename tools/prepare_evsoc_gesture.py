"""Copy the user's official YOLO EVSoC baseline into an isolated candidate.

Preserve the complete vendor source and relative BSP layout. The copied project
is explicitly not ready for this DDR3/AR0135/HDMI board until integration passes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source, generated, out):
    source, generated, out = (Path(p).resolve() for p in (source, generated, out))
    out.relative_to((ROOT / "artifacts").resolve())
    if out.exists():
        raise FileExistsError(out)
    app_rel = Path("embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_ypd")
    required = [Path("edge_vision_soc.v"), Path("edge_vision_soc.xml"), app_rel / "src/main.cc"]
    for rel in required:
        if not (source / rel).is_file():
            raise FileNotFoundError(source / rel)
    report = json.loads((generated / "generation_report.json").read_text())
    for rel, sha in report["files"].items():
        if digest(generated / rel) != sha:
            raise ValueError(f"Generated artifact changed: {rel}")
    shutil.copytree(source, out, ignore=shutil.ignore_patterns(
        "outflow", "work_syn", "work_pnr", "work_pt", "ooc", "build", ".metadata", ".git", "__pycache__"))
    provenance = out / "reference_original"
    provenance.mkdir()
    for rel in required:
        shutil.copy2(source / rel, provenance / rel.name)
    shutil.copy2(ROOT / "example_top.v", provenance / "example_top.v")
    generated_files = generated / "output/gesture_int8_core0"
    shutil.copy2(generated_files / "tinyml_core0_define.v", out / "source/tinyml/tinyml_core0_define.v")
    model_dest = out / app_rel / "src/model"
    for suffix in ("cc", "h"):
        shutil.copy2(generated_files / f"gesture_int8_model_data.{suffix}", model_dest)
    # Do not pretend the unmodified YOLO postprocessor can consume class logits.
    (out / "INTEGRATION_REQUIRED.md").write_text(
        "# Integration candidate — NOT board-ready\n\n"
        "Official YOLO main.cc is preserved as the source baseline. The generated gesture model and RTL parameters are staged, "
        "but main.cc is not switched yet. Before building/downloading, adapt its input contract, resolver and classification postprocessor; "
        "replace CSI/HyperRAM/DSI with the isolated AR0135/DDR3/HDMI connections; generate matching Sapphire BSP; "
        "verify memory ownership, CDC, video priority, UART controls and frame-boundary overlay.\n",
        encoding="utf-8")
    manifest = {"source": str(source), "application_workspace": str(out / app_rel),
                "bsp_root": str(out / "embedded_sw/SapphireSoc"),
                "source_sha256": {str(p): digest(source / p) for p in required},
                "video_top_sha256": digest(ROOT / "example_top.v"),
                "model_sha256": report["model_sha256"],
                "generator_sha256": report["generator_sha256"],
                "generated_files": report["files"],
                "main_adapted": False, "hardware_integrated": False,
                "hardware_compiled": False, "board_verified": False}
    (out / "integration_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--generated", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.source, args.generated, args.output)
