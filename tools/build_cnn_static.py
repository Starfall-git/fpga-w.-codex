"""Cross-build a static software-kernel probe using a supplied vendor DDR3 BSP.

Reads vendor files only; copies dependencies under ignored artifacts/. Does not
generate hardware, flash a board or link against the video DDR address map.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(vendor, runtime, sdk, bundle, out):
    vendor, sdk, bundle, out = (Path(p).resolve() for p in (vendor, sdk, bundle, out))
    if out.exists():
        raise FileExistsError(f"Choose a new output directory: {out}")
    # Outputs must be within this isolated checkout's artifact directory.
    out.relative_to((ROOT / "artifacts").resolve())
    compiler = sdk / "toolchain/bin/riscv-none-elf-g++.exe"
    gcc = sdk / "toolchain/bin/riscv-none-elf-gcc.exe"
    runtime = Path(runtime).resolve()
    vendor_src = runtime / "software/standalone/tinyml_imgc/src"
    bsp = vendor / "bsp/efinix/EfxSapphireSoc"
    linker = bsp / "linker/default.ld"
    for path in (compiler, gcc, linker, vendor_src / "main.cc", bundle / "bundle_manifest.json"):
        if not path.is_file():
            raise FileNotFoundError(path)
    manifest = json.loads((bundle / "bundle_manifest.json").read_text(encoding="utf-8"))
    for name, expected in manifest["files"].items():
        p = (bundle / name).resolve()
        p.relative_to(bundle)
        if digest(p) != expected:
            raise ValueError(f"Bundle checksum mismatch: {name}")
    out.mkdir(parents=True)
    src = out / "src"
    src.mkdir()
    excluded = shutil.ignore_patterns("examples", "tools", ".git", "__pycache__")
    for folder in ("tensorflow", "platform"):
        shutil.copytree(vendor_src / folder, src / folder, ignore=excluded)
    shutil.copytree(bsp, out / "bsp")
    for folder in ("common", "driver"):
        shutil.copytree(vendor / "software/standalone" / folder, out / folder)
    shutil.copy2(runtime / "software/standalone/common/tinyml_lib.a", out / "common/tinyml_lib.a")
    shutil.copy2(ROOT / "firmware/cnn_static/main.cc", src / "main.cc")
    for name in ("cnn_gesture_data.h", "cnn_gesture_data.cc"):
        shutil.copy2(bundle / name, src / name)
    # Freeze the actual copied inputs, including headers and the binary library.
    inputs = {p.relative_to(out).as_posix(): digest(p)
              for folder in (src, out / "bsp", out / "common", out / "driver")
              for p in sorted(folder.rglob("*")) if p.is_file()}
    (out / "input_hashes.json").write_text(json.dumps(inputs, indent=2), encoding="utf-8")
    includes = ["src", "src/platform", "src/platform/interrupt", "src/platform/misc", "src/platform/tinyml",
                "src/tensorflow/third_party/flatbuffers/include", "src/tensorflow/third_party/gemmlowp",
                "src/tensorflow/third_party/ruy", "bsp/include", "bsp/app", "driver"]
    common = ["-march=rv32im_zicsr_zifencei", "-mabi=ilp32", "-O2", "-g", "-DUSE_GP",
              "-DSYSTEM_UART_A_APB=SYSTEM_UART_0_IO_APB", "-DSYSTEM_GPIO_A_APB=SYSTEM_GPIO_0_IO_APB",
              "-DSYSTEM_I2C_A_APB=SYSTEM_I2C_0_IO_APB", "-DTF_LITE_STATIC_MEMORY",
              "-DTF_LITE_USE_GLOBAL_CMATH_FUNCTIONS", "-DTF_LITE_USE_GLOBAL_MIN", "-DTF_LITE_USE_GLOBAL_MAX",
              "-DTF_LITE_DISABLE_X86_NEON", "-ffunction-sections", "-fdata-sections", "-fno-common", "-fno-builtin"]
    common += ["-I" + name for name in includes]
    common += ['-DCNN_MODEL_SHA256="' + manifest["model_sha256"] + '"']
    patterns = ["src/*.cc", "src/model/*.cc", "src/platform/*/*.c", "src/platform/*/*.cc",
                "src/platform/*/*/*.c", "src/platform/*/*/*.cc", "src/tensorflow/lite/c/*.c",
                "src/tensorflow/lite/core/api/*.cc", "src/tensorflow/lite/kernels/*.cc",
                "src/tensorflow/lite/kernels/internal/*.cc", "src/tensorflow/lite/micro/*.cc",
                "src/tensorflow/lite/micro/kernels/*.cc", "src/tensorflow/lite/micro/memory_planner/*.cc",
                "src/tensorflow/lite/schema/*.cc"]
    sources = sorted({p for pattern in patterns for p in out.glob(pattern) if not p.stem.endswith("_test")})
    sources += [out / "common" / name for name in ("start.S", "trap.S")]
    (out / "objects").mkdir()
    commands = []
    for i, path in enumerate(sources):
        is_cpp = path.suffix in (".cc", ".cpp")
        extra = ["-std=c++11", "-fno-rtti", "-fno-exceptions", "-fno-threadsafe-statics"] if is_cpp else []
        commands.append([str(compiler if is_cpp else gcc), *common, *extra, "-c",
                         path.relative_to(out).as_posix(), "-o", f"objects/{i:04d}.o"])
    def compile_one(args):
        run = subprocess.run(args, cwd=out, capture_output=True, text=True, errors="replace")
        return run.returncode, " ".join(args) + "\n" + run.stdout + run.stderr
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(compile_one, commands))
    (out / "compile.log").write_text("\n".join(result[1] for result in results), encoding="utf-8")
    failures = [result for result in results if result[0]]
    if failures:
        print(failures[0][1][-5000:])
        raise RuntimeError(f"{len(failures)} of {len(commands)} translation units failed; see compile.log")
    # A response file avoids Windows command-line size limits.
    link_args = [f"objects/{i:04d}.o" for i in range(len(commands))] + [
        "-march=rv32im_zicsr_zifencei", "-mabi=ilp32", "-specs=nosys.specs", "-nostartfiles",
        "-Wl,-T,bsp/linker/default.ld,-Map,cnn_static.map,--gc-sections,--print-memory-usage",
        "-Wl,--start-group", "common/tinyml_lib.a", "-lc", "-lm", "-lgcc", "-Wl,--end-group", "-o", "cnn_static.elf"]
    (out / "link.rsp").write_text("\n".join(link_args), encoding="ascii")
    linked = subprocess.run([str(compiler), "@link.rsp"], cwd=out, capture_output=True, text=True)
    (out / "link.log").write_text(linked.stdout + linked.stderr, encoding="utf-8")
    if linked.returncode:
        print(linked.stderr[-6000:])
    linked.check_returncode()
    tool = sdk / "toolchain/bin"
    subprocess.run([str(tool / "riscv-none-elf-objcopy.exe"), "-O", "binary", "cnn_static.elf", "cnn_static.bin"], cwd=out, check=True)
    size = subprocess.check_output([str(tool / "riscv-none-elf-size.exe"), "cnn_static.elf"], cwd=out, text=True)
    version = subprocess.check_output([str(compiler), "--version"], text=True).splitlines()[0]
    for flag, name in (("-h", "elf_header.txt"), ("-A", "elf_attributes.txt"), ("-S", "elf_sections.txt")):
        result = subprocess.check_output([str(tool / "riscv-none-elf-readelf.exe"), flag, "cnn_static.elf"], cwd=out, text=True)
        (out / name).write_text(result, encoding="utf-8")
    report = {"compiler": version, "isa": "rv32im_zicsr_zifencei", "abi": "ilp32", "units": len(commands),
              "model_sha256": manifest["model_sha256"], "elf_sha256": digest(out / "cnn_static.elf"),
              "linker_sha256": digest(linker), "bsp": str(bsp), "runtime": str(runtime), "size_output": size,
              "build_script_sha256": digest(Path(__file__)), "source_manifest_sha256": digest(out / "input_hashes.json"),
              "firmware_sha256": digest(src / "main.cc"), "tinyml_library_sha256": digest(out / "common/tinyml_lib.a"),
              "link_warnings": [line for line in linked.stderr.splitlines() if "warning:" in line],
              "arena_ceiling_bytes": 262144, "arena_used_bytes": None, "target_run_verified": False,
              "video_integration_compatible": False,
              "warning": "Vendor static BSP at 0x1000 overlaps video slots; never use in video system as-is"}
    (out / "build_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vendor-workspace", type=Path, required=True)
    parser.add_argument("--runtime-workspace", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/cnn-static")
    args = parser.parse_args()
    build(args.vendor_workspace, args.runtime_workspace, args.sdk, args.bundle, args.output)
