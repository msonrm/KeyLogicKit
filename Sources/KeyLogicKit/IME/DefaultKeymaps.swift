import Foundation

#if !SWIFT_PACKAGE
/// XcodeGen ビルド用 Bundle.module 互換シム
private class _BundleToken {}
extension Bundle {
    static let module = Bundle(for: _BundleToken.self)
}
#endif

/// 組み込みキーマップ定義
///
/// アプリに同梱されるデフォルトのキーマップを提供する。
/// JSON ファイルのキーマップは Bundle 内から読み込む。
public enum DefaultKeymaps {

    /// ローマ字入力（US 配列）
    public static let romajiUS = KeymapDefinition(
        name: "ローマ字(US)",
        behavior: .sequential(characterMap: h2zMapUS),
        keyboardLayout: "us",
        inputBase: "romaji",
        description: "標準ローマ字入力（US キーボード）",
        targetScript: "hiragana"
    )

    // MARK: - 標準ローマ字テーブル

    /// 標準ローマ字→ひらがな変換テーブル
    ///
    /// `inputBase: "romaji"` 指定時のベーステーブルとして使用する。
    /// AzooKey の trie と同等の標準ローマ字マッピングを網羅。
    /// 変体綴り（shi/si, chi/ti, tsu/tu, fu/hu）を含む。
    public static let standardRomajiTable: [String: String] = [
        // 母音
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        // か行
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        // さ行
        "sa": "さ", "si": "し", "shi": "し", "su": "す", "se": "せ", "so": "そ",
        // た行
        "ta": "た", "ti": "ち", "chi": "ち", "tu": "つ", "tsu": "つ", "te": "て", "to": "と",
        // な行
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        // は行
        "ha": "は", "hi": "ひ", "hu": "ふ", "he": "へ", "ho": "ほ",
        // ま行
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        // や行
        "ya": "や", "yu": "ゆ", "yo": "よ",
        // ら行
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        // わ行
        "wa": "わ", "wi": "うぃ", "we": "うぇ", "wo": "を",
        // が行
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        // ざ行
        "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        // だ行
        "da": "だ", "di": "ぢ", "du": "づ", "dzu": "づ", "de": "で", "do": "ど",
        // ば行
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        // ぱ行
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        // 拗音（きゃ行〜）
        "kya": "きゃ", "kyu": "きゅ", "kye": "きぇ", "kyo": "きょ",
        "sya": "しゃ", "syu": "しゅ", "sye": "しぇ", "syo": "しょ",
        "sha": "しゃ", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
        "tya": "ちゃ", "tyu": "ちゅ", "tye": "ちぇ", "tyo": "ちょ",
        "cha": "ちゃ", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
        "nya": "にゃ", "nyu": "にゅ", "nye": "にぇ", "nyo": "にょ",
        "hya": "ひゃ", "hyu": "ひゅ", "hye": "ひぇ", "hyo": "ひょ",
        "mya": "みゃ", "myu": "みゅ", "mye": "みぇ", "myo": "みょ",
        "rya": "りゃ", "ryu": "りゅ", "rye": "りぇ", "ryo": "りょ",
        "gya": "ぎゃ", "gyu": "ぎゅ", "gye": "ぎぇ", "gyo": "ぎょ",
        "zya": "じゃ", "zyu": "じゅ", "zye": "じぇ", "zyo": "じょ",
        "ja": "じゃ", "ju": "じゅ", "je": "じぇ", "jo": "じょ",
        "bya": "びゃ", "byu": "びゅ", "bye": "びぇ", "byo": "びょ",
        "pya": "ぴゃ", "pyu": "ぴゅ", "pye": "ぴぇ", "pyo": "ぴょ",
        // 外来音
        "fa": "ふぁ", "fi": "ふぃ", "fu": "ふ", "fe": "ふぇ", "fo": "ふぉ",
        "va": "ヴぁ", "vi": "ヴぃ", "vu": "ヴ", "ve": "ヴぇ", "vo": "ヴぉ",
        "tgi": "てぃ", "tgu": "とぅ", "dci": "でぃ", "dcu": "どぅ", "wso": "うぉ",
        // 撥音
        "n": "ん", "nn": "ん",
        // 促音（子音重ね → っ + かな）
        // kk
        "kka": "っか", "kki": "っき", "kku": "っく", "kke": "っけ", "kko": "っこ",
        // ss
        "ssa": "っさ", "ssi": "っし", "ssu": "っす", "sse": "っせ", "sso": "っそ",
        // tt
        "tta": "った", "tti": "っち", "ttu": "っつ", "tte": "って", "tto": "っと",
        // hh
        "hha": "っは", "hhi": "っひ", "hhu": "っふ", "hhe": "っへ", "hho": "っほ",
        // mm
        "mma": "っま", "mmi": "っみ", "mmu": "っむ", "mme": "っめ", "mmo": "っも",
        // rr
        "rra": "っら", "rri": "っり", "rru": "っる", "rre": "っれ", "rro": "っろ",
        // gg
        "gga": "っが", "ggi": "っぎ", "ggu": "っぐ", "gge": "っげ", "ggo": "っご",
        // zz
        "zza": "っざ", "zzi": "っじ", "zzu": "っず", "zze": "っぜ", "zzo": "っぞ",
        // dd
        "dda": "っだ", "ddi": "っぢ", "ddu": "っづ", "dde": "っで", "ddo": "っど",
        // bb
        "bba": "っば", "bbi": "っび", "bbu": "っぶ", "bbe": "っべ", "bbo": "っぼ",
        // pp
        "ppa": "っぱ", "ppi": "っぴ", "ppu": "っぷ", "ppe": "っぺ", "ppo": "っぽ",
        // ff
        "ffa": "っふぁ", "ffi": "っふぃ", "ffu": "っふ", "ffe": "っふぇ", "ffo": "っふぉ",
        // jj
        "jja": "っじゃ", "jji": "っじ", "jju": "っじゅ", "jje": "っじぇ", "jjo": "っじょ",
        // cc
        "cca": "っか", "cci": "っち", "ccu": "っく", "cce": "っけ", "cco": "っこ",
        "ccha": "っちゃ", "cchi": "っち", "cchu": "っちゅ", "cche": "っちぇ", "ccho": "っちょ",
        // 小書き x-series
        "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
        "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ", "xtu": "っ", "xtsu": "っ", "xwa": "ゎ",
        // 小書き l-series
        "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
        "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ", "ltu": "っ", "ltsu": "っ", "lwa": "ゎ",
    ]

    // MARK: - 全キーマップ一覧

    /// 全組み込みキーマップ（KeymapManager から参照）
    public static let allKeymaps: [(id: String, definition: KeymapDefinition)] = {
        var keymaps: [(id: String, definition: KeymapDefinition)] = [
            ("builtin:romaji_us", romajiUS),
        ]
        // Bundle 内の JSON キーマップを読み込み
        let jsonKeymaps: [(id: String, fileName: String)] = [
            ("builtin:azik_us", "azik_us"),
            ("builtin:tsuki2-263_us", "tsuki2-263_us"),
            ("builtin:nicola_us", "nicola_us"),
            ("builtin:nicola_jis", "nicola_jis"),
        ]
        for (id, name) in jsonKeymaps {
            if let def = loadBundleKeymap(name) {
                keymaps.append((id: id, definition: def))
            }
        }
        return keymaps
    }()

    // MARK: - Bundle JSON 読み込み

    /// Bundle 内の JSON キーマップを読み込む
    ///
    /// `.copy("Resources/Keymaps")` はディレクトリ構造を保持するため、
    /// Bundle 内のパスはビルドシステムにより異なる。複数パスを探索する。
    public static func loadBundleKeymap(_ name: String) -> KeymapDefinition? {
        let ext = "json"
        let url: URL? =
            Bundle.module.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Keymaps")
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources/Keymaps")
        guard let url,
              let data = try? Data(contentsOf: url),
              let definition = try? KeymapStore.decode(from: data)
        else {
            return nil
        }
        return definition
    }

    // MARK: - 半角→全角マッピング（US 配列）

    /// 半角→全角/日本語文字マッピング（azooKey-Desktop の h2zMap 準拠）
    ///
    /// 全ての ASCII 記号・数字を日本語入力向けの文字に変換する。
    /// key.characters ベースなので、UIKit がキーボードレイアウトを解決済み。
    public static let h2zMapUS: [Character: Character] = [
        // 数字
        "0": "０", "1": "１", "2": "２", "3": "３", "4": "４",
        "5": "５", "6": "６", "7": "７", "8": "８", "9": "９",
        // 句読点
        ",": "、", ".": "。", "/": "・",
        // 括弧
        "[": "「", "]": "」", "{": "『", "}": "』",
        "(": "（", ")": "）", "<": "＜", ">": "＞",
        // 長音・記号
        "-": "ー", "~": "〜", "^": "＾", "_": "＿",
        // 引用符
        "\"": "\u{201D}", "'": "\u{2019}", "`": "｀",
        // 数学・論理
        "+": "＋", "=": "＝", "*": "＊",
        // 感嘆・疑問
        "!": "！", "?": "？", ":": "：", ";": "；",
        // その他記号
        "@": "＠", "#": "＃", "$": "＄", "%": "％",
        "&": "＆", "|": "｜", "\\": "＼", "¥": "￥",
    ]
}
