"""Verify the packaged, already-tested v0.2 export without launching a new game."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    build = root / "build"
    manifest = json.loads((build / "Rimgate-demo-v0.2.0-manifest.json").read_text(encoding="utf-8-sig"))
    export = json.loads((build / "release_v0.2_windows/EXPORT.json").read_text(encoding="utf-8-sig"))
    checks = []

    def check(value, label):
        checks.append({"check": label, "passed": bool(value)})

    archives = {}
    for kind, name in [("windows", "Rimgate-demo-v0.2.0-windows-x64.zip"), ("source", "Rimgate-demo-v0.2.0-source.zip")]:
        path = build / name
        archives[kind] = {"file": name, "bytes": path.stat().st_size, "sha256": sha(path.read_bytes())}
        with zipfile.ZipFile(path) as archive:
            check(archive.testzip() is None, f"{kind}: every member passes CRC")
            members = {item.filename.replace("\\", "/"): item for item in archive.infolist() if not item.is_dir()}
            check(all(not name.startswith("/") and ".." not in name.split("/") for name in members), f"{kind}: relative member paths")
            check(not any(name.startswith((".tools/", ".godot/", ".git/")) for name in members), f"{kind}: no local runtime or repository metadata")

            def read(name):
                return archive.read(members[name])

            if kind == "windows":
                check(json.loads(read("VERSION.json")) == manifest, "Windows VERSION.json equals external manifest")
                for name, key in [("Rimgate.exe", "executable_sha256"), ("Rimgate.pck", "pck_sha256")]:
                    check(sha(read(name)) == manifest[key] == export[key], f"{name}: matches tested export")
                check(manifest["product_source_sha256"] == export["product_source_sha256"], "Product fingerprint retained")
                for name, original in [("AUDIO_LICENSES.txt", "assets/audio/LICENSES.txt"), ("FONT_LICENSE.txt", "assets/fonts/LICENSE.txt"), ("source/Tabasco-original-license.txt", "assets/audio/source/Tabasco-original-license.txt"), ("source/Kenney-original-license.txt", "assets/audio/source/Kenney-original-license.txt"), ("source/MANIFEST.json", "assets/audio/source/MANIFEST.json")]:
                    check(read(name) == (root / original).read_bytes(), f"License/notice unchanged: {name}")
                for name in ["docs/PLAY_V2.md", "docs/V2_TEST_REPORT.md", "docs/V2_BUILD_PROVENANCE.md", "docs/GODOT_LICENSE.txt", "docs/GODOT_THIRD_PARTY_NOTICES.txt", "build/Rimgate-demo-v0.2.0-motion.mp4"]:
                    check(name in members, f"Delivery includes {name}")
                for name in ["v2_final_interaction", "v2_final_benchmark", "v2_final_victory", "v2_final_motion", "v2_final_soak", "v2_final_soak-process", "v2_final_soak-memory-recheck"]:
                    report = json.loads(read(f"build/reports/{name}.json"))
                    check(report.get("failures") == [], f"Final report has no failures: {name}")
                    if "pck_sha256" in report:
                        check(report["pck_sha256"] == manifest["pck_sha256"], f"Report refers to final PCK: {name}")
                soak = json.loads(read("build/reports/v2_final_soak.json"))
                check(soak["elapsed_seconds"] >= 1800 and soak["restarts"] >= 5, "Final soak meets duration/restart gate")
                process = json.loads(read("build/reports/v2_final_soak-process.json"))
                check(process["completed"] and process["game_exit_code"] == 0, "Final soak exited normally")
                for name in ["v2_station_input", "../v2_evidence/visual_v2_report", "../v2_evidence/motion_audio_report"]:
                    member = "build/" + (name[3:] if name.startswith("../") else f"reports/{name}") + ".json"
                    check(json.loads(read(member))["passed"], f"Additional check passed: {name}")
                check(read("build/v2_evidence/motion_14.5.png") == read("build/v2_evidence/motion_15.5.png"), "Recorded pause frames are identical")
            else:
                commit = manifest["source_commit"]
                check(archive.comment.decode("ascii").strip() == commit, "Source archive comment identifies manifest commit")
                expected = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", commit], cwd=root, text=True, encoding="utf-8").splitlines()
                check(set(members) == set(expected), "Source archive contains exactly committed tracked files")
                check(not any(name.startswith("build/") for name in members), "Source contains no generated builds")
                for name in ["project.godot", "scripts/sim/world.gd", "scripts/sim/unit_system.gd", "scripts/sim/combat_system.gd", "docs/V2_TEST_REPORT.md"]:
                    committed = subprocess.check_output(["git", "show", f"{commit}:{name}"], cwd=root)
                    check(read(name) == committed, f"Source member matches commit: {name}")

    result = {"version": "0.2.0", "source_commit": manifest["source_commit"], "export_source_commit": manifest["export_source_commit"], "pck_sha256": manifest["pck_sha256"], "archives": archives, "checks": checks, "passed": all(item["passed"] for item in checks)}
    output = build / "reports/v2_release_package_check.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"V2_RELEASE_PACKAGE_CHECK {sum(item['passed'] for item in checks)}/{len(checks)} passed: {output}")
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
