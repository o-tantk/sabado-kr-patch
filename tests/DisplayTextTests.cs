using System;
using System.Collections.Generic;
using SabadoKorean;

internal static class DisplayTextTests
{
    private static readonly Dictionary<string, string> Table = new Dictionary<string, string> {
        {"Jacob", "제이콥"}, {"Chesa", "체사"}, {"Beads", "구슬"}, {"Wallet", "지갑"},
        {"Game tutorial", "게임 설명"}, {"Coverage:", "완성도:"},
        {"You scored {0} points!", "{0}점을 얻었어요!"}
    };
    private static string Lookup(string text) { string result; return Table.TryGetValue(text, out result) ? result : null; }
    private static void Check(string input, string expected)
    {
        string result = DisplayText.Translate(input, Lookup);
        if (result != expected) throw new Exception("Unexpected display translation: " + input + " => " + result);
    }
    public static void Main()
    {
        Check("Jacob", "제이콥");
        Check(" Chesa\r\n", "체사");
        Check("<color=#00ffff><b>Jacob</b></color>", "<color=#00ffff><b>제이콥</b></color>");
        Check("Beads (2)", "구슬 (2)");
        Check("Wallet(Clone)", "지갑(Clone)");
        Check("Beads (2)(Clone)", "구슬 (2)(Clone)");
        Check("Game\n tutorial", "게임 설명");
        Check("Coverage: 37% / 100%", "완성도: 37% / 100%");
        Check("You scored 12 points!", "12점을 얻었어요!");
        Check("Chesa\nCoverage: 84%", "체사\n완성도: 84%");
        Check("<sprite=2> Jacob", "<sprite=2> Jacob");
        Check("Jacob's wallet ID", "Jacob's wallet ID");
        Check("Beads (quest-key)", "Beads (quest-key)");
        Check(" 未翻訳 ", " 未翻訳 ");
        Check("제이콥", "제이콥");
        Check(null, null);
        Console.WriteLine("Display translation: 16 checks passed.");
    }
}
