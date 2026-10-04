"""Derive a static accelerator self-test from the copied official YOLO main.cc."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def adapt(project, bundle):
    project, bundle = project.resolve(), bundle.resolve()
    project.relative_to((ROOT / "artifacts").resolve())
    app = project / "embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_ypd"
    original = project / "reference_original/main.cc"
    target = app / "src/main.cc"
    integration = json.loads((project / "integration_manifest.json").read_text())
    if (target.read_bytes() != original.read_bytes() and
        hashlib.sha256(target.read_bytes()).hexdigest() != integration.get("adapted_main_sha256")):
        raise ValueError("Application already changed; do not overwrite edits")
    manifest = json.loads((bundle / "bundle_manifest.json").read_text())
    if manifest["model_sha256"] != integration["model_sha256"]:
        raise ValueError("Golden vectors belong to another model")
    for name, digest in manifest["files"].items():
        path = (bundle / name).resolve()
        path.relative_to(bundle)
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Bundle checksum mismatch: {name}")
    content = original.read_text(encoding="utf-8")
    replacements = {
        '#include "model/yolo_person_detect_model_data.h"':
            '#include "model/gesture_int8_model_data.h"\n#include "cnn_gesture_data.h"',
        'tflite::GetModel(yolo_person_detect_model_data)': 'tflite::GetModel(gesture_int8_model_data)',
        'constexpr int kTensorArenaSize = 10000 * 1024;': 'constexpr int kTensorArenaSize = 256 * 1024;',
        'uint8_t tensor_arena[kTensorArenaSize];': 'alignas(16) uint8_t tensor_arena[kTensorArenaSize];',
    }
    for old, new in replacements.items():
        if content.count(old) != 1:
            raise ValueError(f"Official source changed: {old}")
        content = content.replace(old, new)
    # The YOLO print loop assumes rank 4; class output has rank 2.
    start = content.index('   for (int i = 0; i < total_output_layers; ++i)')
    end = content.index('\n}\n', start)
    content = content[:start] + '   MicroPrintf("Output tensors: %d\\n\\r", total_output_layers);\n' + content[end:]
    start = content.index('int main() {')
    content = content[:start] + (ROOT / "firmware/evsoc_gesture/static_main.inc").read_text(encoding="utf-8")
    for name in ("cnn_gesture_data.h", "cnn_gesture_data.cc"):
        shutil.copy2(bundle / name, app / "src" / name)
    target.write_text(content, encoding="utf-8")
    # The user's demo also contains old generator output defining layer_mode.
    # Keep these reference files, but exclude them from the 2026 runtime build.
    makefile = app / "makefile"
    make = makefile.read_text(encoding="utf-8")
    marker = "# CNN gesture sources (2026 accelerator config is queried from hardware)"
    if marker not in make:
        addition = (marker + "\nSRCS := $(filter-out src/model/define.cc src/model/yolo_person_detect_model_data.cc,$(SRCS))\n"
                    "LDFLAGS += -Wl,--gc-sections\n\n")
        make = make.replace("include ${STANDALONE}/common/bsp.mk", addition + "include ${STANDALONE}/common/bsp.mk")
        makefile.write_text(make, encoding="utf-8")
    (project / "INTEGRATION_REQUIRED.md").write_text(
        "# Static accelerator application prepared; dual video integration is pending\n\n"
        "main.cc now uses the generated gesture model and three golden inputs. It retains the official EVSoC TinyML init/Invoke flow. "
        "No PiCam/DSI initialization is called. Hardware is still the official HyperRAM baseline: DO NOT DOWNLOAD to the DDR3 board. "
        "Complete shared DDR arbitration, AR0135 preprocessing, UART and frame-boundary Overlay integration before board validation.\n",
        encoding="utf-8")
    integration.update(main_adapted=True, application_mode="static_accelerator_golden",
                       adapted_main_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                       golden_bundle_sha256=hashlib.sha256((bundle / "bundle_manifest.json").read_bytes()).hexdigest())
    (project / "integration_manifest.json").write_text(json.dumps(integration, indent=2), encoding="utf-8")
    print(target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--bundle", type=Path, required=True)
    args = parser.parse_args()
    adapt(args.project, args.bundle)
