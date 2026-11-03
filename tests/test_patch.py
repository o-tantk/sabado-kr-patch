import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch as mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import patch


class PatchSafetyTests(unittest.TestCase):
    def setUp(self):
        parent = patch.ROOT / "local/tests"
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=parent)
        self.base = Path(self.temp.name)
        self.game = self.base / "game"
        self.game.mkdir()
        (self.game / "game.bin").write_bytes(b"original game")
        self.package = self.base / "package"
        self.plugin = "BepInEx/plugins/SabadoKorean/SabadoKorean.dll"
        patch.child(self.package, self.plugin).parent.mkdir(parents=True)
        patch.child(self.package, self.plugin).write_bytes(b"plugin v1")
        (self.package / "winhttp.dll").write_bytes(b"loader")
        self.target = {"steam_build_id": "test", "files": {"game.bin": patch.sha256(self.game / "game.bin")}}
        self.stopped = mock.object(patch, "ensure_stopped")
        self.stopped.start()

    def tearDown(self):
        self.stopped.stop()
        self.temp.cleanup()

    def install(self):
        patch.install(self.game, self.package, self.base / "backups", self.target)

    def test_install_update_remove_preserves_original_and_unrelated_file(self):
        self.install()
        patch.child(self.game, "BepInEx/LogOutput.log").write_text("keep generated log")
        patch.child(self.package, self.plugin).write_bytes(b"plugin v2")
        self.install()
        manifests = list((self.base / "backups").glob("*/recovery.json"))
        self.assertEqual(len(manifests), 2)
        self.assertTrue(any(patch.child(p.parent / "files", self.plugin).exists() for p in manifests))
        patch.remove(self.game)
        self.assertEqual((self.game / "game.bin").read_bytes(), b"original game")
        self.assertFalse((self.game / "winhttp.dll").exists())
        self.assertTrue((self.game / "BepInEx/LogOutput.log").exists())
        self.install()  # Generated empty folders/logs must not prevent reinstalling.

    def test_target_mismatch_does_not_modify_installation(self):
        (self.game / "game.bin").write_bytes(b"different game")
        with self.assertRaises(ValueError):
            self.install()
        self.assertFalse((self.game / "winhttp.dll").exists())

    def test_modified_patch_is_not_removed(self):
        self.install()
        (self.game / "winhttp.dll").write_bytes(b"user modification")
        with self.assertRaises(ValueError):
            patch.remove(self.game)
        self.assertTrue((self.game / patch.MANIFEST).exists())
        self.assertTrue(patch.child(self.game, self.plugin).exists())

    def test_unrelated_loader_is_not_overwritten(self):
        (self.game / "winhttp.dll").write_bytes(b"other loader")
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual((self.game / "winhttp.dll").read_bytes(), b"other loader")

    def test_failed_copy_rolls_back(self):
        original_copy = patch.atomic_copy
        def fail_plugin(source, destination):
            if destination == patch.child(self.game, self.plugin):
                raise OSError("simulated write failure")
            original_copy(source, destination)
        with mock.object(patch, "atomic_copy", side_effect=fail_plugin):
            with self.assertRaises(OSError):
                self.install()
        self.assertFalse((self.game / "winhttp.dll").exists())
        self.assertFalse((self.game / patch.MANIFEST).exists())

    def test_path_traversal_is_rejected(self):
        with self.assertRaises(ValueError):
            patch.child(self.game, "../outside")

    def test_game_assets_cannot_be_smuggled_into_package(self):
        (self.package / "game.bin").write_bytes(b"overwrite original")
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual((self.game / "game.bin").read_bytes(), b"original game")

    def test_translation_tokens_and_native_quote_alias(self):
        key = 'key "quoted"'
        identity = patch.source_id(key)
        catalog = [{"id": identity, "key": key, "en": "<b>Hello {0}</b> [E]", "fil": ""}]
        korean = "<b>안녕 {0}</b> [E]"
        keyed, _, _ = patch.make_tables(catalog, {identity: korean}, {})
        self.assertEqual(keyed[patch.source_id('key quoted')], korean)
        with self.assertRaises(ValueError):
            patch.validate_translations(catalog, {identity: "안녕"})

    def test_ui_whitespace_aliases_and_conflicts(self):
        _, ui, _ = patch.make_tables([], {}, {"Game\n tutorial": "게임 설명"})
        self.assertEqual(ui[patch.source_id("Game tutorial")], "게임 설명")
        with self.assertRaises(ValueError):
            patch.make_tables([], {}, {"Game tutorial": "게임 설명", "Game\n tutorial": "다른 번역"})

    def test_dynamic_ui_placeholders_are_preserved(self):
        with self.assertRaises(ValueError):
            patch.make_tables([], {}, {"You scored {0} points!": "점수를 얻었어요!"})


if __name__ == "__main__":
    unittest.main()
