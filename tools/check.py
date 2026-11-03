"""Validate the translation corpus, placeholders and original game fingerprints."""
from collections import Counter
import json
from pathlib import Path
import re

from patch import read_json, make_tables, verify_target, ROOT, DEFAULT_GAME, TOKEN


def main():
    catalog = read_json(ROOT / "local/survey/catalog.json")
    translations = read_json(ROOT / "translations/ko.json")
    extra = read_json(ROOT / "translations/ui.json")
    keyed, ui, conflicts = make_tables(catalog, translations, extra)
    required = {row["id"] for row in catalog if row["en"]}
    missing = required - translations.keys()
    if missing:
        raise ValueError("Untranslated English keys: " + str(len(missing)))
    report = {"english_keys": len(required), "translated_english_keys": len(required & translations.keys()),
              "key_aliases": len(keyed), "ui_matches": len(ui), "ambiguous_ui_matches": conflicts,
              "extra_ui_entries": len(extra),
              "source_tokens_checked": sum(len(TOKEN.findall(r["en"])) for r in catalog if r["id"] in translations),
              "longest_korean_text_chars": max(map(len, translations.values()))}
    extra_survey = ROOT / "local/survey-extra"
    if (extra_survey / "items.json").exists():
        item_names = {row["item_name"] for row in read_json(extra_survey / "items.json")}
        report["item_data_names_translated"] = len(item_names & extra.keys())
        report["item_data_names_unresolved"] = sorted(item_names - extra.keys())
    if (extra_survey / "physical-objects.json").exists():
        # This build's ObjectGrabber.grabbableLayer mask is 34816 (layers 11 and 15).
        names = {row["name"] for row in read_json(extra_survey / "physical-objects.json") if (1 << row["layer"]) & 34816}
        missing_objects = {name for name in names if re.sub(r"(?:\s*\((?:Clone|\d+)\))+$", "", name) not in extra}
        report["grabbable_object_names"] = len(names)
        report["grabbable_object_names_untranslated"] = sorted(missing_objects)
        if missing_objects:
            raise ValueError("Untranslated grabbed-object labels: " + str(sorted(missing_objects)))
    verify_target(DEFAULT_GAME, read_json(ROOT / "config/target.json"))
    report["original_game_fingerprints_match"] = True
    (ROOT / "local/verification").mkdir(parents=True, exist_ok=True)
    (ROOT / "local/verification/corpus.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
