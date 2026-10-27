@{
    AppTitle = "শর্টকাট লঞ্চার"
    AppListening = "শর্টকাট লঞ্চার - শুনছে (থামাতে F4)"
    AppFatalError = "শর্টকাট লঞ্চার - মারাত্মক ত্রুটি"
    
    SettingsTitle = "শর্টকাট লঞ্চার - সেটআপ"
    HelpTitle = "শর্টকাট লঞ্চার - সহায়তা"
    
    StatusIndexed = "{0}টি শর্টকাট ইনডেক্স করা হয়েছে"
    StatusResults = "'{1}' এর জন্য {0}টি ফলাফল"
    StatusVoiceUnavailable = "ভয়েস অনুপলব্ধ - শুধু কীবোর্ড"
    StatusRefreshing = "রিফ্রেশ হচ্ছে..."
    StatusFailed = "ব্যর্থ: {0}"
    
    BtnOK = "ঠিক আছে"
    BtnCancel = "বাতিল"
    HelpShortcuts = "কীবোর্ড শর্টকাট"
    HelpSearch = "অনুসন্ধান"
    HelpSearchDesc = 'ডিফল্টভাবে মিলকরণ কেস-অসংবেদনশীল। ব্যবহারকারী কেস (Case), পূর্ণ শব্দ (Whole Word) বা রেগুলার এক্সপ্রেশন (Regex) মিলকরণে টগল করতে পারেন। প্রাথমিক নামটি যেকোনো ঐচ্ছিক মন্তব্যের উপরে র‌্যাঙ্ক করা হয়।'    HelpLaunch = "লঞ্চ"
    HelpLaunchDesc = "ক্লাসিক .lnk, UWP অ্যাপ, নিবন্ধিত App Paths, System32 টুল (.msc / .cpl) এবং Windows Settings পৃষ্ঠা (ms-settings:) সবই একই তালিকা থেকে লঞ্চ করা যায়।"
    HelpFiles = "ফাইল"
    HelpLog = "লগ:"
    HelpConfig = "কনফিগ:"
    
    # Help Dialog Keys
    KeyType = "টাইপ"
    ActType = "শর্টকাট ফিল্টার করুন"
    KeyUpDown = "উপরে / নিচে"
    ActUpDown = "তালিকায় নির্বাচন সরান"
    KeyEnter = "Enter"
    ActEnter = "নির্বাচিত শর্টকাট লঞ্চ করুন"
    KeyEsc = "Esc"
    ActEsc = "প্রম্পট পরিষ্কার করুন"
    KeyF1 = "F1"
    ActF1 = "এই সহায়তা খুলুন"
    KeyF2 = "F2"
    ActF2 = "সেটআপ খুলুন"
    KeyF3 = "F3"
    ActF3 = "ডেস্কটপ আইকন টগল করুন"
    KeyF4 = "F4"
    ActF4 = "ভয়েস ইনপুট টগল করুন"
    KeyF5 = "F5"
    ActF5 = "শর্টকাট ইনডেক্স রিফ্রেশ করুন"
    KeyAltF4 = "Alt+F4"
    ActAltF4 = "উইন্ডো বন্ধ করুন"

    # Settings Dialog
    SecCollections = "সংগ্রহ"
    ColDesktop = "ডেস্কটপ শর্টকাট"
    ColTaskbar = "টাস্কবার পিন করা শর্টকাট"
    ColStartLnk = "স্টার্ট-মেনু .lnk ফাইল"
    ColStartApps = "Get-StartApps (UWP / ক্লাসিক)"
    ColAppPaths = "App Paths (রেজিস্ট্রি)"
    ColTools = "System32 টুল (.msc / .cpl)"
    ColSettings = "Settings পৃষ্ঠা (ms-settings:)"
    ColDocuments = "ডকুমেন্ট (.docx, .pdf, .txt, ইত্যাদি)"
    ColMultimedia = "মাল্টিমিডিয়া (.mp3, .mp4, .jpg, ইত্যাদি)"
    
    SecSearch = "অনুসন্ধান"
    OptAltNames = "মন্তব্য এবং উপনাম"
    
    SecVoice = "ভয়েস"
    VoiceLang = "স্বীকৃতি ভাষা:"
    VoiceNoRecognizers = "(কোনো রেকগনাইজার ইনস্টল নেই)"
    
    SecAppearance = "চেহারা"
    ThemeLabel = "থিম:"
    ThemeSystem = "সিস্টেম"
    ThemeLight = "হালকা"
    ThemeDark = "গাঢ়"
    OpacityLabel = "অপাসিটি:"
    UILangLabel = "UI ভাষা:"
    UILangSystem = "সিস্টেম ডিফল্ট"
    UILangRestart = "UI ভাষা পরিবর্তন হয়েছে। পরিবর্তনগুলি কার্যকর করতে শর্টকাট লঞ্চার পুনরায় চালু করুন।"
    
    TooltipSettings = "সেটআপ"
    TooltipCase = "কেস মিলান"
    TooltipWord = "পূর্ণ শব্দ মিলান"
    TooltipRegex = "রেগুলার এক্সপ্রেশন ব্যবহার করুন"
    
    # Settings Pages (Name is displayed in the list)
    SettingsPages = @(
        @{ Name = 'সেটিংস হোম'; Uri = 'ms-settings:' }
        @{ Name = 'সেটিংস ডিসপ্লে'; Uri = 'ms-settings:display' }
        @{ Name = 'সেটিংস সাউন্ড'; Uri = 'ms-settings:sound' }
        @{ Name = 'সেটিংস নোটিফিকেশন'; Uri = 'ms-settings:notifications' }
        @{ Name = 'সেটিংস পাওয়ার স্লিপ'; Uri = 'ms-settings:powersleep' }
        @{ Name = 'সেটিংস স্টোরেজ'; Uri = 'ms-settings:storagesense' }
        @{ Name = 'সেটিংস ব্লুটুথ ডিভাইস'; Uri = 'ms-settings:bluetooth' }
        @{ Name = 'সেটিংস প্রিন্টার স্ক্যানার'; Uri = 'ms-settings:printers' }
        @{ Name = 'সেটিংস নেটওয়ার্ক ইন্টারনেট'; Uri = 'ms-settings:network' }
        @{ Name = 'সেটিংস ব্যক্তিগতকরণ'; Uri = 'ms-settings:personalization' }
        @{ Name = 'সেটিংস অ্যাপস ফিচার'; Uri = 'ms-settings:appsfeatures' }
        @{ Name = 'সেটিংস অ্যাকাউন্ট'; Uri = 'ms-settings:yourinfo' }
        @{ Name = 'সেটিংস সময় ভাষা'; Uri = 'ms-settings:dateandtime' }
        @{ Name = 'সেটিংস গেমিং'; Uri = 'ms-settings:gaming-gamebar' }
        @{ Name = 'সেটিংস অ্যাক্সেসিবিলিটি'; Uri = 'ms-settings:easeofaccess' }
        @{ Name = 'সেটিংস গোপনীয়তা'; Uri = 'ms-settings:privacy' }
        @{ Name = 'সেটিংস আপডেট নিরাপত্তা'; Uri = 'ms-settings:windowsupdate' }
    )
}