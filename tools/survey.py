"""Read a Sabado install without modifying it; keep original resources in local/."""
import argparse
import csv
import hashlib
import io
import json
import re
from pathlib import Path

import UnityPy

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Sabado")


def sha256(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def source_id(key):
    return hashlib.sha256(key.strip().encode("utf-8")).hexdigest()


def inspect(game, output):
    game, output = game.resolve(), output.resolve()
    if output == game or game in output.parents:
        raise ValueError("Analysis output must be outside the game installation")
    data = game / "Sabado Day One_Data"
    output.mkdir(parents=True, exist_ok=True)
    with (data / "globalgamemanagers").open("rb") as handle:
        version = re.search(rb"6000\.\d+\.\d+f\d+", handle.read(256)).group().decode()
    assets = UnityPy.load(str(data / "resources.assets"))
    text = next(o.parse_as_object().m_Script for o in assets.objects
                if o.type.name == "TextAsset" and o.parse_as_object().m_Name == "localization")
    (output / "localization.csv").write_text(text, encoding="utf-8")
    reader = csv.DictReader(io.StringIO(text))
    rows = list(reader)
    unique = {r["key"].strip(): r for r in rows if r["key"].strip()}
    catalog = [{"id": source_id(k), "key": k, "en": r["English"].strip(),
                "fil": r["Filipino"].strip()} for k, r in unique.items()]
    (output / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    files = {str(p.relative_to(game)).replace("\\", "/"): {"bytes": p.stat().st_size, "sha256": sha256(p)}
             for p in sorted(game.rglob("*")) if p.is_file()}
    (output / "inventory.json").write_text(json.dumps(files, indent=2), encoding="utf-8")
    manifest = game.parent.parent / "appmanifest_4986750.acf"
    build = re.search(r'"buildid"\s+"(\d+)"', manifest.read_text())[1] if manifest.exists() else None
    report = {"steam_app_id": 4986750, "steam_build_id": build, "unity_version": version,
              "backend": "Mono", "architecture": "x64", "csv_rows": len(rows),
              "unique_keys": len(unique), "nonempty_english_keys": sum(bool(r["en"]) for r in catalog),
              "languages": reader.fieldnames[1:], "original_file_count": len(files)}
    (output / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME)
    parser.add_argument("--output", type=Path, default=ROOT / "local" / "survey")
    args = parser.parse_args()
    inspect(args.game, args.output)
