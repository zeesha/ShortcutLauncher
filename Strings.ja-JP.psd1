@{
    AppTitle = "ショートカットランチャー"
    AppListening = "ショートカットランチャー - 音声入力中 (F4で停止)"
    AppFatalError = "ショートカットランチャー - 致命的なエラー"
    
    SettingsTitle = "ショートカットランチャー - 設定"
    HelpTitle = "ショートカットランチャー - ヘルプ"
    
    StatusIndexed = "{0} 個のショートカットが登録されています"
    StatusResults = "'{1}' の検索結果: {0} 件"
    StatusVoiceUnavailable = "音声入力は利用できません - キーボード操作のみ"
    StatusRefreshing = "更新中..."
    StatusFailed = "失敗: {0}"
    
    BtnOK = "OK"
    BtnCancel = "キャンセル"
    HelpShortcuts = "キーボードショートカット"
    HelpSearch = "検索"
    HelpSearchDesc = 'デフォルトでは大文字と小文字を区別しません。大文字と小文字の区別、単語単位の検索、または正規表現の使用を切り替えることができます。主な名前は、オプションのコメントよりも優先されます。'
    HelpLaunch = "起動"
    HelpLaunchDesc = "従来の .lnk、UWP アプリ、登録済みのアプリパス、System32 ツール`n  (.msc / .cpl)、および Windows 設定ページ (ms-settings:) は、`n  すべてこのリストから起動できます。"
    HelpFiles = "ファイル"
    HelpLog = "ログ:"
    HelpConfig = "設定:"
    
    # Help Dialog Keys
    KeyType = "入力"
    ActType = "ショートカットを絞り込む"
    KeyUpDown = "上 / 下"
    ActUpDown = "リスト内の選択項目を移動"
    KeyEnter = "Enter"
    ActEnter = "選択したショートカットを起動"
    KeyEsc = "Esc"
    ActEsc = "入力をクリア"
    KeyF1 = "F1"
    ActF1 = "このヘルプを開く"
    KeyF2 = "F2"
    ActF2 = "設定を開く"
    KeyF3 = "F3"
    ActF3 = "デスクトップアイコンの表示/非表示"
    KeyF4 = "F4"
    ActF4 = "音声入力を切り替え"
    KeyF5 = "F5"
    ActF5 = "インデックスを更新"
    KeyAltF4 = "Alt+F4"
    ActAltF4 = "ウィンドウを閉じる"

    # Settings Dialog
    SecCollections = "コレクション"
    ColDesktop = "デスクトップのショートカット"
    ColTaskbar = "タスクバーにピン留めされたショートカット"
    ColStartLnk = "スタートメニューの .lnk ファイル"
    ColStartApps = "Get-StartApps (UWP / クラシック)"
    ColAppPaths = "アプリパス (レジストリ)"
    ColTools = "System32 ツール (.msc / .cpl)"
    ColSettings = "設定ページ (ms-settings:)"
    ColDocuments = "ドキュメント (.docx, .pdf, .txt など)"
    ColMultimedia = "マルチメディア (.mp3, .mp4, .jpg など)"
    
    SecSearch = "検索"
    OptAltNames = "説明と別名"
    
    SecVoice = "音声"
    VoiceLang = "認識言語:"
    VoiceNoRecognizers = "(認識エンジンがインストールされていません)"
    
    SecAppearance = "外観"
    ThemeLabel = "テーマ:"
    ThemeSystem = "システム"
    ThemeLight = "ライト"
    ThemeDark = "ダーク"
    OpacityLabel = "不透明度:"
    UILangLabel = "UI言語:"
    UILangSystem = "システムデフォルト"
    UILangRestart = "UI言語が変更されました。変更を反映するにはショートカットランチャーを再起動してください。"

    TooltipSettings = "設定"
    TooltipCase = "大文字と小文字を区別"
    TooltipWord = "単語単位で検索"
    TooltipRegex = "正規表現を使用"
    
    # Settings Pages
    SettingsPages = @(
        @{ Name = '設定 - ホーム'; Uri = 'ms-settings:' }
        @{ Name = '設定 - ディスプレイ'; Uri = 'ms-settings:display' }
        @{ Name = '設定 - サウンド'; Uri = 'ms-settings:sound' }
        @{ Name = '設定 - 通知とアクション'; Uri = 'ms-settings:notifications' }
        @{ Name = '設定 - 電源とスリープ'; Uri = 'ms-settings:powersleep' }
        @{ Name = '設定 - ストレージ'; Uri = 'ms-settings:storagesense' }
        @{ Name = '設定 - Bluetooth とデバイス'; Uri = 'ms-settings:bluetooth' }
        @{ Name = '設定 - プリンターとスキャナー'; Uri = 'ms-settings:printers' }
        @{ Name = '設定 - ネットワークとインターネット'; Uri = 'ms-settings:network' }
        @{ Name = '設定 - 個人用設定'; Uri = 'ms-settings:personalization' }
        @{ Name = '設定 - アプリ'; Uri = 'ms-settings:appsfeatures' }
        @{ Name = '設定 - アカウント'; Uri = 'ms-settings:yourinfo' }
        @{ Name = '設定 - 時刻と言語'; Uri = 'ms-settings:dateandtime' }
        @{ Name = '設定 - ゲーム'; Uri = 'ms-settings:gaming-gamebar' }
        @{ Name = '設定 - アクセシビリティ'; Uri = 'ms-settings:easeofaccess' }
        @{ Name = '設定 - プライバシー'; Uri = 'ms-settings:privacy' }
        @{ Name = '設定 - 更新とセキュリティ'; Uri = 'ms-settings:windowsupdate' }
    )
}