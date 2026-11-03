using System;
using System.Globalization;
using System.Text.RegularExpressions;

namespace SabadoKorean
{
    // Presentation-only translation. Never change object names, item IDs or save data.
    internal static class DisplayText
    {
        private static readonly Regex Whitespace = new Regex(@"\s+");
        private static readonly Regex Wrapper = new Regex(@"^(?<open>(?:<(?:[A-Za-z][^<>]*|#[0-9A-Fa-f]+)>)+)(?<body>[^<>]+)(?<close>(?:</[A-Za-z]+>)+)$", RegexOptions.Singleline);
        private static readonly Regex InstanceSuffix = new Regex(@"^(?<name>.+?)(?<suffix>(?:\s*\((?:Clone|\d+)\))+)$");
        private static readonly Regex Counter = new Regex(@"^(?<label>Coverage:|Accuracy:|Score:)(?<value>\s*\d[\d\s.,/%+-]*)$");
        private static readonly Regex Score = new Regex(@"^You scored (?<value>\d+) points!$");

        internal static string Translate(string original, Func<string, string> lookup)
        {
            if (string.IsNullOrEmpty(original)) return original;
            string text = original.Trim();
            string translated = lookup(text) ?? lookup(Whitespace.Replace(text, " "));
            if (translated != null) return translated;

            Match wrapper = Wrapper.Match(text);
            if (wrapper.Success)
            {
                string body = wrapper.Groups["body"].Value;
                translated = Translate(body, lookup);
                if (translated != body)
                    return wrapper.Groups["open"].Value + translated + wrapper.Groups["close"].Value;
            }
            Match instance = InstanceSuffix.Match(text);
            if (instance.Success && (translated = lookup(instance.Groups["name"].Value.TrimEnd())) != null)
                return translated + instance.Groups["suffix"].Value;
            Match counter = Counter.Match(text);
            if (counter.Success && (translated = lookup(counter.Groups["label"].Value)) != null)
                return translated + counter.Groups["value"].Value;
            Match score = Score.Match(text);
            if (score.Success && (translated = lookup("You scored {0} points!")) != null)
                return string.Format(CultureInfo.InvariantCulture, translated, score.Groups["value"].Value);

            // Translate separate label lines while leaving unknown text and numbers alone.
            if (text.IndexOf('\n') >= 0)
            {
                string[] lines = text.Replace("\r\n", "\n").Split('\n');
                bool any = false;
                for (int i = 0; i < lines.Length; i++)
                {
                    string line = Translate(lines[i], lookup);
                    any |= line != lines[i];
                    lines[i] = line;
                }
                if (any) return string.Join("\n", lines);
            }
            return original;
        }
    }
}
