"""Rename only the isolated derived app, preserving the original vendor demo."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_PARENT = Path("embedded_sw/SapphireSoc/software/standalone")


def rename(project):
    project = project.resolve()
    allowed = (ROOT / "artifacts").resolve()
    project.relative_to(allowed)
    source = (project / APP_PARENT / "evsoc_tinyml_ypd").resolve()
    target = (project / APP_PARENT / "evsoc_tinyml_gesture").resolve()
    # Explicitly validate every directory move stays in this artifact workspace.
    source.relative_to(project)
    target.relative_to(project)
    if target.exists():
        raise FileExistsError(target)
    archive = (project / "legacy_ypd_build").resolve()
    archive.relative_to(project)
    if (source / "build").exists() and archive.exists():
        raise FileExistsError(archive)
    source.rename(target)
    for name in ("makefile", ".project", ".cproject"):
        p = target / name
        p.write_bytes(p.read_bytes().replace(b"evsoc_tinyml_ypd", b"evsoc_tinyml_gesture"))
    if (target / "build").exists():
        (target / "build").rename(archive)
    manifest = project / "integration_manifest.json"
    if manifest.exists():
        data = json.loads(manifest.read_text())
        data["application_workspace"] = str(target)
        data["application_name"] = "evsoc_tinyml_gesture"
        manifest.write_text(json.dumps(data, indent=2), encoding="utf-8")
    report = project / "official_build_report.json"
    history = project / "official_build_ypd_report.json"
    if report.exists() and not history.exists():
        report.rename(history)
    return target


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    print(rename(parser.parse_args().project))
