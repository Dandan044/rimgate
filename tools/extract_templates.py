"""Extract only the Windows x64 templates from the official Godot TPZ."""
from pathlib import Path
from zipfile import ZipFile
import shutil

root = Path(__file__).resolve().parents[1]
target = root / ".tools" / "templates"
target.mkdir(parents=True, exist_ok=True)
with ZipFile(root / ".tools" / "export_templates.tpz") as archive:
    for filename in ("windows_debug_x86_64.exe", "windows_release_x86_64.exe"):
        matches = [name for name in archive.namelist() if name.endswith("/" + filename)]
        if len(matches) != 1:
            raise RuntimeError(f"Expected one template for {filename}: {matches}")
        with archive.open(matches[0]) as source, (target / filename).open("wb") as output:
            shutil.copyfileobj(source, output)
        print(f"Extracted {filename}: {(target / filename).stat().st_size} bytes")
