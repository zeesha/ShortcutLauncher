@{
    AppTitle = "Shortcut Launcher"
    AppListening = "Shortcut Launcher - listening (F4 to stop)"
    AppFatalError = "Shortcut Launcher - fatal error"
    
    SettingsTitle = "Shortcut Launcher - Settings"
    HelpTitle = "Shortcut Launcher - Help"
    
    StatusIndexed = "{0} shortcuts indexed"
    StatusResults = "{0} result(s) for '{1}'"
    StatusVoiceUnavailable = "Voice unavailable - keyboard only"
    StatusRefreshing = "Refreshing..."
    StatusFailed = "Failed: {0}"
    
    BtnOK = "OK"
    BtnCancel = "Cancel"
    HelpShortcuts = "Keyboard shortcuts"
    HelpSearch = "Search"
    HelpSearchDesc = 'Matching is case-insensitive by default. User can toggle to Case, Whole Word, or Regex matching. The primary name is ranked above any optional comment.'
    HelpLaunch = "Launch"
    HelpLaunchDesc = "Classic .lnk, UWP apps, registered App Paths, System32 tools`n  (.msc / .cpl) and Windows Settings pages (ms-settings:) are all`n  launchable from the same list."
    HelpFiles = "Files"
    HelpLog = "Log:"
    HelpConfig = "Config:"
    
    # Help Dialog Keys
    KeyType = "type"
    ActType = "filter shortcuts"
    KeyUpDown = "Up / Down"
    ActUpDown = "move selection in the list"
    KeyEnter = "Enter"
    ActEnter = "launch the selected shortcut"
    KeyEsc = "Esc"
    ActEsc = "clear the prompt"
    KeyF1 = "F1"
    ActF1 = "open this Help"
    KeyF2 = "F2"
    ActF2 = "open Settings"
    KeyF3 = "F3"
    ActF3 = "toggle desktop icons"
    KeyF4 = "F4"
    ActF4 = "toggle voice input"
    KeyF5 = "F5"
    ActF5 = "refresh shortcut index"
    KeyAltF4 = "Alt+F4"
    ActAltF4 = "close the window"

    # Settings Dialog
    SecCollections = "Collections"
    ColDesktop = "Desktop shortcuts"
    ColTaskbar = "Taskbar pinned shortcuts"
    ColStartLnk = "Start-menu .lnk files"
    ColStartApps = "Get-StartApps (UWP / classic)"
    ColAppPaths = "App Paths (registry)"
    ColTools = "System32 tools (.msc / .cpl)"
    ColSettings = "Settings pages (ms-settings:)"
    ColDocuments = "Documents (.docx, .pdf, .txt, etc.)"
    ColMultimedia = "Multimedia (.mp3, .mp4, .jpg, etc.)"
    
    SecSearch = "Search"
    OptAltNames = "Comments and Aliases"
    
    SecVoice = "Voice"
    VoiceLang = "Recognition language:"
    VoiceNoRecognizers = "(no recognizers installed)"
    
    SecAppearance = "Appearance"
    ThemeLabel = "Theme:"
    ThemeSystem = "System"
    ThemeLight = "Light"
    ThemeDark = "Dark"
    OpacityLabel = "Opacity:"
    UILangLabel = "UI Language:"
    UILangSystem = "System Default"
    UILangRestart = "UI language changed. Please restart Shortcut Launcher for the changes to take effect."
    
    TooltipSettings = "Settings"
    TooltipCase = "Match Case"
    TooltipWord = "Match Whole Word"
    TooltipRegex = "Use Regular Expression"
    
    # Settings Pages (Name is displayed in the list)
    SettingsPages = @(
        @{ Name = 'Settings Home'; Uri = 'ms-settings:' }
        @{ Name = 'Settings Display'; Uri = 'ms-settings:display' }
        @{ Name = 'Settings Sound'; Uri = 'ms-settings:sound' }
        @{ Name = 'Settings Notifications'; Uri = 'ms-settings:notifications' }
        @{ Name = 'Settings Power Sleep'; Uri = 'ms-settings:powersleep' }
        @{ Name = 'Settings Storage'; Uri = 'ms-settings:storagesense' }
        @{ Name = 'Settings Bluetooth Devices'; Uri = 'ms-settings:bluetooth' }
        @{ Name = 'Settings Printers Scanners'; Uri = 'ms-settings:printers' }
        @{ Name = 'Settings Network Internet'; Uri = 'ms-settings:network' }
        @{ Name = 'Settings Personalization'; Uri = 'ms-settings:personalization' }
        @{ Name = 'Settings Apps Features'; Uri = 'ms-settings:appsfeatures' }
        @{ Name = 'Settings Accounts'; Uri = 'ms-settings:yourinfo' }
        @{ Name = 'Settings Time Language'; Uri = 'ms-settings:dateandtime' }
        @{ Name = 'Settings Gaming'; Uri = 'ms-settings:gaming-gamebar' }
        @{ Name = 'Settings Ease of Access'; Uri = 'ms-settings:easeofaccess' }
        @{ Name = 'Settings Privacy'; Uri = 'ms-settings:privacy' }
        @{ Name = 'Settings Update Security'; Uri = 'ms-settings:windowsupdate' }
    )
}