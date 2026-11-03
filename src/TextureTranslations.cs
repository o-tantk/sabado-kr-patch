using System;
using System.Collections.Generic;
using System.IO;
using BepInEx.Logging;
using UnityEngine;
using UnityEngine.UI;

namespace SabadoKorean
{
    // Only explicitly catalogued material slots are replaced. Game asset files and
    // the original Texture2D objects remain intact, including their import settings.
    internal sealed class TextureTranslations : IDisposable
    {
        private sealed class Entry
        {
            internal string Kind, Name, Material, Property;
            internal int Width, Height;
            internal byte[] Png;
        }

        private sealed class Change
        {
            internal Material Material;
            internal string Property;
            internal Texture Original;
            internal Texture2D Replacement;
        }

        private sealed class SpriteChange
        {
            internal Image Image;
            internal Sprite Original, Replacement;
        }

        private readonly List<Entry> entries = new List<Entry>();
        private readonly List<Change> changes = new List<Change>();
        private readonly List<SpriteChange> spriteChanges = new List<SpriteChange>();
        private readonly Dictionary<int, Texture2D> replacements = new Dictionary<int, Texture2D>();
        private readonly Dictionary<int, Sprite> sprites = new Dictionary<int, Sprite>();
        private readonly ManualLogSource log;
        private float nextScan;

        internal TextureTranslations(string folder, ManualLogSource log)
        {
            this.log = log;
            string table = Path.Combine(folder, "textures.tsv");
            if (!File.Exists(table)) return;
            foreach (string line in File.ReadAllLines(table))
            {
                if (string.IsNullOrWhiteSpace(line) || line.StartsWith("#")) continue;
                string[] row = line.Split('\t');
                if (row.Length != 7 || (row[6] != "material" && row[6] != "sprite") || Path.GetFileName(row[5]) != row[5] || !row[5].EndsWith(".png", StringComparison.Ordinal))
                    throw new InvalidDataException("Invalid texture translation row");
                entries.Add(new Entry { Kind = row[6], Name = row[0], Width = int.Parse(row[1]), Height = int.Parse(row[2]),
                    Material = row[3], Property = row[4], Png = File.ReadAllBytes(Path.Combine(folder, "textures", row[5])) });
            }
            log.LogInfo("Loaded " + entries.Count + " translated texture slots.");
        }

        internal void Update(bool active)
        {
            if (!active) { Restore(); return; }
            if (Time.unscaledTime < nextScan || entries.Count == 0) return;
            nextScan = Time.unscaledTime + 1f;
            // Unloaded scenes must not leave dead material references in the journal.
            changes.RemoveAll(c => c.Material == null);
            spriteChanges.RemoveAll(c => c.Image == null);
            foreach (Material material in Resources.FindObjectsOfTypeAll<Material>())
            {
                if (material == null) continue;
                foreach (Entry entry in entries)
                {
                    if (entry.Kind != "material") continue;
                    if ((material.name != entry.Material && material.name != entry.Material + " (Instance)") || !material.HasProperty(entry.Property)) continue;
                    Texture source = material.GetTexture(entry.Property);
                    if (source == null || source.name != entry.Name || source.width != entry.Width || source.height != entry.Height) continue;
                    Texture2D replacement = GetTexture(source, entry);
                    if (!changes.Exists(c => c.Material == material && c.Property == entry.Property))
                        changes.Add(new Change { Material = material, Property = entry.Property, Original = source, Replacement = replacement });
                    material.SetTexture(entry.Property, replacement);
                    log.LogInfo("Korean image applied: " + entry.Name + " -> " + material.name + "." + entry.Property);
                }
            }
            foreach (Image image in Resources.FindObjectsOfTypeAll<Image>())
            {
                if (image == null) continue;
                Sprite source = image.sprite;
                if (source == null || source.texture == null) continue;
                foreach (Entry entry in entries)
                {
                    if (entry.Kind != "sprite" || source.name != entry.Name || source.texture.name != entry.Name ||
                        source.texture.width != entry.Width || source.texture.height != entry.Height) continue;
                    // The selected tutorial sprites are full rectangular images, with
                    // no slicing or atlas packing. Refuse a changed import layout.
                    if (source.packed || source.rect != new Rect(0, 0, entry.Width, entry.Height) || source.border != Vector4.zero) continue;
                    Sprite replacement;
                    if (!sprites.TryGetValue(source.GetInstanceID(), out replacement))
                    {
                        Texture2D texture = GetTexture(source.texture, entry);
                        replacement = Sprite.Create(texture, new Rect(0, 0, texture.width, texture.height),
                            new Vector2(source.pivot.x / source.rect.width, source.pivot.y / source.rect.height),
                            source.pixelsPerUnit * texture.width / source.rect.width, 0, SpriteMeshType.FullRect);
                        replacement.name = "Sabado Korean / " + source.name;
                        UnityEngine.Object.DontDestroyOnLoad(replacement);
                        sprites[source.GetInstanceID()] = replacement;
                    }
                    // A slideshow may reuse the same Image for multiple source sprites.
                    spriteChanges.RemoveAll(c => c.Image == image);
                    spriteChanges.Add(new SpriteChange { Image = image, Original = source, Replacement = replacement });
                    image.sprite = replacement;
                    log.LogInfo("Korean tutorial image applied: " + entry.Name + " -> " + image.name);
                }
            }
        }

        private Texture2D GetTexture(Texture source, Entry entry)
        {
            Texture2D replacement;
            if (replacements.TryGetValue(source.GetInstanceID(), out replacement)) return replacement;
            replacement = new Texture2D(2, 2, TextureFormat.RGBA32, true, false);
            if (!ImageConversion.LoadImage(replacement, entry.Png, true))
            { UnityEngine.Object.Destroy(replacement); throw new InvalidDataException("Cannot decode Korean texture: " + entry.Name); }
            replacement.name = "Sabado Korean / " + source.name;
            replacement.wrapMode = source.wrapMode;
            replacement.filterMode = source.filterMode;
            replacement.anisoLevel = source.anisoLevel;
            UnityEngine.Object.DontDestroyOnLoad(replacement);
            replacements[source.GetInstanceID()] = replacement;
            return replacement;
        }

        private void Restore()
        {
            foreach (Change change in changes)
                if (change.Material != null && change.Original != null && change.Material.GetTexture(change.Property) == change.Replacement)
                    change.Material.SetTexture(change.Property, change.Original);
            if (changes.Count != 0) log.LogInfo("Original image textures restored (" + changes.Count + " slots).");
            changes.Clear();
            foreach (SpriteChange change in spriteChanges)
                if (change.Image != null && change.Original != null && change.Image.sprite == change.Replacement)
                    change.Image.sprite = change.Original;
            if (spriteChanges.Count != 0) log.LogInfo("Original tutorial images restored (" + spriteChanges.Count + ").");
            spriteChanges.Clear();
        }

        public void Dispose()
        {
            Restore();
            foreach (Sprite sprite in sprites.Values)
                if (sprite != null) UnityEngine.Object.Destroy(sprite);
            sprites.Clear();
            foreach (Texture2D texture in replacements.Values)
                if (texture != null) UnityEngine.Object.Destroy(texture);
            replacements.Clear();
        }
    }
}
