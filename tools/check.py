"""Validate the translation corpus, placeholders and original game fingerprints."""
from collections import Counter
import json
from pathlib import Path

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
              "source_tokens_checked": sum(len(TOKEN.findall(r["en"])) for r in catalog if r["id"] in translations),
              "longest_korean_text_chars": max(map(len, translations.values()))}
    verify_target(DEFAULT_GAME, read_json(ROOT / "config/target.json"))
    report["original_game_fingerprints_match"] = True
    (ROOT / "local/verification").mkdir(parents=True, exist_ok=True)
    (ROOT / "local/verification/corpus.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
