"""Build the derived EVSoC app with its original Makefile and official SDK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(project, sdk):
    project, sdk = project.resolve(), sdk.resolve()
    project.relative_to((ROOT / "artifacts").resolve())
    app = project / "embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_ypd"
    bsp = project / "embedded_sw/SapphireSoc/bsp/efinix/EfxSapphireSoc"
    make = sdk / "build_tools/bin/make.exe"
    toolchain = sdk / "toolchain/bin"
    env = os.environ.copy()
    env["PATH"] = os.pathsep.join((str(toolchain), str(make.parent), env.get("PATH", "")))
    command = [str(make), "-j4", "BSP=efinix/EfxSapphireSoc", "all"]
    result = subprocess.run(command, cwd=app, env=env, capture_output=True, text=True, errors="replace")
    (project / "official-make.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    result.check_returncode()
    elf = app / "build/evsoc_tinyml_ypd.elf"
    size = subprocess.check_output([str(toolchain / "riscv-none-elf-size.exe"), str(elf)], text=True)
    readelf = subprocess.check_output([str(toolchain / "riscv-none-elf-readelf.exe"), "-A", str(elf)], text=True)
    report = {"command": command, "application": str(app), "make_return_code": result.returncode,
              "elf_sha256": sha(elf), "main_sha256": sha(app / "src/main.cc"),
              "makefile_sha256": sha(app / "makefile"),
              "linker_sha256": sha(bsp / "linker/default.ld"), "soc_header_sha256": sha(bsp / "include/soc.h"),
              "tinyml_library_sha256": sha(app.parent / "common/tinyml_lib.a"),
              "model_array_sha256": sha(app / "src/model/gesture_int8_model_data.cc"),
              "size_output": size, "elf_attributes": readelf,
              "bsp_source": "copied official EVSoC HyperRAM demo; not final integrated DDR3 BSP",
              "tensor_arena_ceiling": 262144, "application_scratch_capacity": 500000,
              "arena_used_bytes": None, "hardware_verified": False, "target_run_verified": False,
              "note": "ELF validates official make/runtime compatibility only; do not download to existing video bitstream"}
    (project / "official_build_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--sdk", type=Path, required=True)
    args = parser.parse_args()
    build(args.project, args.sdk)
