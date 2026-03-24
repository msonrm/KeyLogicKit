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

    /// US キーボード用 modeKeys（ctrl+space トグル + ctrl+shift+j/; 切替）
    private static let usModeKeys: [KeymapDefinition.ModeKeyTrigger: KeyAction] = [
        .init(keyCode: .keyboardSpacebar, modifiers: .control): .toggleInputMode,
        .init(keyCode: .keyboardJ, modifiers: [.control, .shift]): .switchToJapanese,
        .init(keyCode: .keyboardSemicolon, modifiers: [.control, .shift]): .switchToEnglish,
    ]

    /// JIS キーボード用 modeKeys（lang1/lang2 + ctrl+shift+j/; 切替）
    private static let jisModeKeys: [KeymapDefinition.ModeKeyTrigger: KeyAction] = [
        .init(keyCode: .keyboardLANG2): .switchToEnglish,
        .init(keyCode: .keyboardLANG1): .switchToJapanese,
        .init(keyCode: .keyboardSpacebar, modifiers: .control): .toggleInputMode,
        .init(keyCode: .keyboardJ, modifiers: [.control, .shift]): .switchToJapanese,
        .init(keyCode: .keyboardSemicolon, modifiers: [.control, .shift]): .switchToEnglish,
    ]

    /// ローマ字入力（US 配列）
    public static let romajiUS = KeymapDefinition(
        name: "ローマ字(US)",
        behavior: .sequential(characterMap: h2zMapUS),
        keyboardLayout: "us",
        inputBase: "romaji",
        modeKeys: usModeKeys,
        description: "標準ローマ字入力（US キーボード）",
        targetScript: "hiragana"
    )

    /// ローマ字入力（JIS 配列）
    public static let romajiJIS = KeymapDefinition(
        name: "ローマ字(JIS)",
        behavior: .sequential(characterMap: h2zMapUS),
        keyboardLayout: "jis",
        inputBase: "romaji",
        modeKeys: jisModeKeys,
        description: "標準ローマ字入力（JIS キーボード）",
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
        // か行（c 系変体綴り含む）
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "ca": "か", "ci": "し", "cu": "く", "ce": "せ", "co": "こ",
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
        "wyi": "ゐ", "wye": "ゑ", "whu": "う",
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
        // や行（いぇ）
        "ye": "いぇ",
        // 拗音（きゃ行〜）
        "kya": "きゃ", "kyu": "きゅ", "kye": "きぇ", "kyo": "きょ",
        "sya": "しゃ", "syu": "しゅ", "sye": "しぇ", "syo": "しょ",
        "sha": "しゃ", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
        "tya": "ちゃ", "tyi": "ちぃ", "tyu": "ちゅ", "tye": "ちぇ", "tyo": "ちょ",
        "cha": "ちゃ", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
        "cya": "ちゃ", "cyi": "ちぃ", "cyu": "ちゅ", "cye": "ちぇ", "cyo": "ちょ",
        "nya": "にゃ", "nyi": "にぃ", "nyu": "にゅ", "nye": "にぇ", "nyo": "にょ",
        "hya": "ひゃ", "hyi": "ひぃ", "hyu": "ひゅ", "hye": "ひぇ", "hyo": "ひょ",
        "mya": "みゃ", "myi": "みぃ", "myu": "みゅ", "mye": "みぇ", "myo": "みょ",
        "rya": "りゃ", "ryi": "りぃ", "ryu": "りゅ", "rye": "りぇ", "ryo": "りょ",
        "gya": "ぎゃ", "gyu": "ぎゅ", "gye": "ぎぇ", "gyo": "ぎょ",
        "zya": "じゃ", "zyu": "じゅ", "zye": "じぇ", "zyo": "じょ",
        "ja": "じゃ", "ju": "じゅ", "je": "じぇ", "jo": "じょ",
        "jya": "じゃ", "jyi": "じぃ", "jyu": "じゅ", "jye": "じぇ", "jyo": "じょ",
        "bya": "びゃ", "byi": "びぃ", "byu": "びゅ", "bye": "びぇ", "byo": "びょ",
        "pya": "ぴゃ", "pyi": "ぴぃ", "pyu": "ぴゅ", "pye": "ぴぇ", "pyo": "ぴょ",
        // 拗音（ぢゃ行）
        "dya": "ぢゃ", "dyi": "ぢぃ", "dyu": "ぢゅ", "dye": "ぢぇ", "dyo": "ぢょ",
        // 外来音（ふ行: f/hw/fw 系）
        "fa": "ふぁ", "fi": "ふぃ", "fu": "ふ", "fe": "ふぇ", "fo": "ふぉ",
        "fya": "ふゃ", "fyu": "ふゅ", "fyo": "ふょ",
        "fwa": "ふぁ", "fwi": "ふぃ", "fwu": "ふぅ", "fwe": "ふぇ", "fwo": "ふぉ",
        "hwa": "ふぁ", "hwi": "ふぃ", "hwe": "ふぇ", "hwo": "ふぉ",
        // 外来音（ヴ行）
        "va": "ヴぁ", "vi": "ヴぃ", "vu": "ヴ", "ve": "ヴぇ", "vo": "ヴぉ",
        "vya": "ゔゃ", "vyu": "ゔゅ", "vyo": "ゔょ",
        // 外来音（てぃ系: th）
        "tha": "てゃ", "thi": "てぃ", "thu": "てゅ", "the": "てぇ", "tho": "てょ",
        // 外来音（でぃ系: dh）
        "dha": "でゃ", "dhi": "でぃ", "dhu": "でゅ", "dhe": "でぇ", "dho": "でょ",
        // 外来音（とぅ系: tw）
        "twa": "とぁ", "twi": "とぃ", "twu": "とぅ", "twe": "とぇ", "two": "とぉ",
        // 外来音（どぅ系: dw）
        "dwa": "どぁ", "dwi": "どぃ", "dwu": "どぅ", "dwe": "どぇ", "dwo": "どぉ",
        // 外来音（すぁ行: sw）
        "swa": "すぁ", "swi": "すぃ", "swu": "すぅ", "swe": "すぇ", "swo": "すぉ",
        // 外来音（つぁ行: ts）
        "tsa": "つぁ", "tsi": "つぃ", "tse": "つぇ", "tso": "つぉ",
        // 外来音（うぁ行: wh）
        "wha": "うぁ", "whi": "うぃ", "whe": "うぇ", "who": "うぉ",
        // 外来音（くぁ行: kw/q）
        "kwa": "くぁ", "kwi": "くぃ", "kwu": "くぅ", "kwe": "くぇ", "kwo": "くぉ",
        "qa": "くぁ", "qi": "くぃ", "qu": "くぅ", "qe": "くぇ", "qo": "くぉ",
        "qwa": "くぁ", "qwi": "くぃ", "qwu": "くぅ", "qwe": "くぇ", "qwo": "くぉ",
        // 外来音（ぐぁ行: gw）
        "gwa": "ぐぁ", "gwi": "ぐぃ", "gwu": "ぐぅ", "gwe": "ぐぇ", "gwo": "ぐぉ",
        // 小書き（カ行）
        "xka": "ヵ", "xke": "ヶ", "lka": "ヵ", "lke": "ヶ",
        // 撥音
        "n": "ん", "nn": "ん", "n'": "ん", "xn": "ん",
        // 促音（子音重ね → っ + かな）
        // kk
        "kka": "っか", "kki": "っき", "kku": "っく", "kke": "っけ", "kko": "っこ",
        "kkya": "っきゃ", "kkyu": "っきゅ", "kkye": "っきぇ", "kkyo": "っきょ",
        "kkwa": "っくぁ", "kkwi": "っくぃ", "kkwu": "っくぅ", "kkwe": "っくぇ", "kkwo": "っくぉ",
        // ss
        "ssa": "っさ", "ssi": "っし", "ssu": "っす", "sse": "っせ", "sso": "っそ",
        "ssha": "っしゃ", "sshi": "っし", "sshu": "っしゅ", "sshe": "っしぇ", "ssho": "っしょ",
        "ssya": "っしゃ", "ssyu": "っしゅ", "ssye": "っしぇ", "ssyo": "っしょ",
        "sswa": "っすぁ", "sswi": "っすぃ", "sswu": "っすぅ", "sswe": "っすぇ", "sswo": "っすぉ",
        // tt
        "tta": "った", "tti": "っち", "ttu": "っつ", "tte": "って", "tto": "っと",
        "ttya": "っちゃ", "ttyi": "っちぃ", "ttyu": "っちゅ", "ttye": "っちぇ", "ttyo": "っちょ",
        "tcha": "っちゃ", "tchi": "っち", "tchu": "っちゅ", "tche": "っちぇ", "tcho": "っちょ",
        "ttsa": "っつぁ", "ttsi": "っつぃ", "ttse": "っつぇ", "ttso": "っつぉ",
        "ttha": "ってゃ", "tthi": "ってぃ", "tthu": "ってゅ", "tthe": "ってぇ", "ttho": "ってょ",
        "ttwa": "っとぁ", "ttwi": "っとぃ", "ttwu": "っとぅ", "ttwe": "っとぇ", "ttwo": "っとぉ",
        // hh
        "hha": "っは", "hhi": "っひ", "hhu": "っふ", "hhe": "っへ", "hho": "っほ",
        "hhya": "っひゃ", "hhyi": "っひぃ", "hhyu": "っひゅ", "hhye": "っひぇ", "hhyo": "っひょ",
        // mm
        "mma": "っま", "mmi": "っみ", "mmu": "っむ", "mme": "っめ", "mmo": "っも",
        "mmya": "っみゃ", "mmyi": "っみぃ", "mmyu": "っみゅ", "mmye": "っみぇ", "mmyo": "っみょ",
        // rr
        "rra": "っら", "rri": "っり", "rru": "っる", "rre": "っれ", "rro": "っろ",
        "rrya": "っりゃ", "rryi": "っりぃ", "rryu": "っりゅ", "rrye": "っりぇ", "rryo": "っりょ",
        // gg
        "gga": "っが", "ggi": "っぎ", "ggu": "っぐ", "gge": "っげ", "ggo": "っご",
        "ggya": "っぎゃ", "ggyu": "っぎゅ", "ggye": "っぎぇ", "ggyo": "っぎょ",
        "ggwa": "っぐぁ", "ggwi": "っぐぃ", "ggwu": "っぐぅ", "ggwe": "っぐぇ", "ggwo": "っぐぉ",
        // zz
        "zza": "っざ", "zzi": "っじ", "zzu": "っず", "zze": "っぜ", "zzo": "っぞ",
        "zzya": "っじゃ", "zzyu": "っじゅ", "zzye": "っじぇ", "zzyo": "っじょ",
        // dd
        "dda": "っだ", "ddi": "っぢ", "ddu": "っづ", "dde": "っで", "ddo": "っど",
        "ddzu": "っづ",
        "ddya": "っぢゃ", "ddyi": "っぢぃ", "ddyu": "っぢゅ", "ddye": "っぢぇ", "ddyo": "っぢょ",
        "ddha": "っでゃ", "ddhi": "っでぃ", "ddhu": "っでゅ", "ddhe": "っでぇ", "ddho": "っでょ",
        "ddwa": "っどぁ", "ddwi": "っどぃ", "ddwu": "っどぅ", "ddwe": "っどぇ", "ddwo": "っどぉ",
        // bb
        "bba": "っば", "bbi": "っび", "bbu": "っぶ", "bbe": "っべ", "bbo": "っぼ",
        "bbya": "っびゃ", "bbyi": "っびぃ", "bbyu": "っびゅ", "bbye": "っびぇ", "bbyo": "っびょ",
        // pp
        "ppa": "っぱ", "ppi": "っぴ", "ppu": "っぷ", "ppe": "っぺ", "ppo": "っぽ",
        "ppya": "っぴゃ", "ppyi": "っぴぃ", "ppyu": "っぴゅ", "ppye": "っぴぇ", "ppyo": "っぴょ",
        // ff
        "ffa": "っふぁ", "ffi": "っふぃ", "ffu": "っふ", "ffe": "っふぇ", "ffo": "っふぉ",
        "ffya": "っふゃ", "ffyu": "っふゅ", "ffyo": "っふょ",
        "ffwa": "っふぁ", "ffwi": "っふぃ", "ffwu": "っふぅ", "ffwe": "っふぇ", "ffwo": "っふぉ",
        // jj
        "jja": "っじゃ", "jji": "っじ", "jju": "っじゅ", "jje": "っじぇ", "jjo": "っじょ",
        "jjyi": "っじぃ",
        "jjya": "っじゃ", "jjyu": "っじゅ", "jjye": "っじぇ", "jjyo": "っじょ",
        // cc
        "cca": "っか", "cci": "っち", "ccu": "っく", "cce": "っけ", "cco": "っこ",
        "ccha": "っちゃ", "cchi": "っち", "cchu": "っちゅ", "cche": "っちぇ", "ccho": "っちょ",
        "ccya": "っちゃ", "ccyi": "っちぃ", "ccyu": "っちゅ", "ccye": "っちぇ", "ccyo": "っちょ",
        // vv
        "vvu": "っゔ", "vva": "っゔぁ", "vvi": "っゔぃ", "vve": "っゔぇ", "vvo": "っゔぉ",
        "vvya": "っゔゃ", "vvyu": "っゔゅ", "vvyo": "っゔょ",
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
            ("builtin:romaji_jis", romajiJIS),
        ]
        // Bundle 内の JSON キーマップを読み込み
        let jsonKeymaps: [(id: String, fileName: String)] = [
            ("builtin:azik_us", "azik_us"),
            ("builtin:azik_jis", "azik_jis"),
            ("builtin:tsuki2-263_us", "tsuki2-263_us"),
            ("builtin:tsuki2-263_jis", "tsuki2-263_jis"),
            ("builtin:nicola_us", "nicola_us"),
            ("builtin:nicola_jis", "nicola_jis"),
            ("builtin:romaji_colemak_us", "romaji_colemak_us"),
            ("builtin:romaji_colemak_jis", "romaji_colemak_jis"),
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
