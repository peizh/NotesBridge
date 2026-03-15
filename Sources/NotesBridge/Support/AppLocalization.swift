import Foundation

struct AppLocalization: Sendable {
    let language: AppLanguage

    var locale: Locale {
        switch resolvedLanguageCode {
        case "zh-Hans":
            Locale(identifier: "zh-Hans")
        case "fr":
            Locale(identifier: "fr")
        default:
            language == .system ? .current : Locale(identifier: "en")
        }
    }

    var resolvedLanguageCode: String {
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.hasPrefix("zh") { return "zh-Hans" }
            if preferred.hasPrefix("fr") { return "fr" }
            return "en"
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .french:
            return "fr"
        }
    }

    func text(_ key: String) -> String {
        Self.translations[resolvedLanguageCode]?[key] ?? key
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    func text(_ key: String, arguments: [CVarArg]) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    func languageDisplayName(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return text("System")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .french:
            return "Français"
        }
    }

    private static let translations: [String: [String: String]] = [
        "zh-Hans": [
            "Ready": "就绪",
            "System": "跟随系统",
            "NotesBridge Settings": "NotesBridge 设置",
            "Distribution": "发行方式",
            "Build": "构建",
            "Language": "语言",
            "Direct Download": "直接下载版",
            "Mac App Store": "Mac App Store",
            "This build can enhance Apple Notes inline through Accessibility.": "此版本可通过辅助功能为 Apple Notes 提供行内增强。",
            "This build only exposes settings, sync, and integration features.": "此版本仅提供设置、同步和集成功能。",
            "Permissions": "权限",
            "Launch Mode": "启动方式",
            "Bundled App": "打包应用",
            "Command-line build": "命令行构建",
            "Accessibility": "辅助功能",
            "Granted": "已授予",
            "Required": "需要授权",
            "Request Accessibility Permission": "请求辅助功能权限",
            "Open Accessibility Settings": "打开辅助功能设置",
            "Reveal NotesBridge App in Finder": "在 Finder 中显示 NotesBridge",
            "Relaunch as Bundled App": "以打包应用方式重新启动",
            "If NotesBridge is already checked in Accessibility but still shows Required here, remove it and add the current NotesBridge.app bundle again.": "如果系统中已勾选 NotesBridge，但这里仍显示需要授权，请移除后重新添加当前的 NotesBridge.app。",
            "Inline Enhancements": "行内增强",
            "Enable inline Apple Notes enhancements": "启用 Apple Notes 行内增强",
            "Show formatting bar for selected text": "为选中文本显示格式栏",
            "Enable markdown and list triggers at line start": "启用行首 Markdown 和列表触发器",
            "Enable slash commands": "启用斜杠命令",
            "Use / to open slash suggestions, or type an exact slash command and press Space to apply it inline.": "输入 / 打开斜杠建议，或输入完整斜杠命令后按空格直接应用。",
            "Keyboard slash navigation is unavailable in the current build. Use the mouse, or type an exact slash command and press Space.": "当前构建不支持键盘导航斜杠菜单。请使用鼠标，或输入完整斜杠命令后按空格。",
            "Inline enhancements support the formatting bar, markdown/list triggers, and slash commands.": "行内增强支持格式栏、Markdown/列表触发器和斜杠命令。",
            "Obsidian": "Obsidian",
            "Vault": "库",
            "Not configured": "未配置",
            "Choose Vault": "选择库",
            "Reveal in Finder": "在 Finder 中显示",
            "Export Folder Name": "导出目录名",
            "Attachments": "附件",
            "Use Obsidian attachment folder from .obsidian/app.json": "使用 .obsidian/app.json 中的附件目录",
            "Default Attachment Folder": "默认附件目录",
            "Resolved Folder": "实际目录",
            "Apple Notes attachments are stored in one shared root and keep the exported folder hierarchy underneath it.": "Apple Notes 附件存放在统一根目录下，并保留导出的层级结构。",
            "Apple Notes Data": "Apple Notes 数据",
            "Folder": "文件夹",
            "Access": "访问状态",
            "Accessible": "可访问",
            "Limited": "受限",
            "Invalid": "无效",
            "Choose Apple Notes Data Folder": "选择 Apple Notes 数据目录",
            "Choose the macOS Apple Notes container folder named group.com.apple.notes so NotesBridge can read NoteStore.sqlite and native attachments.": "请选择名为 group.com.apple.notes 的 macOS Apple Notes 容器目录，以便 NotesBridge 读取 NoteStore.sqlite 和原生附件。",
            "Indexing & Sync": "索引与同步",
            "Known Folders": "已知文件夹",
            "Indexed Notes": "已索引笔记",
            "Last Full Sync": "上次完整同步",
            "Never": "从未",
            "Refresh Folder Index": "刷新文件夹索引",
            "Syncing...": "同步中...",
            "Sync All Notes to Obsidian": "同步全部笔记到 Obsidian",
            "Current Status": "当前状态",
            "Current selection: %@": "当前选择：%@",
            "Slash commands: %@": "斜杠命令：%@",
            "Slash diagnostics": "斜杠诊断",
            "Title": "标题",
            "Heading": "标题 2",
            "Subheading": "标题 3",
            "Body": "正文",
            "Monostyled": "等宽文本",
            "Checklist": "清单",
            "Bulleted List": "项目符号列表",
            "Dashed List": "短横线列表",
            "Numbered List": "编号列表",
            "Block Quote": "引用块",
            "Table": "表格",
            "Preparing sync progress...": "正在准备同步进度...",
            "Inline": "行内增强",
            "Slash": "斜杠",
            "Selection": "选择",
            "Sync": "同步",
            "Last full sync: %@": "上次完整同步：%@",
            "Open Apple Notes": "打开 Apple Notes",
            "Syncing Notes...": "正在同步笔记...",
            "Open Settings": "打开设置",
            "Quit NotesBridge": "退出 NotesBridge",
            "OK": "好",
            "No text selected": "未选择文本",
            "Selected text ready": "选中文本已就绪",
            "Slash commands are unavailable in the Mac App Store build.": "Mac App Store 版本不提供斜杠命令。",
            "Slash commands are disabled with inline enhancements.": "行内增强关闭时，斜杠命令不可用。",
            "Slash commands are turned off in Settings.": "设置中已关闭斜杠命令。",
            "Accessibility permission is required for slash commands.": "斜杠命令需要辅助功能权限。",
            "Accessibility permission is required for slash commands. If NotesBridge is already checked in Accessibility, remove and re-add the current app bundle once.": "斜杠命令需要辅助功能权限。如果系统中已勾选 NotesBridge，请移除后重新添加当前应用。",
            "Bring Apple Notes to the front to use slash commands.": "请将 Apple Notes 切到前台以使用斜杠命令。",
            "Focus the Apple Notes editor to use slash commands.": "请聚焦 Apple Notes 编辑器以使用斜杠命令。",
            "Slash commands are active. Use the mouse, or complete an exact slash command and press Space.": "斜杠命令已启用。请使用鼠标，或输入完整斜杠命令后按空格。",
            "Type / for suggestions, or complete a slash command and press Space.": "输入 / 查看建议，或输入完整斜杠命令后按空格。",
            "Inline enhancements are disabled in the Mac App Store build.": "Mac App Store 版本已禁用行内增强。",
            "Grant Accessibility to NotesBridge. If it is already checked, remove and re-add the current app bundle once.": "请为 NotesBridge 授予辅助功能权限。如果系统中已勾选，请移除后重新添加当前应用。",
            "Accessibility permission is required for Notes enhancements.": "Notes 增强功能需要辅助功能权限。",
            "Inline enhancements are disabled in Settings.": "设置中已关闭行内增强。",
            "Bring Apple Notes to the front to enable formatting tools.": "请将 Apple Notes 切到前台以启用格式工具。",
            "Focus the Apple Notes editor to use inline formatting tools.": "请聚焦 Apple Notes 编辑器以使用行内格式工具。",
            "Inline enhancements are active in Apple Notes.": "Apple Notes 行内增强已启用。",
            "Requesting Accessibility permission for NotesBridge...": "正在为 NotesBridge 请求辅助功能权限...",
            "Accessibility is already granted for NotesBridge.": "NotesBridge 已获得辅助功能权限。",
            "Open Privacy & Security > Accessibility and enable NotesBridge. If it is missing, add ~/Library/Application Support/NotesBridge/NotesBridge.app manually.": "请打开 隐私与安全性 > 辅助功能 并启用 NotesBridge。如果列表中没有，请手动添加 ~/Library/Application Support/NotesBridge/NotesBridge.app。",
            "Open Privacy & Security > Accessibility and enable NotesBridge.": "请打开 隐私与安全性 > 辅助功能 并启用 NotesBridge。",
            "Requesting Input Monitoring permission for slash menu keyboard navigation...": "正在为斜杠菜单键盘导航请求输入监控权限...",
            "Input Monitoring is already granted for NotesBridge.": "NotesBridge 已获得输入监控权限。",
            "Open Privacy & Security > Input Monitoring to enable slash menu keyboard navigation for NotesBridge.": "请打开 隐私与安全性 > 输入监控，为 NotesBridge 启用斜杠菜单键盘导航。",
            "Relaunching NotesBridge as a bundled app so macOS can grant Input Monitoring...": "正在以打包应用方式重新启动 NotesBridge，以便 macOS 授予输入监控权限...",
            "Relaunching NotesBridge as a bundled app...": "正在以打包应用方式重新启动 NotesBridge...",
            "Failed to relaunch NotesBridge as a bundled app.": "无法以打包应用方式重新启动 NotesBridge。",
            "Choose an Obsidian vault": "选择一个 Obsidian 库",
            "Use Vault": "使用此库",
            "Obsidian vault set to %@.": "Obsidian 库已设置为 %@。",
            "Apple Notes data folder set to %@.": "Apple Notes 数据目录已设置为 %@。",
            "Failed to access Apple Notes data folder.": "无法访问 Apple Notes 数据目录。",
            "Sync cancelled. Choose the Apple Notes data folder to continue.": "同步已取消。请选择 Apple Notes 数据目录以继续。",
            "Refreshing Apple Notes folders...": "正在刷新 Apple Notes 文件夹...",
            "Loaded %lld Apple Notes folders.": "已加载 %lld 个 Apple Notes 文件夹。",
            "Failed to refresh Apple Notes folders.": "无法刷新 Apple Notes 文件夹。",
            "Choose an Obsidian vault before syncing.": "同步前请先选择一个 Obsidian 库。",
            "Syncing Apple Notes to Obsidian...": "正在将 Apple Notes 同步到 Obsidian...",
            "Synced %lld note(s) across %lld folder(s).": "已同步 %lld 条笔记，涉及 %lld 个文件夹。",
            "Failed to sync Apple Notes to Obsidian.": "无法将 Apple Notes 同步到 Obsidian。",
            "Failed to save app settings.": "无法保存应用设置。",
            "%d%% • %d/%d notes • %d/%d folders": "%d%% • %d/%d 条笔记 • %d/%d 个文件夹",
            "Current folder: %@": "当前文件夹：%@"
        ],
        "fr": [
            "Ready": "Prêt",
            "System": "Système",
            "NotesBridge Settings": "Réglages NotesBridge",
            "Distribution": "Distribution",
            "Build": "Build",
            "Language": "Langue",
            "Direct Download": "Téléchargement direct",
            "Mac App Store": "Mac App Store",
            "This build can enhance Apple Notes inline through Accessibility.": "Cette version peut enrichir Apple Notes en ligne via Accessibilité.",
            "This build only exposes settings, sync, and integration features.": "Cette version n'expose que les réglages, la synchronisation et les intégrations.",
            "Permissions": "Autorisations",
            "Launch Mode": "Mode de lancement",
            "Bundled App": "App empaquetée",
            "Command-line build": "Build en ligne de commande",
            "Accessibility": "Accessibilité",
            "Granted": "Accordé",
            "Required": "Requis",
            "Request Accessibility Permission": "Demander l'autorisation Accessibilité",
            "Open Accessibility Settings": "Ouvrir les réglages Accessibilité",
            "Reveal NotesBridge App in Finder": "Afficher NotesBridge dans le Finder",
            "Relaunch as Bundled App": "Relancer comme app empaquetée",
            "Inline Enhancements": "Améliorations en ligne",
            "Enable inline Apple Notes enhancements": "Activer les améliorations Apple Notes en ligne",
            "Show formatting bar for selected text": "Afficher la barre de formatage pour le texte sélectionné",
            "Enable markdown and list triggers at line start": "Activer les déclencheurs Markdown et listes en début de ligne",
            "Enable slash commands": "Activer les commandes slash",
            "Obsidian": "Obsidian",
            "Vault": "Vault",
            "Not configured": "Non configuré",
            "Choose Vault": "Choisir un vault",
            "Reveal in Finder": "Afficher dans le Finder",
            "Export Folder Name": "Nom du dossier d'export",
            "Attachments": "Pièces jointes",
            "Default Attachment Folder": "Dossier des pièces jointes par défaut",
            "Resolved Folder": "Dossier résolu",
            "Apple Notes Data": "Données Apple Notes",
            "Folder": "Dossier",
            "Access": "Accès",
            "Accessible": "Accessible",
            "Limited": "Limité",
            "Invalid": "Invalide",
            "Choose Apple Notes Data Folder": "Choisir le dossier de données Apple Notes",
            "Indexing & Sync": "Indexation et synchronisation",
            "Known Folders": "Dossiers connus",
            "Indexed Notes": "Notes indexées",
            "Last Full Sync": "Dernière synchro complète",
            "Never": "Jamais",
            "Refresh Folder Index": "Rafraîchir l'index des dossiers",
            "Syncing...": "Synchronisation...",
            "Sync All Notes to Obsidian": "Synchroniser toutes les notes vers Obsidian",
            "Current Status": "État actuel",
            "Current selection: %@": "Sélection actuelle : %@",
            "Slash commands: %@": "Commandes slash : %@",
            "Slash diagnostics": "Diagnostic slash",
            "Title": "Titre",
            "Heading": "Titre 2",
            "Subheading": "Titre 3",
            "Body": "Corps",
            "Monostyled": "Monostyle",
            "Checklist": "Checklist",
            "Bulleted List": "Liste à puces",
            "Dashed List": "Liste à tirets",
            "Numbered List": "Liste numérotée",
            "Block Quote": "Bloc de citation",
            "Table": "Tableau",
            "Preparing sync progress...": "Préparation de la progression...",
            "Inline": "Inline",
            "Slash": "Slash",
            "Selection": "Sélection",
            "Sync": "Sync",
            "Last full sync: %@": "Dernière synchro complète : %@",
            "Open Apple Notes": "Ouvrir Apple Notes",
            "Syncing Notes...": "Synchronisation des notes...",
            "Open Settings": "Ouvrir les réglages",
            "Quit NotesBridge": "Quitter NotesBridge",
            "OK": "OK",
            "No text selected": "Aucun texte sélectionné",
            "Selected text ready": "Texte sélectionné prêt",
            "Refreshing Apple Notes folders...": "Actualisation des dossiers Apple Notes...",
            "Loaded %lld Apple Notes folders.": "%lld dossiers Apple Notes chargés.",
            "Failed to refresh Apple Notes folders.": "Échec de l'actualisation des dossiers Apple Notes.",
            "Choose an Obsidian vault before syncing.": "Choisissez un vault Obsidian avant la synchronisation.",
            "Syncing Apple Notes to Obsidian...": "Synchronisation d'Apple Notes vers Obsidian...",
            "Synced %lld note(s) across %lld folder(s).": "%lld note(s) synchronisée(s) dans %lld dossier(s).",
            "Failed to sync Apple Notes to Obsidian.": "Échec de la synchronisation d'Apple Notes vers Obsidian.",
            "%d%% • %d/%d notes • %d/%d folders": "%d%% • %d/%d notes • %d/%d dossiers",
            "Current folder: %@": "Dossier actuel : %@"
        ]
    ]
}
