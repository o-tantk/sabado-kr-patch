"""Build, install and remove the Sabado Korean patch with a recoverable file journal."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from survey import DEFAULT_GAME, ROOT, sha256, source_id

MANIFEST = "SabadoKorean.install.json"
OWNER = "local.sabado.korean"
TOKEN = re.compile(r"</?[A-Za-z][^<>]*>|\{[^{}]+\}|%(?:\d+\$)?[sdif]|\[[^\[\]]+\]")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def child(root, relative):
    relative = Path(relative)
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError("Unsafe relative path: " + str(relative))
    result = (root / relative).resolve()
    if root.resolve() not in result.parents:
        raise ValueError("Path escapes target directory: " + str(relative))
    return result


def ensure_stopped(game):
    if os.name != "nt":
        return
    result = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Sabado Day One.exe", "/FO", "CSV", "/NH"],
                            capture_output=True, text=True, errors="replace", check=True)
    if '"Sabado Day One.exe"' in result.stdout:
        raise RuntimeError("Close Sabado before installing or removing the patch.")


def verify_target(game, target):
    for relative, expected in target["files"].items():
        path = child(game, relative)
        if not path.is_file() or sha256(path) != expected:
            raise ValueError("Unsupported/modified game file: " + relative)


def atomic_copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".sabado-kr-", dir=destination.parent)
    os.close(fd)
    temporary = Path(temp_name)
    try:
        shutil.copyfile(source, temporary)
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def validate_translations(catalog, translations):
    known = {row["id"]: row for row in catalog}
    for identity, value in translations.items():
        if identity not in known:
            raise ValueError("Unknown translation ID: " + identity)
        if not isinstance(value, str) or not value.strip() or "\t" in value or "\r" in value or "\\" in value:
            raise ValueError("Empty or unsupported translation escaping: " + identity)
        original = known[identity]["en"] or known[identity]["fil"]
        if Counter(TOKEN.findall(original)) != Counter(TOKEN.findall(value)):
            raise ValueError("Placeholder, markup or control-key mismatch: " + identity)
    return known


def make_tables(catalog, translations, extra_ui):
    known = validate_translations(catalog, translations)
    keyed, ui = dict(translations), {}
    conflicts = set()
    for identity, korean in translations.items():
        row = known[identity]
        # The game's parser removes every ASCII quote, unlike the standard CSV parser.
        alias = source_id(row["key"].replace('"', ""))
        if alias in keyed and keyed[alias] != korean:
            raise ValueError("Native CSV key alias conflict")
        keyed[alias] = korean
        for original in (row["en"], row["en"].replace('"', "")):
            if not original:
                continue
            digest = source_id(original)
            if digest in ui and ui[digest] != korean:
                conflicts.add(digest)
            ui[digest] = korean
    # Keyed dialogue keeps its context. Ambiguous plain English UI matches are skipped.
    for digest in conflicts:
        ui.pop(digest, None)
    for original, korean in extra_ui.items():
        if Counter(TOKEN.findall(original)) != Counter(TOKEN.findall(korean)):
            raise ValueError("UI token mismatch: " + original)
        ui[source_id(original)] = korean
    return keyed, ui, len(conflicts)


def package():
    catalog = read_json(ROOT / "local/survey/catalog.json")
    translations = read_json(ROOT / "translations/ko.json")
    extra = read_json(ROOT / "translations/ui.json")
    keyed, ui, conflicts = make_tables(catalog, translations, extra)
    folder = ROOT / "dist/SabadoKorean"
    loader = ROOT / "vendor/BepInEx"
    for name in ("winhttp.dll", "doorstop_config.ini", ".doorstop_version"):
        atomic_copy(loader / name, folder / name)
    for file in (loader / "BepInEx/core").rglob("*"):
        if file.is_file():
            atomic_copy(file, folder / file.relative_to(loader))
    plugin = folder / "BepInEx/plugins/SabadoKorean"
    atomic_copy(ROOT / "build/SabadoKorean.dll", plugin / "SabadoKorean.dll")
    for name, table in (("strings.tsv", keyed), ("ui.tsv", ui)):
        content = "\n".join(k + "\t" + v.replace("\n", "\\n") for k, v in sorted(table.items())) + "\n"
        (plugin / name).write_text(content, encoding="utf-8")
    result = {"translated_keys": len(translations), "runtime_key_aliases": len(keyed),
              "ui_matches": len(ui), "ambiguous_ui_matches_skipped": conflicts,
              "english_keys": sum(bool(row["en"]) for row in catalog)}
    write_json(ROOT / "local/package-report.json", result)
    print(json.dumps(result, indent=2))
    return folder


def install(game, package_dir, backups, target):
    game, package_dir, backups = game.resolve(), package_dir.resolve(), backups.resolve()
    if game == backups or game in backups.parents:
        raise ValueError("Backups must be outside the game installation")
    ensure_stopped(game)
    verify_target(game, target)
    manifest_path = game / MANIFEST
    previous = read_json(manifest_path) if manifest_path.exists() else None
    if previous and (previous.get("owner") != OWNER or previous.get("game") != str(game)):
        raise ValueError("Unrecognized installation manifest")
    previous_files = previous["files"] if previous else {}
    existing_loader = (game / "winhttp.dll").exists() or any((game / "BepInEx/core").glob("*.dll")) or any((game / "BepInEx/plugins").rglob("*.dll"))
    if not previous and existing_loader:
        raise ValueError("An existing mod loader was found. Automatic takeover is not supported.")
    sources = {p.relative_to(package_dir).as_posix(): p for p in package_dir.rglob("*") if p.is_file()}
    if "BepInEx/plugins/SabadoKorean/SabadoKorean.dll" not in sources:
        raise ValueError("Package does not contain the patch plugin")
    allowed_root = {"winhttp.dll", "doorstop_config.ini", ".doorstop_version"}
    allowed_plugin = {"SabadoKorean.dll", "strings.tsv", "ui.tsv"}
    for relative in sources:
        is_core = relative.startswith("BepInEx/core/") and Path(relative).suffix in {".dll", ".xml"}
        is_plugin = relative.startswith("BepInEx/plugins/SabadoKorean/") and Path(relative).name in allowed_plugin
        if relative not in allowed_root and not is_core and not is_plugin:
            raise ValueError("Unexpected package file; refusing installation: " + relative)
    for relative, record in previous_files.items():
        destination = child(game, relative)
        if not destination.is_file() or sha256(destination) != record["installed_sha256"]:
            raise ValueError("An installed patch file was changed; preserve it before updating: " + relative)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup = backups / stamp
    backup.mkdir(parents=True)
    immediate, final = {}, dict(previous_files)
    # Finish every backup and write a recovery journal BEFORE changing any target file.
    for relative, source in sources.items():
        destination = child(game, relative)
        present = destination.exists()
        saved = child(backup / "files", relative)
        if present:
            atomic_copy(destination, saved)
        immediate[relative] = {"exists": present, "sha256": sha256(destination) if present else None}
        initial = previous_files.get(relative, {}).get("original")
        if initial is None:
            initial = {"exists": present, "backup": str(saved) if present else None,
                       "sha256": immediate[relative]["sha256"]}
        final[relative] = {"original": initial, "installed_sha256": sha256(source)}
    if previous:
        atomic_copy(manifest_path, backup / "previous-manifest.json")
    journal = {"owner": OWNER, "game": str(game), "status": "prepared", "before": immediate}
    write_json(backup / "recovery.json", journal)
    touched = []
    try:
        for relative, source in sources.items():
            touched.append(relative)
            atomic_copy(source, child(game, relative))
        new_manifest = {"owner": OWNER, "game": str(game), "target_build": target["steam_build_id"],
                        "last_backup": str(backup), "files": final}
        write_json(backup / "new-manifest.json", new_manifest)
        atomic_copy(backup / "new-manifest.json", manifest_path)
        journal["status"] = "installed"
    except Exception:
        for relative in reversed(touched):
            destination = child(game, relative)
            if immediate[relative]["exists"]:
                atomic_copy(child(backup / "files", relative), destination)
            elif destination.exists():
                destination.unlink()
        journal["status"] = "rolled_back"
        raise
    finally:
        write_json(backup / "recovery.json", journal)
    print("Installed. Backup/recovery journal: " + str(backup))


def remove(game):
    game = game.resolve()
    ensure_stopped(game)
    manifest_path = game / MANIFEST
    manifest = read_json(manifest_path)
    if manifest.get("owner") != OWNER or manifest.get("game") != str(game):
        raise ValueError("Unrecognized installation manifest")
    # Preflight the complete removal; never delete a modified or unrelated file.
    for relative, record in manifest["files"].items():
        destination = child(game, relative)
        if destination.exists() and sha256(destination) != record["installed_sha256"]:
            raise ValueError("Patch file modified; refusing removal: " + relative)
        original = record["original"]
        if original["exists"]:
            saved = Path(original["backup"])
            if not saved.is_file() or sha256(saved) != original["sha256"]:
                raise ValueError("Original backup missing or modified: " + relative)
    for relative, record in manifest["files"].items():
        destination = child(game, relative)
        if record["original"]["exists"]:
            atomic_copy(Path(record["original"]["backup"]), destination)
        elif destination.exists():
            destination.unlink()
    manifest_path.unlink()
    print("Patch removed. Generated BepInEx logs/cache/config are retained; loader is removed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["package", "install", "remove", "status"])
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME)
    args = parser.parse_args()
    target = read_json(ROOT / "config/target.json")
    if args.action == "package":
        package()
    elif args.action == "install":
        install(args.game, ROOT / "dist/SabadoKorean", ROOT / "local/backups", target)
    elif args.action == "remove":
        remove(args.game)
    else:
        verify_target(args.game.resolve(), target)
        print("Original game fingerprints match target build " + target["steam_build_id"])
        print("Patch installed: " + str((args.game / MANIFEST).exists()))


if __name__ == "__main__":
    main()
