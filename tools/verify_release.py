"""Verify a packaged Rimgate release against its export, commit and raw evidence.

This verifier never runs the game, edits reports, repairs archives or assumes a
missing gate passed. It writes its own independent package-check report.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def json_bytes(data):
    return json.loads(data.decode("utf-8-sig"))


def safe_member(name):
    name = name.replace("\\", "/").rstrip("/")
    return bool(name) and not name.startswith("/") and ":" not in name and all(
        part not in ("", ".", "..", ".git", ".godot", ".tools", "__pycache__") for part in name.split("/")
    )


def mp4_metadata(data):
    """Read container metadata without an external decoder or rewriting media."""
    tracks = set()
    duration = None
    top_boxes = set()
    payload_bytes = 0

    def scan(start, end, level=0):
        nonlocal duration, payload_bytes
        offset = start
        while offset < end:
            if end - offset < 8:
                raise ValueError("truncated MP4 atom")
            size, kind = struct.unpack_from(">I4s", data, offset)
            header = 8
            if size == 1:
                if end - offset < 16:
                    raise ValueError("truncated MP4 large atom")
                size = struct.unpack_from(">Q", data, offset + 8)[0]
                header = 16
            elif size == 0:
                size = end - offset
            if size < header or offset + size > end:
                raise ValueError("invalid MP4 atom bounds")
            begin = offset + header
            stop = offset + size
            if level == 0:
                top_boxes.add(kind)
            if kind == b"mdat":
                payload_bytes += stop - begin
            elif kind in (b"moov", b"trak", b"mdia"):
                scan(begin, stop, level + 1)
            elif kind == b"hdlr" and stop - begin >= 12:
                tracks.add(data[begin + 8:begin + 12].decode("ascii", errors="replace"))
            elif kind == b"mvhd":
                version = data[begin]
                if version == 0 and stop - begin >= 20:
                    timescale, ticks = struct.unpack_from(">II", data, begin + 12)
                elif version == 1 and stop - begin >= 32:
                    timescale = struct.unpack_from(">I", data, begin + 20)[0]
                    ticks = struct.unpack_from(">Q", data, begin + 24)[0]
                else:
                    raise ValueError("invalid MP4 movie header")
                if timescale <= 0:
                    raise ValueError("invalid MP4 timescale")
                duration = ticks / timescale
            offset = stop

    scan(0, len(data))
    return {"boxes": sorted(box.decode("ascii", errors="replace") for box in top_boxes),
            "tracks": sorted(tracks), "duration_seconds": duration, "payload_bytes": payload_bytes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--version", default="0.3.0")
    parser.add_argument("--export-dir", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--windows-zip", type=Path)
    parser.add_argument("--source-zip", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--report-prefix", help="ZIP-relative prefix, e.g. build/reports/v3_final")
    parser.add_argument("--media", help="ZIP-relative motion MP4")
    parser.add_argument("--pause-frames", nargs=2, help="Two ZIP-relative PNG files inside the recorded pause")
    parser.add_argument("--audio-report", help="ZIP-relative actual motion audio-analysis JSON")
    parser.add_argument("--extra-report", action="append", default=[], help="Additional ZIP-relative JSON evidence that must pass")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", args.version):
        parser.error("--version must be a release version such as 0.3.0")
    root = args.root.resolve()
    build = root / "build"
    series = args.version.split(".")[1]
    short_version = ".".join(args.version.split(".")[:2])
    checks = []
    archives = {}

    def check(value, label, detail=None):
        item = {"check": label, "passed": bool(value)}
        if detail is not None:
            item["detail"] = str(detail)
        checks.append(item)

    def path(value, default):
        value = value if value is not None else Path(default)
        return value if value.is_absolute() else root / value

    def read_json_file(file, label):
        try:
            result = json_bytes(file.read_bytes())
            if not isinstance(result, dict):
                raise ValueError("expected a JSON object")
            check(True, label)
            return result
        except (OSError, ValueError) as error:
            check(False, label, error)
            return {}

    manifest_path = path(args.manifest, f"build/Rimgate-demo-v{args.version}-manifest.json")
    export_dir = path(args.export_dir, f"build/release_v{short_version}_windows")
    manifest = read_json_file(manifest_path, "External version manifest is readable")
    export = read_json_file(export_dir / "EXPORT.json", "EXPORT.json is readable")
    check(manifest.get("version") == args.version == export.get("version"), "Manifest and export identify requested version")
    for key in ["source_commit", "export_source_commit"]:
        check(bool(re.fullmatch(r"[0-9a-fA-F]{40,64}", str(manifest.get(key, "")))), f"Manifest contains a full {key}")
    for key in ["product_source_sha256", "executable_sha256", "pck_sha256"]:
        value = str(manifest.get(key, "")).upper()
        check(bool(re.fullmatch(r"[0-9A-F]{64}", value)) and value == str(export.get(key, "")).upper(), f"Manifest {key} equals tested export")
    check(manifest.get("export_source_commit") == export.get("export_source_commit") and bool(manifest.get("export_source_commit")), "Export source revision retained")
    for name, key in [("Rimgate.exe", "executable_sha256"), ("Rimgate.pck", "pck_sha256")]:
        try:
            check(sha((export_dir / name).read_bytes()) == str(export.get(key, "")).upper(), f"Local tested export {name} retains recorded hash")
        except OSError as error:
            check(False, f"Local tested export {name} exists", error)

    committed_files = {}
    expected_data = None
    commit = str(manifest.get("source_commit", ""))
    try:
        expected_data = subprocess.check_output(["git", "-c", "core.autocrlf=false", "archive", "--format=zip", commit], cwd=root, stderr=subprocess.PIPE)
        with zipfile.ZipFile(io.BytesIO(expected_data)) as expected:
            committed_files = {info.filename: expected.read(info) for info in expected.infolist() if not info.is_dir()}
        tracked = subprocess.check_output(["git", "ls-tree", "-rz", "--name-only", commit], cwd=root, stderr=subprocess.PIPE).decode("utf-8").rstrip("\0").split("\0")
        check(set(committed_files) == set(tracked), "git archive includes exactly the manifest commit's tracked files")
        product_diff = subprocess.check_output(["git", "diff", "--name-only", str(manifest["export_source_commit"]), commit, "--", "project.godot", "main.tscn", "export_presets.cfg", "scripts", "assets"], cwd=root, stderr=subprocess.PIPE)
        check(not product_diff.strip(), "Final source commit retains all product bytes from the tested export commit", product_diff.decode("utf-8", errors="replace").strip() or None)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        check(False, "Manifest commit can be independently reconstructed using git archive", error)

    windows_path = path(args.windows_zip, f"build/Rimgate-demo-v{args.version}-windows-x64.zip")
    source_path = path(args.source_zip, f"build/Rimgate-demo-v{args.version}-source.zip")
    prefix = args.report_prefix or f"build/reports/v{series}_final"
    media_name = args.media or f"build/Rimgate-demo-v{args.version}-motion.mp4"
    pause_names = args.pause_frames or [f"build/v{series}_evidence/motion_14.5.png", f"build/v{series}_evidence/motion_15.5.png"]
    audio_name = args.audio_report or f"build/v{series}_evidence/motion_audio_report.json"
    test_report = str(manifest.get("test_report", f"docs/V{series}_TEST_REPORT.md")).replace("\\", "/")
    for kind, archive_path in [("windows", windows_path), ("source", source_path)]:
        try:
            raw = archive_path.read_bytes()
            archives[kind] = {"file": archive_path.name, "bytes": len(raw), "sha256": sha(raw)}
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                check(archive.testzip() is None, f"{kind}: every ZIP member passes CRC")
                all_names = [info.filename.replace("\\", "/").rstrip("/") for info in archive.infolist()]
                check(all(safe_member(name) for name in all_names), f"{kind}: all ZIP paths are safe and exclude local metadata")
                check(len(all_names) == len(set(all_names)), f"{kind}: no duplicate or separator-aliased members")
                members = {info.filename.replace("\\", "/"): info for info in archive.infolist() if not info.is_dir()}

                def read(name):
                    if name not in members:
                        check(False, f"{kind}: required member exists: {name}")
                        return None
                    return archive.read(members[name])

                def read_json(name):
                    data = read(name)
                    if data is None:
                        return {}
                    try:
                        value = json_bytes(data)
                        if not isinstance(value, dict):
                            raise ValueError("expected JSON object")
                        return value
                    except ValueError as error:
                        check(False, f"{kind}: JSON member parses: {name}", error)
                        return {}

                if kind == "source":
                    check(expected_data is not None and raw == expected_data, "Source ZIP exactly reproduces git archive output for the manifest commit")
                    check(archive.comment.decode("ascii", errors="replace").strip() == commit and bool(commit), "Source archive comment identifies manifest source commit")
                    check(bool(committed_files) and set(members) == set(committed_files), "Source ZIP contains exactly the committed git archive file set")
                    mismatches = [name for name in committed_files if name not in members or archive.read(members[name]) != committed_files[name]]
                    check(bool(committed_files) and not mismatches, "Every source ZIP file is byte-for-byte identical to git archive", ", ".join(mismatches[:20]) or None)
                    check(not any(name.startswith("build/") for name in members), "Source ZIP excludes generated build artifacts")
                    for name in ["project.godot", "scripts/sim/world.gd", "scripts/sim/unit_system.gd", "scripts/sim/combat_system.gd", "scripts/ui/battle_screen.gd", test_report]:
                        data = read(name)
                        check(data is not None and name in committed_files and data == committed_files[name], f"Key source member matches manifest commit: {name}")
                    continue

                check(read_json("VERSION.json") == manifest and bool(manifest), "Windows VERSION.json equals external manifest exactly")
                for name, key in [("Rimgate.exe", "executable_sha256"), ("Rimgate.pck", "pck_sha256")]:
                    data = read(name)
                    check(data is not None and sha(data) == str(manifest.get(key, "")).upper() == str(export.get(key, "")).upper(), f"Packaged {name} matches the tested export")
                notices = {"AUDIO_LICENSES.txt":"assets/audio/LICENSES.txt", "FONT_LICENSE.txt":"assets/fonts/LICENSE.txt", "source/Tabasco-original-license.txt":"assets/audio/source/Tabasco-original-license.txt", "source/Kenney-original-license.txt":"assets/audio/source/Kenney-original-license.txt", "source/MANIFEST.json":"assets/audio/source/MANIFEST.json", "docs/GODOT_LICENSE.txt":"docs/GODOT_LICENSE.txt", "docs/GODOT_THIRD_PARTY_NOTICES.txt":"docs/GODOT_THIRD_PARTY_NOTICES.txt"}
                for name, original in notices.items():
                    data = read(name)
                    check(data is not None and original in committed_files and data == committed_files[original], f"Packaged license/notice matches source commit: {name}")
                for name in [f"docs/PLAY_V{series}.md", test_report, f"docs/V{series}_BUILD_PROVENANCE.md", "README.md", f"DEMO_V{series}_PLAN.md"]:
                    data = read(name)
                    check(data is not None and len(data) > 0 and name in committed_files and data == committed_files[name], f"Packaged release document matches source commit: {name}")

                reports = {}
                for label in ["input", "benchmark", "victory", "motion", "soak", "soak-process", "soak-memory-recheck"]:
                    name = f"{prefix}_{label}.json"
                    result = read_json(name); reports[label] = result
                    has_verdict = result.get("failures") == [] or result.get("passed") is True
                    no_failures = ("failures" not in result or result["failures"] == []) and result.get("passed", True) is not False
                    check(bool(result) and has_verdict and no_failures, f"Final {label} report explicitly passes with no failures")
                    check(str(result.get("pck_sha256", "")).upper() == str(manifest.get("pck_sha256", "")).upper() and bool(result.get("pck_sha256")), f"Final {label} report identifies the packaged PCK")
                    if isinstance(result.get("checks"), list) and any(isinstance(item, dict) for item in result["checks"]):
                        check(all(isinstance(item, dict) and item.get("passed") is True for item in result["checks"]), f"Every enumerated {label} check passes")
                input_result = reports["input"]
                check(bool(input_result.get("checks")), "Final input evidence contains actual enumerated checks")
                benchmark = reports["benchmark"]
                check(benchmark.get("mode") == "benchmark" and float(benchmark.get("elapsed_seconds", 0)) >= 65 and int(benchmark.get("frames", 0)) > 0 and not benchmark.get("offline_movie_capture", False), "Benchmark is a real-time sample of at least 65 seconds")
                check(float(benchmark.get("average_fps", 0)) >= 60 and 0 < float(benchmark.get("p95_ms", 0)) <= 33.3, "Benchmark meets average 60 FPS and P95 33.3 ms gates")
                check(all(benchmark.get(key) for key in ["cpu", "gpu", "os", "logical_resolution", "window_resolution", "render_resolution"]) and int(benchmark.get("peak_projectiles", 0)) > 0, "Benchmark identifies hardware, resolutions and projectile load")
                victory = reports["victory"]
                scenario = victory.get("scenario", {}); actual = scenario.get("actual", {}); expected = scenario.get("expected", {})
                check(victory.get("mode") == "victory" and float(victory.get("elapsed_seconds", 0)) >= 480 and scenario.get("completed") is True and actual.get("phase") == "won" and int(actual.get("step", 0)) == 28800 and abs(float(actual.get("time", 0)) - 480) <= 0.00001, "Final real-time victory completes all 28,800 steps and 480 seconds")
                check("snapshot_hash" in actual and "state_hash" in expected and actual["snapshot_hash"] == expected["state_hash"] and int(actual.get("commands", 0)) > 0, "Final victory agrees with the version's public-command replay fingerprint")
                motion = reports["motion"]
                check(motion.get("mode") == "motion" and float(motion.get("recorded_seconds", 0)) >= 20, "Motion report records at least 20 seconds of actual rendered actions")
                soak = reports["soak"]; process = reports["soak-process"]; memory = reports["soak-memory-recheck"]
                check(float(soak.get("elapsed_seconds", 0)) >= 1800 and int(soak.get("restarts", 0)) >= 5, "Soak runtime meets 30-minute and restart gates")
                check(process.get("completed") is True and process.get("game_exit_code") == 0 and float(process.get("elapsed_seconds", 0)) >= 1800, "Soak monitor records a completed normal process exit")
                samples = process.get("samples", [])
                valid_samples = len(samples) >= 15 and all(float(item.get("private_bytes", 0)) > 0 for item in samples)
                check(valid_samples, "Soak has at least 15 actual nonzero process-memory samples")
                if valid_samples:
                    early = sum(float(item["private_bytes"]) for item in samples[4:9]) / 5
                    late = sum(float(item["private_bytes"]) for item in samples[-5:]) / 5
                    allowance = max(64 * 1024 * 1024, early * .25)
                    check(late - early <= allowance, "Independently recomputed memory growth meets allowance")
                    check(int(memory.get("sample_count", 0)) == len(samples) and abs(float(memory.get("private_bytes_early_mean", 0)) - early) <= 1 and abs(float(memory.get("private_bytes_late_mean", 0)) - late) <= 1, "Memory recheck matches unchanged raw monitor samples")
                raw_process = read(f"{prefix}_soak-process.json")
                check(raw_process is not None and str(memory.get("input_report_sha256", "")).upper() == sha(raw_process), "Memory recheck binds the actual raw process report")

                media = read(media_name)
                if media is not None:
                    try:
                        metadata = mp4_metadata(media)
                        check({"ftyp", "moov", "mdat"} <= set(metadata["boxes"]) and {"vide", "soun"} <= set(metadata["tracks"]) and metadata["payload_bytes"] > 1000 and (metadata["duration_seconds"] or 0) >= 20, "Motion MP4 contains valid video/audio tracks and at least 20 seconds")
                        check(abs((metadata["duration_seconds"] or 0) - float(motion.get("recorded_seconds", 0))) <= .3, "Motion MP4 duration matches the actual capture report")
                    except (ValueError, struct.error, IndexError) as error:
                        check(False, "Motion MP4 metadata is valid", error)
                pause_data = [read(name) for name in pause_names]
                valid_pngs = all(data is not None and data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) > 33 and data[12:16] == b"IHDR" and all(value > 0 for value in struct.unpack(">II", data[16:24])) for data in pause_data)
                check(valid_pngs and pause_data[0] == pause_data[1], "Two valid recorded pause PNG frames are byte-identical")
                audio = read_json(audio_name)
                check(audio.get("passed") is True and int(audio.get("channels", 0)) == 2 and float(audio.get("seconds", 0)) >= 20 and float(audio.get("peak", 0)) > 0 and int(audio.get("clipped_samples", -1)) == 0 and float(audio.get("stereo_difference_rms", 0)) > 0, "Recorded audio analysis proves non-silent stereo without clipping")
                for name in args.extra_report:
                    extra = read_json(name)
                    check(bool(extra) and extra.get("passed") is True and ("failures" not in extra or extra["failures"] == []), f"Additional evidence passes: {name}")
        except (OSError, ValueError, zipfile.BadZipFile, RuntimeError, KeyError, TypeError) as error:
            check(False, f"{kind}: archive can be completely verified", error)

    result = {"version": args.version, "source_commit": manifest.get("source_commit"), "export_source_commit": manifest.get("export_source_commit"), "pck_sha256": manifest.get("pck_sha256"), "archives": archives, "checks": checks, "passed": bool(checks) and all(item["passed"] for item in checks)}
    output = path(args.output, f"build/reports/v{series}_release_package_check.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"RELEASE_PACKAGE_CHECK {sum(item['passed'] for item in checks)}/{len(checks)} passed: {output}")
    for item in checks:
        if not item["passed"]:
            print("FAIL: " + item["check"] + (": " + item["detail"] if "detail" in item else ""))
    raise SystemExit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
