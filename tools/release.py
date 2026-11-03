"""Assemble the offline Windows release; Python is used only by the maintainer."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

import patch

ROOT = Path(__file__).resolve().parents[1]
DOORSTOP_SOURCE_SHA256 = "ba5bc290e6145e0b33e1b3cfd4de18698144f6dbe031a2278996cfc73036a3e6"


def main():
    version = re.search(r'BepInPlugin\([^\n]+"(\d+\.\d+\.\d+)"\)',
                        (ROOT / "src/KoreanPatch.cs").read_text(encoding="utf-8")).group(1)
    source_archive = ROOT / "vendor/UnityDoorstop-4.6.0-source.tar.gz"
    if not source_archive.exists() or patch.sha256(source_archive) != DOORSTOP_SOURCE_SHA256:
        raise ValueError("Run tools/fetch-release-deps.ps1 to obtain the verified third-party source archive")
    package = patch.package()
    staging = Path(tempfile.mkdtemp(prefix="release-", dir=ROOT / "build"))
    folder = staging / f"SabadoKorean-v{version}"
    payload = folder / "payload"
    # Use an explicit inventory rather than copying leftover files from dist/.
    loader = ROOT / "vendor/BepInEx"
    files = [".doorstop_version", "doorstop_config.ini", "winhttp.dll"]
    files += [p.relative_to(loader).as_posix() for p in (loader / "BepInEx/core").iterdir()
              if p.is_file() and p.suffix in {".dll", ".xml"}]
    prefix = "BepInEx/plugins/SabadoKorean/"
    files += [prefix + p for p in ("SabadoKorean.dll", "strings.tsv", "ui.tsv", "textures.tsv")]
    files += [prefix + "textures/" + entry["file"]
              for entry in patch.read_json(ROOT / "translations/textures.json")]
    hashes = {}
    for relative in sorted(files):
        patch.atomic_copy(package / relative, payload / relative)
        hashes[relative] = patch.sha256(payload / relative)
    patch.write_json(folder / "package.json", {"schema": 1, "version": version,
                     "target": patch.read_json(ROOT / "config/target.json"), "files": hashes})
    for source, name in (("Install.bat", "설치.bat"), ("Remove.bat", "제거.bat"), ("Recover.bat", "복구.bat")):
        content = (ROOT / "installer" / source).read_text(encoding="ascii")
        (folder / name).write_bytes(content.replace("\r\n", "\n").replace("\n", "\r\n").encode("ascii"))
    (folder / "installer").mkdir()
    for name in ("engine.ps1", "setup.ps1"):
        content = (ROOT / "installer" / name).read_text(encoding="utf-8-sig")
        (folder / "installer" / name).write_text(content, encoding="utf-8-sig")
    shutil.copyfile(ROOT / "README.md", folder / "사용설명서.txt")
    shutil.copyfile(ROOT / "THIRD-PARTY-NOTICES.md", folder / "THIRD-PARTY-NOTICES.md")
    shutil.copytree(ROOT / "licenses", folder / "licenses")
    (folder / "third-party-sources").mkdir()
    shutil.copyfile(source_archive, folder / "third-party-sources" / source_archive.name)
    output = ROOT / f"dist/SabadoKorean-v{version}-windows-x64.zip"
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(staging).as_posix(), (2026, 11, 4, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                archive.writestr(info, path.read_bytes())
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    (ROOT / "dist/SHA256SUMS.txt").write_text(checksum + "  " + output.name + "\n", encoding="ascii")
    patch.write_json(ROOT / "local/release-build.json", {"version": version, "staging": str(folder),
                     "archive": str(output), "sha256": checksum, "payload_files": len(hashes)})
    print(json.dumps({"archive": str(output), "staging": str(folder), "sha256": checksum}, indent=2))


if __name__ == "__main__":
    main()
