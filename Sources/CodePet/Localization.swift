import Foundation

/// Languages CodePet's UI can render in. `system` follows the OS preference.
enum AppLanguage: String, CaseIterable {
    case system, en, zhHans, zhHant, ja

    /// Native name shown in the Language menu.
    var menuTitle: String {
        switch self {
        case .system: return L.t(.langSystem)
        case .en:     return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja:     return "日本語"
        }
    }
}

/// Tiny in-app localization layer. The current language is global so plain
/// value types (PetActivity, Session) can localize without plumbing; views
/// re-render via the store when it changes.
enum L {
    static var language: AppLanguage = .system

    /// The concrete language to render, resolving `.system` from the OS.
    static var resolved: AppLanguage {
        if language != .system { return language }
        let code = Locale.preferredLanguages.first ?? "en"
        if code.hasPrefix("zh-Hant") || code.hasPrefix("zh-TW") || code.hasPrefix("zh-HK") {
            return .zhHant
        }
        if code.hasPrefix("zh") { return .zhHans }
        if code.hasPrefix("ja") { return .ja }
        return .en
    }

    enum Key {
        case idle, working, needsYou, ready, failed
        case noSessions, noSessionsHint, noActiveSessions
        case focusTerminal, revealInFinder, copyId, recent
        case showSessions, collapseCards, pet, refreshPets, position, snapToCorner
        case previewState, clearPreview, quit, language, langSystem
        case cornerBR, cornerBL, cornerTR, cornerTL
        case installedPets, petdexPets, codexPets, builtinForms
        case readyForReview
        case installFromPetdex, petdexLoading, petdexBrowseWeb
        case petdexInstalledTitle, petdexInstallFailedTitle, ok
        case petdexInstallByName, petdexEnterName, petdexInstalling, cancel, install
        case replyPlaceholder, replyPermTitle, replyPermBody, openSettings
    }

    static func t(_ k: Key) -> String { table[resolved]?[k] ?? table[.en]![k] ?? "" }

    /// Localize a stored (canonical-English) `detail` string at *render* time, so
    /// the status line follows the current language live. Status phrases and tool
    /// verbs are translated; free text (notification messages, file names, args)
    /// passes through unchanged.
    static func localizeDetail(_ raw: String) -> String {
        if let s = statusPhrases[resolved]?[raw] { return s }
        if let r = raw.range(of: ": ") {
            let verb = String(raw[..<r.lowerBound])
            if let v = actionVerbs[resolved]?[verb] {
                let arg = String(raw[r.upperBound...])
                return "\(v): \(friendlyArg(verb: verb, arg))"
            }
        }
        return raw
    }

    /// Turn a raw tool argument into something readable: file ops show just the
    /// file name, Bash shows just the program being run — instead of the full
    /// path / command line, which reads as technical noise under the pet.
    private static func friendlyArg(verb: String, _ arg: String) -> String {
        let a = arg.trimmingCharacters(in: .whitespaces)
        switch verb {
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
            return lastPathComponent(a)
        case "Bash":
            let program = a.split(separator: " ", maxSplits: 1).first.map(String.init) ?? a
            return lastPathComponent(program)
        default:
            return a
        }
    }

    private static func lastPathComponent(_ s: String) -> String {
        let parts = s.split(separator: "/", omittingEmptySubsequences: true)
        return parts.last.map(String.init) ?? s
    }

    private static let statusPhrases: [AppLanguage: [String: String]] = [
        .zhHans: ["thinking…": "思考中…", "waiting for input": "等待输入",
                  "session started": "会话开始", "done": "完成"],
        .zhHant: ["thinking…": "思考中…", "waiting for input": "等待輸入",
                  "session started": "工作階段開始", "done": "完成"],
        .ja:     ["thinking…": "思考中…", "waiting for input": "入力待ち",
                  "session started": "セッション開始", "done": "完了"],
    ]
    private static let actionVerbs: [AppLanguage: [String: String]] = [
        .zhHans: ["Edit": "编辑", "Write": "写入", "MultiEdit": "编辑", "NotebookEdit": "编辑",
                  "Read": "读取", "Bash": "运行", "Grep": "搜索", "Glob": "匹配",
                  "Task": "子任务", "Fetch": "抓取", "Search": "搜索"],
        .zhHant: ["Edit": "編輯", "Write": "寫入", "MultiEdit": "編輯", "NotebookEdit": "編輯",
                  "Read": "讀取", "Bash": "執行", "Grep": "搜尋", "Glob": "比對",
                  "Task": "子任務", "Fetch": "抓取", "Search": "搜尋"],
        .ja:     ["Edit": "編集", "Write": "書き込み", "MultiEdit": "編集", "NotebookEdit": "編集",
                  "Read": "読み取り", "Bash": "実行", "Grep": "検索", "Glob": "照合",
                  "Task": "サブタスク", "Fetch": "取得", "Search": "検索"],
    ]

    // MARK: Parameterized

    static func actions(_ n: Int) -> String {
        switch resolved {
        case .zhHans: return "\(n) 个操作"
        case .zhHant: return "\(n) 個操作"
        case .ja:     return "\(n) 操作"
        default:      return "\(n) action\(n == 1 ? "" : "s")"
        }
    }

    /// A compact duration, e.g. "5m" / "5分钟" / "5分".
    static func elapsed(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let (value, unit): (Int, Key2)
        if s < 60 { (value, unit) = (Int(s), .sec) }
        else if s < 3600 { (value, unit) = (Int(s / 60), .min) }
        else if s < 86400 { (value, unit) = (Int(s / 3600), .hour) }
        else { (value, unit) = (Int(s / 86400), .day) }
        return "\(value)\(unitString(unit))"
    }

    static func ago(_ seconds: Double) -> String {
        let s = max(0, seconds)
        if s < 5 { return justNow }
        let base = elapsed(s)
        switch resolved {
        case .en: return base + " ago"
        default:  return base + "前"
        }
    }

    private static var justNow: String {
        switch resolved {
        case .zhHans: return "刚刚"
        case .zhHant: return "剛剛"
        case .ja:     return "たった今"
        default:      return "just now"
        }
    }

    private enum Key2 { case sec, min, hour, day }
    private static func unitString(_ u: Key2) -> String {
        switch resolved {
        case .zhHans: return [.sec: "秒", .min: "分钟", .hour: "小时", .day: "天"][u]!
        case .zhHant: return [.sec: "秒", .min: "分鐘", .hour: "小時", .day: "天"][u]!
        case .ja:     return [.sec: "秒", .min: "分", .hour: "時間", .day: "日"][u]!
        default:      return [.sec: "s", .min: "m", .hour: "h", .day: "d"][u]!
        }
    }

    // MARK: Tables

    private static let table: [AppLanguage: [Key: String]] = [
        .en: [
            .idle: "idle", .working: "working…", .needsYou: "needs you",
            .ready: "ready for review", .failed: "something failed",
            .readyForReview: "ready for review",
            .noSessions: "No active sessions",
            .noSessionsHint: "Start Claude Code and it'll appear here",
            .noActiveSessions: "no active sessions",
            .focusTerminal: "Focus terminal", .revealInFinder: "Reveal in Finder",
            .copyId: "Copy session id", .recent: "Recent:",
            .showSessions: "Show Sessions…", .collapseCards: "Collapse the session cards",
            .pet: "Pet", .refreshPets: "Refresh Pets…", .position: "Position",
            .snapToCorner: "Snap to Corner", .previewState: "Preview State",
            .clearPreview: "Clear Preview", .quit: "Quit CodePet",
            .language: "Language", .langSystem: "System",
            .cornerBR: "Bottom Right", .cornerBL: "Bottom Left",
            .cornerTR: "Top Right", .cornerTL: "Top Left",
            .installedPets: "Installed pets", .petdexPets: "Petdex gallery (~/.petdex)",
            .codexPets: "Codex pets (~/.codex)",
            .builtinForms: "Built-in forms",
            .installFromPetdex: "Install from Petdex", .petdexLoading: "Loading gallery…",
            .petdexBrowseWeb: "Browse full gallery…",
            .petdexInstalledTitle: "Pet installed", .petdexInstallFailedTitle: "Install failed",
            .ok: "OK",
            .petdexInstallByName: "Install by name…",
            .petdexEnterName: "Enter a pet name from petdex.crafter.run (e.g. boba, naiwa, doraemon):",
            .petdexInstalling: "Installing…", .cancel: "Cancel", .install: "Install",
            .replyPlaceholder: "Reply…",
            .replyPermTitle: "Automation permission needed",
            .replyPermBody: "Allow CodePet to control your terminal in System Settings → Privacy & Security → Automation, then send again.",
            .openSettings: "Open Settings",
        ],
        .zhHans: [
            .idle: "空闲", .working: "工作中…", .needsYou: "需要你",
            .ready: "待审查", .failed: "出错了", .readyForReview: "待审查",
            .noSessions: "暂无活动会话",
            .noSessionsHint: "启动 Claude Code 后会显示在这里",
            .noActiveSessions: "暂无活动会话",
            .focusTerminal: "切到终端", .revealInFinder: "在访达中显示",
            .copyId: "复制会话 ID", .recent: "最近：",
            .showSessions: "显示会话…", .collapseCards: "收起会话卡片",
            .pet: "宠物", .refreshPets: "刷新宠物…", .position: "位置",
            .snapToCorner: "吸附到角落", .previewState: "预览状态",
            .clearPreview: "清除预览", .quit: "退出 CodePet",
            .language: "语言", .langSystem: "跟随系统",
            .cornerBR: "右下角", .cornerBL: "左下角",
            .cornerTR: "右上角", .cornerTL: "左上角",
            .installedPets: "已安装宠物", .petdexPets: "Petdex 图库 (~/.petdex)",
            .codexPets: "Codex 宠物 (~/.codex)",
            .builtinForms: "内置形象",
            .installFromPetdex: "从 Petdex 安装", .petdexLoading: "正在加载图库…",
            .petdexBrowseWeb: "浏览完整图库…",
            .petdexInstalledTitle: "宠物已安装", .petdexInstallFailedTitle: "安装失败",
            .ok: "好",
            .petdexInstallByName: "输入名称安装…",
            .petdexEnterName: "输入 petdex.crafter.run 上的宠物名称(如 boba、naiwa、doraemon):",
            .petdexInstalling: "正在安装…", .cancel: "取消", .install: "安装",
            .replyPlaceholder: "回复…",
            .replyPermTitle: "需要自动化权限",
            .replyPermBody: "请在 系统设置 → 隐私与安全性 → 自动化 里勾选允许 CodePet 控制你的终端，然后重新发送。",
            .openSettings: "打开设置",
        ],
        .zhHant: [
            .idle: "空閒", .working: "工作中…", .needsYou: "需要你",
            .ready: "待審查", .failed: "出錯了", .readyForReview: "待審查",
            .noSessions: "暫無活動工作階段",
            .noSessionsHint: "啟動 Claude Code 後會顯示在這裡",
            .noActiveSessions: "暫無活動工作階段",
            .focusTerminal: "切到終端", .revealInFinder: "在 Finder 中顯示",
            .copyId: "複製工作階段 ID", .recent: "最近：",
            .showSessions: "顯示工作階段…", .collapseCards: "收起工作階段卡片",
            .pet: "寵物", .refreshPets: "重新整理寵物…", .position: "位置",
            .snapToCorner: "吸附到角落", .previewState: "預覽狀態",
            .clearPreview: "清除預覽", .quit: "結束 CodePet",
            .language: "語言", .langSystem: "跟隨系統",
            .cornerBR: "右下角", .cornerBL: "左下角",
            .cornerTR: "右上角", .cornerTL: "左上角",
            .installedPets: "已安裝寵物", .petdexPets: "Petdex 圖庫 (~/.petdex)",
            .codexPets: "Codex 寵物 (~/.codex)",
            .builtinForms: "內建形象",
            .installFromPetdex: "從 Petdex 安裝", .petdexLoading: "正在載入圖庫…",
            .petdexBrowseWeb: "瀏覽完整圖庫…",
            .petdexInstalledTitle: "寵物已安裝", .petdexInstallFailedTitle: "安裝失敗",
            .ok: "好",
            .petdexInstallByName: "輸入名稱安裝…",
            .petdexEnterName: "輸入 petdex.crafter.run 上的寵物名稱(如 boba、naiwa、doraemon):",
            .petdexInstalling: "正在安裝…", .cancel: "取消", .install: "安裝",
            .replyPlaceholder: "回覆…",
            .replyPermTitle: "需要自動化權限",
            .replyPermBody: "請在 系統設定 → 隱私權與安全性 → 自動化 裡允許 CodePet 控制你的終端機，然後重新傳送。",
            .openSettings: "打開設定",
        ],
        .ja: [
            .idle: "待機中", .working: "作業中…", .needsYou: "確認待ち",
            .ready: "レビュー待ち", .failed: "エラー発生", .readyForReview: "レビュー待ち",
            .noSessions: "アクティブなセッションなし",
            .noSessionsHint: "Claude Code を開始すると表示されます",
            .noActiveSessions: "アクティブなセッションなし",
            .focusTerminal: "ターミナルを前面に", .revealInFinder: "Finder で表示",
            .copyId: "セッション ID をコピー", .recent: "最近：",
            .showSessions: "セッションを表示…", .collapseCards: "セッションカードを閉じる",
            .pet: "ペット", .refreshPets: "ペットを更新…", .position: "位置",
            .snapToCorner: "隅にスナップ", .previewState: "状態プレビュー",
            .clearPreview: "プレビューを消去", .quit: "CodePet を終了",
            .language: "言語", .langSystem: "システムに従う",
            .cornerBR: "右下", .cornerBL: "左下",
            .cornerTR: "右上", .cornerTL: "左上",
            .installedPets: "インストール済みペット", .petdexPets: "Petdex ギャラリー (~/.petdex)",
            .codexPets: "Codex ペット (~/.codex)",
            .builtinForms: "内蔵フォーム",
            .installFromPetdex: "Petdex から追加", .petdexLoading: "ギャラリーを読み込み中…",
            .petdexBrowseWeb: "ギャラリー全体を見る…",
            .petdexInstalledTitle: "ペットを追加しました", .petdexInstallFailedTitle: "追加に失敗しました",
            .ok: "OK",
            .petdexInstallByName: "名前で追加…",
            .petdexEnterName: "petdex.crafter.run のペット名を入力(例: boba、naiwa、doraemon):",
            .petdexInstalling: "追加中…", .cancel: "キャンセル", .install: "追加",
            .replyPlaceholder: "返信…",
            .replyPermTitle: "オートメーション権限が必要",
            .replyPermBody: "システム設定 → プライバシーとセキュリティ → オートメーション で CodePet にターミナルの操作を許可してから、もう一度送信してください。",
            .openSettings: "設定を開く",
        ],
    ]
}
