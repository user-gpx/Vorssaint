// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderMenuStrings {
    let sectionTitle: String
    let enableLabel: String
    let showIconsLabel: String
    let itemsLabel: String
    let extensionHint: String
    let copy: String
    let cut: String
    let paste: String
    let newTerminal: String
    let newFile: String

    func title(for action: FinderMenuAction) -> String {
        switch action {
        case .copy: return copy
        case .cut: return cut
        case .paste: return paste
        case .newTerminal: return newTerminal
        case .newFile: return newFile
        default: return action.defaultTitle
        }
    }
}

extension FeatureStrings {
    static func finderMenu(_ language: AppLanguage) -> FinderMenuStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension FinderMenuStrings {
    static let enUS = FinderMenuStrings(
        sectionTitle: "Finder Menu",
        enableLabel: "Show Vorssaint in Finder’s context menu",
        showIconsLabel: "Show icons",
        itemsLabel: "Menu items",
        extensionHint: "The Finder extension must also be enabled in System Settings › General › Login Items & Extensions › File Providers.",
        copy: "Copy",
        cut: "Cut",
        paste: "Paste",
        newTerminal: "New Terminal",
        newFile: "New File"
    )

    static let ptBR = FinderMenuStrings(
        sectionTitle: "Menu do Finder",
        enableLabel: "Mostrar o Vorssaint no menu de contexto do Finder",
        showIconsLabel: "Mostrar ícones",
        itemsLabel: "Itens do menu",
        extensionHint: "A extensão do Finder também precisa estar ativada em Ajustes do Sistema › Geral › Itens de Login e Extensões › Provedores de Arquivos.",
        copy: "Copiar",
        cut: "Recortar",
        paste: "Colar",
        newTerminal: "Novo Terminal",
        newFile: "Novo Arquivo"
    )

    static let tr = FinderMenuStrings(
        sectionTitle: "Finder Menüsü",
        enableLabel: "Vorssaint’i Finder bağlam menüsünde göster",
        showIconsLabel: "Simgeleri göster",
        itemsLabel: "Menü öğeleri",
        extensionHint: "Finder uzantısı ayrıca Sistem Ayarları › Genel › Giriş Öğeleri ve Uzantılar › Dosya Sağlayıcıları bölümünde etkinleştirilmelidir.",
        copy: "Kopyala",
        cut: "Kes",
        paste: "Yapıştır",
        newTerminal: "Yeni Terminal",
        newFile: "Yeni Dosya"
    )

    static let ru = FinderMenuStrings(
        sectionTitle: "Меню Finder",
        enableLabel: "Показывать Vorssaint в контекстном меню Finder",
        showIconsLabel: "Показывать значки",
        itemsLabel: "Пункты меню",
        extensionHint: "Расширение Finder также нужно включить в «Системных настройках» › «Основные» › «Объекты входа и расширения» › «Поставщики файлов».",
        copy: "Скопировать",
        cut: "Вырезать",
        paste: "Вставить",
        newTerminal: "Новый терминал",
        newFile: "Новый файл"
    )

    static let es = FinderMenuStrings(
        sectionTitle: "Menú del Finder",
        enableLabel: "Mostrar Vorssaint en el menú contextual del Finder",
        showIconsLabel: "Mostrar iconos",
        itemsLabel: "Elementos del menú",
        extensionHint: "También debes activar la extensión del Finder en Ajustes del Sistema › General › Ítems de inicio y extensiones › Proveedores de archivos.",
        copy: "Copiar",
        cut: "Cortar",
        paste: "Pegar",
        newTerminal: "Nueva terminal",
        newFile: "Nuevo archivo"
    )

    static let sk = FinderMenuStrings(
        sectionTitle: "Menu Finderu",
        enableLabel: "Zobraziť Vorssaint v kontextovom menu Finderu",
        showIconsLabel: "Zobraziť ikony",
        itemsLabel: "Položky menu",
        extensionHint: "Rozšírenie Finderu je potrebné zapnúť aj v Nastaveniach systému › Všeobecné › Prihlasovacie položky a rozšírenia › Poskytovatelia súborov.",
        copy: "Kopírovať",
        cut: "Vystrihnúť",
        paste: "Vložiť",
        newTerminal: "Nový terminál",
        newFile: "Nový súbor"
    )

    static let de = FinderMenuStrings(
        sectionTitle: "Finder-Menü",
        enableLabel: "Vorssaint im Kontextmenü des Finders anzeigen",
        showIconsLabel: "Symbole anzeigen",
        itemsLabel: "Menüeinträge",
        extensionHint: "Die Finder-Erweiterung muss außerdem in den Systemeinstellungen › Allgemein › Anmeldeobjekte & Erweiterungen › Dateianbieter aktiviert werden.",
        copy: "Kopieren",
        cut: "Ausschneiden",
        paste: "Einsetzen",
        newTerminal: "Neues Terminal",
        newFile: "Neue Datei"
    )

    static let fr = FinderMenuStrings(
        sectionTitle: "Menu du Finder",
        enableLabel: "Afficher Vorssaint dans le menu contextuel du Finder",
        showIconsLabel: "Afficher les icônes",
        itemsLabel: "Éléments du menu",
        extensionHint: "L’extension Finder doit aussi être activée dans Réglages Système › Général › Ouverture et extensions › Fournisseurs de fichiers.",
        copy: "Copier",
        cut: "Couper",
        paste: "Coller",
        newTerminal: "Nouveau Terminal",
        newFile: "Nouveau fichier"
    )

    static let it = FinderMenuStrings(
        sectionTitle: "Menu del Finder",
        enableLabel: "Mostra Vorssaint nel menu contestuale del Finder",
        showIconsLabel: "Mostra icone",
        itemsLabel: "Voci del menu",
        extensionHint: "L’estensione Finder deve essere attivata anche in Impostazioni di Sistema › Generali › Elementi login ed estensioni › Provider di file.",
        copy: "Copia",
        cut: "Taglia",
        paste: "Incolla",
        newTerminal: "Nuovo Terminale",
        newFile: "Nuovo file"
    )

    static let ja = FinderMenuStrings(
        sectionTitle: "Finderメニュー",
        enableLabel: "FinderのコンテキストメニューにVorssaintを表示",
        showIconsLabel: "アイコンを表示",
        itemsLabel: "メニュー項目",
        extensionHint: "Finder拡張機能は「システム設定」›「一般」›「ログイン項目と拡張機能」›「ファイルプロバイダ」でも有効にする必要があります。",
        copy: "コピー",
        cut: "カット",
        paste: "ペースト",
        newTerminal: "新規ターミナル",
        newFile: "新規ファイル"
    )

    static let ko = FinderMenuStrings(
        sectionTitle: "Finder 메뉴",
        enableLabel: "Finder 상황에 맞는 메뉴에 Vorssaint 표시",
        showIconsLabel: "아이콘 표시",
        itemsLabel: "메뉴 항목",
        extensionHint: "Finder 확장 기능은 시스템 설정 › 일반 › 로그인 항목 및 확장 기능 › 파일 제공자에서도 활성화해야 합니다.",
        copy: "복사",
        cut: "잘라내기",
        paste: "붙여넣기",
        newTerminal: "새 터미널",
        newFile: "새 파일"
    )

    static let zhHans = FinderMenuStrings(
        sectionTitle: "访达菜单",
        enableLabel: "在访达右键菜单中显示 Vorssaint",
        showIconsLabel: "显示图标",
        itemsLabel: "菜单项目",
        extensionHint: "还需在系统设置 › 通用 › 登录项与扩展 › 文件提供程序中启用访达扩展。",
        copy: "复制",
        cut: "剪切",
        paste: "粘贴",
        newTerminal: "新建终端",
        newFile: "新建文件"
    )

    static let zhTW = FinderMenuStrings(
        sectionTitle: "Finder 選單",
        enableLabel: "在 Finder 右鍵選單中顯示 Vorssaint",
        showIconsLabel: "顯示圖示",
        itemsLabel: "選單項目",
        extensionHint: "還需在系統設定 › 一般 › 登入項目與擴充功能 › 檔案提供者中啟用 Finder 擴充功能。",
        copy: "複製",
        cut: "剪下",
        paste: "貼上",
        newTerminal: "新增終端機",
        newFile: "新增檔案"
    )

    static let zhHK = FinderMenuStrings(
        sectionTitle: "Finder 選單",
        enableLabel: "在 Finder 右鍵選單中顯示 Vorssaint",
        showIconsLabel: "顯示圖示",
        itemsLabel: "選單項目",
        extensionHint: "還需在系統設定 › 一般 › 登入項目與擴充功能 › 檔案提供者中啟用 Finder 擴充功能。",
        copy: "複製",
        cut: "剪下",
        paste: "貼上",
        newTerminal: "新增終端機",
        newFile: "新增檔案"
    )

    static let uk = FinderMenuStrings(
        sectionTitle: "Меню Finder",
        enableLabel: "Показувати Vorssaint у контекстному меню Finder",
        showIconsLabel: "Показувати значки",
        itemsLabel: "Пункти меню",
        extensionHint: "Розширення Finder також потрібно ввімкнути в «Системних налаштуваннях» › «Загальні» › «Об’єкти входу та розширення» › «Постачальники файлів».",
        copy: "Копіювати",
        cut: "Вирізати",
        paste: "Вставити",
        newTerminal: "Новий термінал",
        newFile: "Новий файл"
    )
}
