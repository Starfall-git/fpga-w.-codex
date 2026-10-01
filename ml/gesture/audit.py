"""v1.0 / 4: Read-only local resource and model audit; JSON goes to stdout.

Paths are anchored to this CNN copy. Historical reports are explicitly labelled;
their presence is not proof that the current source has been synthesized.
"""
import hashlib
import json
from pathlib import Path
import re

from model import budget

ROOT = Path(__file__).resolve().parents[2]


def resource_report(relative):
    path = ROOT / relative
    raw = path.read_bytes()
    content = raw.decode("utf-8", errors="replace")
    resources = {}
    for label in ("XLRs", "Memory Blocks", "DSP Blocks"):
        match = re.search(r"^" + re.escape(label) + r": (\d+) / (\d+)",
                          content, re.MULTILINE)
        if not match:
            raise ValueError(f"Resource field missing: {relative}: {label}")
        used, total = map(int, match.groups())
        resources[label] = dict(used=used, total=total, remaining=total-used)
    return dict(path=relative, sha256=hashlib.sha256(raw).hexdigest(),
                provenance="inherited historical report, not rebuilt in CNN workspace",
                resources=resources)


def audit():
    examples = ROOT / "tinyml-main/tinyml_hello_world/Ti60F225_tinyml_helloworld"
    inherited = resource_report("outflow/Ti60_AR0135.place.rpt")
    sample = resource_report((examples / "outflow/Ti60F225_tinyml_helloworld.place.rpt")
                             .relative_to(ROOT).as_posix())
    return dict(version="v1.0", root=str(ROOT), existing_video=inherited,
                standalone_example=sample,
                candidates=[budget(s, 4, d) for s, d in
                            ((64, True), (96, True), (64, False))],
                notes=["Do not add whole standalone and video designs as an integration estimate.",
                       "No accuracy, FPS, arena usage or post-route resources measured.",
                       "Four classes are a provisional planning assumption."])


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2, ensure_ascii=True))
