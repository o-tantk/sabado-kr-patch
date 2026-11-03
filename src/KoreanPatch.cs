using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using BepInEx;
using BepInEx.Configuration;
using HarmonyLib;
using TMPro;
using UnityEngine;
using UnityEngine.TextCore.LowLevel;

namespace SabadoKorean
{
    [BepInPlugin("local.sabado.korean", "Sabado Korean Patch", "0.1.0")]
    public sealed class KoreanPatch : BaseUnityPlugin
    {
        internal static KoreanPatch Instance;
        private readonly Dictionary<string, string> translations = new Dictionary<string, string>();
        private readonly Dictionary<string, string> ui = new Dictionary<string, string>();
        private readonly Dictionary<string, string> hashes = new Dictionary<string, string>();
        private readonly Dictionary<int, string[]> changed = new Dictionary<int, string[]>();
        private readonly HashSet<string> reported = new HashSet<string>();
        private ConfigEntry<bool> patchEnabled;
        private TMP_FontAsset koreanFont;
        private bool fontReady;
        private Harmony harmony;
        private float nextScan;

        private void Awake()
        {
            Instance = this;
            patchEnabled = Config.Bind("General", "Enabled", true, "Translate the game's English language slot into Korean.");
            string folder = Path.GetDirectoryName(Info.Location);
            LoadTable(Path.Combine(folder, "strings.tsv"), translations);
            LoadTable(Path.Combine(folder, "ui.tsv"), ui);
            harmony = new Harmony("local.sabado.korean");
            harmony.PatchAll(typeof(KoreanPatch).Assembly);
            Logger.LogInfo("Loaded " + translations.Count + " keyed translations and " + ui.Count + " exact UI matches. Game " + Application.version + "; Unity " + Application.unityVersion);
        }

        private void Start()
        {
            try
            {
                string fontPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), "malgun.ttf");
                if (!File.Exists(fontPath)) throw new FileNotFoundException("Malgun Gothic is not installed.", fontPath);
                // This target's TMP exposes its file-path factory internally. Keep the
                // exact signature pinned to the fingerprinted game DLL.
                var factory = AccessTools.Method(typeof(TMP_FontAsset), "CreateFontAsset", new[] {
                    typeof(string), typeof(int), typeof(int), typeof(int), typeof(GlyphRenderMode),
                    typeof(int), typeof(int), typeof(AtlasPopulationMode), typeof(bool) });
                if (factory == null) throw new MissingMethodException("TMP file-path font factory is unavailable.");
                koreanFont = (TMP_FontAsset)factory.Invoke(null, new object[] {fontPath, 0, 48, 5, GlyphRenderMode.SDFAA, 2048, 2048, AtlasPopulationMode.Dynamic, true});
                if (koreanFont == null) throw new InvalidOperationException("TMP font creation failed.");
                koreanFont.name = "Sabado Korean Malgun Gothic";
                DontDestroyOnLoad(koreanFont);
                foreach (var atlas in koreanFont.atlasTextures) if (atlas != null) DontDestroyOnLoad(atlas);
                if (koreanFont.material != null) DontDestroyOnLoad(koreanFont.material);
                string characters = new string(string.Concat(translations.Values).Concat(string.Concat(ui.Values)).Concat("한국어 (패치)").Where(c => !char.IsControl(c)).Distinct().ToArray());
                string missing;
                bool complete = koreanFont.TryAddCharacters(characters, out missing);
                Logger.LogInfo("Korean font ready. Characters=" + characters.Length + "; complete=" + complete + "; missing=" + missing);
                fontReady = true;
            }
            catch (Exception ex)
            {
                fontReady = false;
                Logger.LogError("Korean display disabled because font initialization failed: " + ex);
            }
        }

        private static void LoadTable(string path, Dictionary<string, string> table)
        {
            foreach (string line in File.ReadAllLines(path, Encoding.UTF8))
            {
                if (string.IsNullOrWhiteSpace(line) || line.StartsWith("#")) continue;
                int separator = line.IndexOf('\t');
                if (separator != 64) throw new InvalidDataException("Invalid translation row in " + Path.GetFileName(path));
                string value = line.Substring(separator + 1).Replace("\\n", "\n").Replace("\\t", "\t");
                table.Add(line.Substring(0, separator), value);
            }
        }

        internal bool Active
        {
            get
            {
                return fontReady && patchEnabled.Value && (CSVLocalizationManager.Instance == null || CSVLocalizationManager.Instance.CurrentLanguageCSVHeader == "English");
            }
        }

        private string Hash(string text)
        {
            text = text.Trim();
            string result;
            if (hashes.TryGetValue(text, out result)) return result;
            using (var sha = SHA256.Create())
                result = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-", "").ToLowerInvariant();
            hashes[text] = result;
            return result;
        }

        internal string Translate(string key, string original)
        {
            string value;
            return Active && key != null && translations.TryGetValue(Hash(key), out value) ? value : original;
        }

        private void Update()
        {
            if (Time.unscaledTime < nextScan || koreanFont == null) return;
            nextScan = Time.unscaledTime + 0.35f;
            foreach (TMP_Text component in UnityEngine.Object.FindObjectsByType<TMP_Text>(FindObjectsSortMode.None))
            {
                if (component == null || !component.gameObject.activeInHierarchy) continue;
                string current = component.text;
                if (string.IsNullOrEmpty(current)) continue;
                int id = component.GetInstanceID();
                string[] previous;
                if (!Active)
                {
                    if (changed.TryGetValue(id, out previous) && current == previous[1]) component.text = previous[0];
                    continue;
                }
                string replacement;
                if (ui.TryGetValue(Hash(current), out replacement) && replacement != current)
                {
                    changed[id] = new[] { current, replacement };
                    component.text = replacement;
                    current = replacement;
                }
                if (!current.Any(c => c >= '\uAC00' && c <= '\uD7A3')) continue;
                if (component.font != koreanFont)
                {
                    component.font = koreanFont;
                    component.fontSharedMaterial = koreanFont.material;
                    component.havePropertiesChanged = true;
                }
                string marker = id + ":" + current;
                if (reported.Add(marker))
                {
                    component.ForceMeshUpdate();
                    if (component.isTextOverflowing)
                        Logger.LogWarning("Layout overflow: " + component.name + " / " + current.Replace('\n', ' '));
                }
            }
        }

        private void OnDestroy()
        {
            if (harmony != null) harmony.UnpatchSelf();
        }
    }

    [HarmonyPatch(typeof(CSVLocalizationManager), "GetText")]
    internal static class TranslatePatch
    {
        private static void Postfix(string key, ref string __result)
        {
            if (KoreanPatch.Instance != null) __result = KoreanPatch.Instance.Translate(key, __result);
        }
    }

    // Relabel only the text-language dropdown, never the voice-language dropdown.
    [HarmonyPatch(typeof(LanguageDropdown), "Start")]
    internal static class LanguageLabelPatch
    {
        private static void Postfix(TMP_Dropdown ___languageDropdown)
        {
            if (___languageDropdown == null || KoreanPatch.Instance == null || !KoreanPatch.Instance.Active) return;
            foreach (var option in ___languageDropdown.options)
                if (option.text == "English") option.text = "한국어 (패치)";
            ___languageDropdown.RefreshShownValue();
        }
    }
}
