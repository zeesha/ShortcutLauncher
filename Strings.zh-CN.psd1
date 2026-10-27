@{
    AppTitle = "快捷启动器"
    AppListening = "快捷启动器 - 正在聆听 (按 F4 停止)"
    AppFatalError = "快捷启动器 - 致命错误"
    
    SetupTitle = "快捷启动器 - 设置"
    HelpTitle = "快捷启动器 - 帮助"
    
    StatusIndexed = "已索引 {0} 个快捷方式"
    StatusResults = "找到 {0} 个关于 '{1}' 的结果"
    StatusVoiceUnavailable = "语音不可用 - 仅限键盘操作"
    StatusRefreshing = "正在刷新..."
    StatusFailed = "失败: {0}"
    
    BtnOK = "确定"
    BtnCancel = "取消"
    HelpShortcuts = "键盘快捷键"
    HelpSearch = "搜索"
    HelpSearchDesc = '默认情况下，匹配不区分大小写。用户可以切换成区分大小写、全字匹配或正则表达式匹配。主名称的优先级高于任何可选的备注。'
    HelpLaunch = "启动"
    HelpLaunchDesc = "传统的 .lnk、UWP 应用、注册的 App Paths、System32 工具`n  (.msc / .cpl) 以及 Windows 设置页面 (ms-settings:) 均可从此列表启动。"
    HelpFiles = "文件"
    HelpLog = "日志:"
    HelpConfig = "配置:"
    
    # Help Dialog Keys
    KeyType = "输入"
    ActType = "过滤快捷方式"
    KeyUpDown = "上 / 下"
    ActUpDown = "在列表中移动选择"
    KeyEnter = "回车"
    ActEnter = "启动选中的快捷方式"
    KeyEsc = "Esc"
    ActEsc = "清空输入框"
    KeyF1 = "F1"
    ActF1 = "打开此帮助"
    KeyF2 = "F2"
    ActF2 = "打开设置"
    KeyF3 = "F3"
    ActF3 = "显示/隐藏桌面图标"
    KeyF4 = "F4"
    ActF4 = "切换语音输入"
    KeyF5 = "F5"
    ActF5 = "刷新快捷方式索引"
    KeyAltF4 = "Alt+F4"
    ActAltF4 = "关闭窗口"

    # Setup Dialog
    SecCollections = "采集来源"
    ColDesktop = "桌面快捷方式"
    ColTaskbar = "任务栏固定快捷方式"
    ColStartLnk = "开始菜单 .lnk 文件"
    ColStartApps = "Get-StartApps (UWP / 传统)"
    ColAppPaths = "App Paths (注册表)"
    ColTools = "System32 工具 (.msc / .cpl)"
    ColSettings = "设置页面 (ms-settings:)"
    ColDocuments = "文档 (.docx, .pdf, .txt 等)"
    ColMultimedia = "多媒体 (.mp3, .mp4, .jpg 等)"
    
    SecSearch = "搜索"
    OptAltNames = "备注和别名"
    
    SecVoice = "语音"
    VoiceLang = "识别语言:"
    VoiceNoRecognizers = "(未安装识别器)"
    
    SecAppearance = "外观"
    ThemeLabel = "主题:"
    ThemeSystem = "跟随系统"
    ThemeLight = "浅色"
    ThemeDark = "深色"
    OpacityLabel = "不透明度:"
    UILangLabel = "界面语言:"
    UILangSystem = "跟随系统"
    UILangRestart = "界面语言已更改。请重启快捷启动器以使更改生效。"

    TooltipSetup = "设置"
    TooltipCase = "区分大小写"
    TooltipWord = "全字匹配"
    TooltipRegex = "使用正则表达式"
    
    # Settings Pages (Name is displayed in the list)
    SettingsPages = @(
        @{ Name = '设置 - 主页'; Uri = 'ms-settings:' }
        @{ Name = '设置 - 显示'; Uri = 'ms-settings:display' }
        @{ Name = '设置 - 声音'; Uri = 'ms-settings:sound' }
        @{ Name = '设置 - 通知和操作'; Uri = 'ms-settings:notifications' }
        @{ Name = '设置 - 电源和睡眠'; Uri = 'ms-settings:powersleep' }
        @{ Name = '设置 - 存储'; Uri = 'ms-settings:storagesense' }
        @{ Name = '设置 - 蓝牙和其他设备'; Uri = 'ms-settings:bluetooth' }
        @{ Name = '设置 - 打印机和扫描仪'; Uri = 'ms-settings:printers' }
        @{ Name = '设置 - 网络和 Internet'; Uri = 'ms-settings:network' }
        @{ Name = '设置 - 个性化'; Uri = 'ms-settings:personalization' }
        @{ Name = '设置 - 应用和功能'; Uri = 'ms-settings:appsfeatures' }
        @{ Name = '设置 - 账户'; Uri = 'ms-settings:yourinfo' }
        @{ Name = '设置 - 时间和语言'; Uri = 'ms-settings:dateandtime' }
        @{ Name = '设置 - 游戏'; Uri = 'ms-settings:gaming-gamebar' }
        @{ Name = '设置 - 轻松使用'; Uri = 'ms-settings:easeofaccess' }
        @{ Name = '设置 - 隐私'; Uri = 'ms-settings:privacy' }
        @{ Name = '设置 - 更新和安全'; Uri = 'ms-settings:windowsupdate' }
    )
}