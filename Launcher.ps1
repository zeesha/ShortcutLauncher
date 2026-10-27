#Requires -Version 5.1
<#
    Launcher.ps1

    -- Design notes ----------------------------------------------------
    * One window, no console. The PowerShell host console is hidden at
      startup because the GUI carries all state (search results, count,
      MIC status). Fatal errors are surfaced via MessageBox since there
      is nowhere else for them to appear.

    * Show() + DoEvents loop, not ShowDialog(). The speech engine's
      Register-ObjectEvent actions run on the pipeline thread; with
      ShowDialog() that thread is blocked inside the dialog's message
      loop and those actions never fire. Driving the form with
      Application::DoEvents keeps the pipeline thread alive so voice
      results actually arrive.

    * The search box is the only control that ever holds focus
      (TabStop = $false everywhere else, plus a GotFocus redirector and
      form-level Tab suppression). Arrows move the list selection
      without leaving the prompt; Enter / Esc / F1-F5 are handled at
      the form level via KeyPreview so they work regardless of what has
      focus. The form itself is deliberately NOT in the redirector list:
      the form's GotFocus fires during OS activation (including the
      restore sequence) and must complete without interference.

    * File filter runs before dedup. If a Desktop document shortcut
      and a Start-menu app share a name, dedup is name-only and
      first-wins; filtering files first ensures the app (not the
      document) occupies that name slot.

    * In-memory search replaces the CLI's findstr round-trip. Same
      matching rules on the primary name, extended to look at a record's
      AltNames as well (see bilingual note below), just no temp file,
      no child process, no GBK re-encoding per keystroke.

    * Bilingual names. On a Chinese Windows the display name of a
      shortcut / UWP app / Start-menu entry is localized ("计算器",
      "记事本"). To keep such records findable by their English
      identity and by the user's custom comments, every record carries
      an AltNames list populated from whatever is available:
         - Classic .lnk      : target exe stem, .lnk Description
         - UWP               : English hint from the AUMID
         - App Paths         : exe file stem
         - System32 tools    : .msc / .cpl file stem
         - Settings pages    : curated English label
      Search treats both the primary name and AltNames with the same
      ranking; the primary name is preferred on ties. Voice grammar is
      built from both lists as well. Alt-name (including the shortcut
      Description field) participation is toggleable in Settings.

    * Extra launch sources beyond Desktop / Taskbar / Start menu:
         - %APPDATA% and %ProgramData% Start Menu\Programs\**\*.lnk
           (classic Start-menu items Get-StartApps tends to miss)
         - Registry "App Paths" (notepad, cmd, powershell, mspaint, ...)
         - %SystemRoot%\System32\*.msc and *.cpl (admin / control-panel
           applets; FileDescription is localized on a Chinese system)
         - Curated ms-settings: URIs (no public enumeration API exists)
      Sources are collected in priority order so dedup first-wins keeps
      the more specific record (e.g. a real Desktop shortcut wins over a
      same-named App Paths entry). Each source can be disabled in Settings.

    * Appearance. Theme has three options: 'Light', 'Dark', 'System' (follows the
      Windows app theme via HKCU\...\Themes\Personalize\AppsUseLightTheme).
      Default is 'System'. Opacity is a double in [0.3, 1.0], default 0.9; the
      slider in Settings previews live on the parent form and reverts on
      Cancel. Changing either in Settings takes effect immediately without
      a restart: Apply-Theme swaps $script:colors and recolors the live
      controls (the search underline and the owner-drawn list read
      $script:colors at paint time, so Invalidate is enough); Apply-
      Opacity clamps and assigns $script:form.Opacity. The Settings dialog
      itself stays opaque and uses system-native controls, so it
      follows the OS theme rather than the launcher's palette.

    * Settings. Options are stored at
      %LOCALAPPDATA%\ShortcutLauncher\settings.json. A missing or
      unreadable file falls back to defaults. The Settings dialog (button
      at the right of the search bar) edits collections, alt-name
      search, voice language, theme, and opacity. OK saves the file,
      applies theme + opacity, rebuilds the index, and re-initializes
      the voice engine so changes take effect immediately without a
      restart.

    * Localization. UI text is loaded using Import-LocalizedData from
      Strings.psd1 and language-specific subfolders (e.g., zh-CN, ja-JP).
      The fallback is English. Changing the UI language in Settings
      prompts the user to restart the application.

    * Logging. All events that matter (startup, settings load/save,
      theme resolution, index build, voice init, F1-F5 toggles, each
      recognition, each launch attempt + result, fatal errors, shutdown)
      are appended with an ISO timestamp to Launcher.log next to this
      script. Logging is best-effort: the first write failure disables
      it for the rest of the run, because the log is diagnostic, not
      load-bearing. No rotation is done - for a launcher run by hand
      the file grows very slowly.

    * Single instance + activation. A named mutex
      (Local\ShortcutLauncher.Gui.SingleInstance) ensures one instance
      per Windows session. A named AutoResetEvent
      (Local\ShortcutLauncher.Gui.Activate) carries the "come to front"
      request. When a second instance starts it signals the event and
      exits silently; the first instance is polling that event in its
      DoEvents loop (~20ms latency) and, on receipt, restores itself if
      minimized and brings itself to the foreground.

      Event is created BEFORE the mutex so the "mutex held but event
      missing" window is effectively zero. Both objects use the Local\
      prefix, so two interactive sessions of different users each get
      their own independent instance.

    * Minimize / restore. Three cooperating mechanisms:
        1. A NativeWindow subclass (RestoreHook) intercepts
           WM_SYSCOMMAND / SC_RESTORE and forces the same programmatic
           restore that the second-instance activation uses.
        2. Form.Activated also forces Normal if it fires with state
           still Minimized (catches partial restores).
        3. The keepFocus redirector is NOT attached to the form itself,
           so the form's GotFocus during activation runs undisturbed.

      The loop condition is "not disposed" only. A minimized form can
      transiently report Visible = $false during the minimize animation;
      exiting the loop in that state leaves a zombie taskbar icon that
      can't be restored because the message pump is gone. We never call
      Hide(), so the Visible check adds no real protection.

    -- Behaviour -------------------------------------------------------
      type        filter shortcuts
      Up / Down   move selection in the list (cursor stays in the prompt)
      Enter       launch the selected shortcut; prompt is refilled with
                  the full name, window stays open
      Esc         clear the prompt
      F1          open Help
      F2          open Settings
      F3          toggle desktop icons
      F4          toggle voice input
      F5          refresh index (re-scan shortcuts)
      Alt+F4      close the window
#>

# ---------------------------------------------------------------- single instance
$script:ActivateEvent = New-Object System.Threading.EventWaitHandle(
    $false,
    [System.Threading.EventResetMode]::AutoReset,
    'Local\ShortcutLauncher.Gui.Activate')

$script:AppMutex = New-Object System.Threading.Mutex(
    $false,
    'Local\ShortcutLauncher.Gui.SingleInstance')

$script:IsFirstInstance = $false
try {
    $script:IsFirstInstance = $script:AppMutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    # Previous holder crashed while owning the mutex.
    $script:IsFirstInstance = $true
}

if (-not $script:IsFirstInstance) {
    # Another instance is running. Signal it to restore + focus, then exit
    # silently.
    if ($script:ActivateEvent) {
        try { [void]$script:ActivateEvent.Set() } catch { }
        try { $script:ActivateEvent.Dispose() } catch { }
    }
    try { $script:AppMutex.Dispose() } catch { }
    exit
}

# ---------------------------------------------------------------- UI / speech assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech -ErrorAction SilentlyContinue
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- hide console
try {
    if (-not ([System.Management.Automation.PSTypeName]'Native.Win32Console').Type) {
        Add-Type -Namespace Native -Name Win32Console -MemberDefinition @"
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@
    }
    $__h = [Native.Win32Console]::GetConsoleWindow()
    if ($__h -ne [IntPtr]::Zero) {
        [void][Native.Win32Console]::ShowWindow($__h, 0)
    }
} catch { }

$WshShell = New-Object -ComObject WScript.Shell

# ============================================================
# LOGGING
# ============================================================
# Pick the first writable location for Launcher.log: script directory
# (natural place) then LocalAppData (for installs under Program Files
# or other read-only locations). If none is writable, logging is
# silently disabled; the app still works.
$script:LogPath = $null
foreach ($candidate in @(
    $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Launcher.log' }),
    $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'ShortcutLauncher\Launcher.log' })
)) {
    if (-not $candidate) { continue }
    try {
        $dir = Split-Path -Parent $candidate
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            [void](New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop)
        }
        [System.IO.File]::AppendAllText($candidate, '')
        $script:LogPath = $candidate
        break
    } catch { }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO'
    )
    if (-not $script:LogPath) { return }
    try {
        $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -LiteralPath $script:LogPath `
                    -Value "[$ts] [$Level] $Message" `
                    -Encoding UTF8 -ErrorAction Stop
    } catch {
        # One write failure disables logging for the rest of this run.
        $script:LogPath = $null
    }
}

Write-Log "=== Shortcut Launcher starting ==="
Write-Log "  single_instance=acquired pid=$PID user=$env:USERNAME computer=$env:COMPUTERNAME"
Write-Log "  ps=$($PSVersionTable.PSVersion) host=$($Host.Name)"
Write-Log "  log=$($script:LogPath)"

# ============================================================
# SETTINGS
# ============================================================
$script:SettingsDir  = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA 'ShortcutLauncher'
} else {
    $null
}

$script:SettingsPath = if ($script:SettingsDir) {
    Join-Path $script:SettingsDir 'settings.json'
} else {
    $null
}

$script:DefaultSettings = [ordered]@{
    IncludeDesktop       = $true
    IncludeTaskbar       = $true
    IncludeStartMenuLnk  = $true
    IncludeStartApps     = $true
    IncludeAppPaths      = $true
    IncludeSystemTools   = $true
    IncludeSettingsPages = $true
    IncludeDocuments     = $false
    IncludeMultimedia    = $false
    SearchAltNames       = $true
    VoiceCulture         = 'en-US'
    Theme                = 'System'
    Opacity              = 0.9
    UILanguage           = 'System'
    MatchCase            = $false
    MatchWholeWord       = $false
    MatchRegex           = $false
}

function Clamp-Opacity {
    param($Value)
    if ($null -eq $Value) { return 0.9 }
    $v = 0.9
    try { $v = [double]$Value } catch { return 0.9 }
    if ($v -lt 0.3) { $v = 0.3 }
    if ($v -gt 1.0) { $v = 1.0 }
    return $v
}

function Load-Settings {
    $s = @{}
    foreach ($k in $script:DefaultSettings.Keys) {
        $s[$k] = $script:DefaultSettings[$k]
    }
    
    if (-not $script:SettingsPath) { return $s }
    
    try {
        if (Test-Path -LiteralPath $script:SettingsPath) {
            $json = Get-Content -LiteralPath $script:SettingsPath -Raw -ErrorAction Stop |
                    ConvertFrom-Json
            foreach ($k in @($script:DefaultSettings.Keys)) {
                if ($null -ne $json.$k) { $s[$k] = $json.$k }
            }
            Write-Log "Settings: loaded from $($script:SettingsPath)"
        }
    } catch {
        Write-Log "Settings: load failed, using defaults: $($_.Exception.Message)" -Level WARN
    }
    return $s
}

function Save-Settings {
    if (-not $script:SettingsPath) {
        Write-Log "Settings: no writable path, save skipped" -Level WARN
        return
    }
    try {
        if ($script:SettingsDir -and -not (Test-Path -LiteralPath $script:SettingsDir)) {
            [void](New-Item -ItemType Directory -Path $script:SettingsDir -Force -ErrorAction Stop)
        }
        ($script:Settings | ConvertTo-Json -Depth 4) |
            Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8 -ErrorAction Stop
        Write-Log "Settings: saved to $($script:SettingsPath)"
    } catch {
        Write-Log "Settings: save failed: $($_.Exception.Message)" -Level WARN
    }
}

$script:Settings = Load-Settings

# ============================================================
# LOCALIZATION
# ============================================================
# Determine the directory where the script is located
$ScriptDirectory = $PSScriptRoot
if ([string]::IsNullOrEmpty($ScriptDirectory)) {
    $ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Get-LocalizedStrings {
    param (
        [string]$Directory
    )

    # 1. Check the user's saved setting first
    $uiLangSetting = if ($script:Settings -and $script:Settings.UILanguage) { $script:Settings.UILanguage } else { 'System' }

    $candidates = @()
    
    # If the user explicitly chose a language, try that first
    if ($uiLangSetting -ne 'System') {
        $candidates += "Strings.$uiLangSetting.psd1"
        
        # If they chose English, make sure it falls back to the default Strings.psd1
        if ($uiLangSetting -eq 'en-US') { $candidates += "Strings.psd1" }
    }

    # 2. Fallback to Windows system languages
    $uiCulture = (Get-UICulture).Name
    $sysCulture = (Get-Culture).Name

    $candidates += @(
        "Strings.$uiCulture.psd1"
        "Strings.$sysCulture.psd1"
        "Strings.psd1"
    )

    # Remove duplicates
    $candidates = $candidates | Select-Object -Unique

    foreach ($file in $candidates) {
        $filePath = Join-Path -Path $Directory -ChildPath $file
        if (Test-Path -Path $filePath) {
            try {
                return Import-PowerShellDataFile -Path $filePath -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to load language file '$file': $_"
            }
        }
    }

    throw "No localization files found in $Directory"
}

# Load the strings
try {
    $Strings = Get-LocalizedStrings -Directory $ScriptDirectory
    $script:L = $Strings  # <--- ADD THIS LINE
}
catch {
    Write-Error $_
    exit 1
}

# ============================================================
# THEME
# ============================================================
function Resolve-Theme {
    param([string]$Theme)
    $t = if ($Theme) { $Theme.ToLowerInvariant() } else { 'System' }
    if ($t -eq 'light') { return 'Light' }
    if ($t -eq 'dark')  { return 'Dark' }
    try {
        $v = (Get-ItemProperty `
                -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                -Name 'AppsUseLightTheme' `
                -ErrorAction Stop).AppsUseLightTheme
        if ($null -ne $v -and [int]$v -eq 1) { return 'Light' }
    } catch { }
    return 'Dark'
}

function Get-ThemePalette {
    param([string]$Effective)
    if ($Effective -eq 'Light') {
        return @{
            bg      = [System.Drawing.Color]::FromArgb(250, 250, 252)
            surface = [System.Drawing.Color]::FromArgb(232, 234, 240)
            accent  = [System.Drawing.Color]::FromArgb(180,  90,  10)
            text    = [System.Drawing.Color]::FromArgb( 28,  30,  38)
            muted   = [System.Drawing.Color]::FromArgb(100, 106, 122)
            error   = [System.Drawing.Color]::FromArgb(190,  36,  36)
        }
    }
    # Dark
    return @{
        bg      = [System.Drawing.Color]::FromArgb( 22,  24,  30)
        surface = [System.Drawing.Color]::FromArgb( 35,  38,  48)
        accent  = [System.Drawing.Color]::FromArgb(255, 170,  40)
        text    = [System.Drawing.Color]::FromArgb(238, 240, 245)
        muted   = [System.Drawing.Color]::FromArgb(126, 132, 148)
        error   = [System.Drawing.Color]::FromArgb(235, 100, 100)
    }
}

# ============================================================
# P/INVOKE (Desktop Icons)
# ============================================================
$script:DesktopIconsAvailable = $false
try {
    if (-not ([System.Management.Automation.PSTypeName]'Native.DesktopIcons').Type) {
        Add-Type -Namespace Native -Name DesktopIcons -MemberDefinition @"
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string className, string windowTitle);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
"@
    }
    $script:DesktopIconsAvailable = $true
} catch {
    Write-Log "DesktopIcons P/Invoke compile failed: $($_.Exception.Message)" -Level WARN
}

# ============================================================
# RESTORE HOOK COMPILATION
# ============================================================
$script:RestoreHookAvailable = $false
try {
    if (-not ([System.Management.Automation.PSTypeName]'RestoreHook').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Windows.Forms;

public class RestoreHook : NativeWindow {
    public Form TargetForm;

    protected override void WndProc(ref Message m) {
        const int WM_SYSCOMMAND = 0x0112;
        const int SC_RESTORE    = 0xF120;

        if (m.Msg == WM_SYSCOMMAND && TargetForm != null) {
            int cmd = (int)(m.WParam.ToInt64() & 0xFFF0);
            if (cmd == SC_RESTORE) {
                base.WndProc(ref m);
                try {
                    if (TargetForm.WindowState == FormWindowState.Minimized) {
                        TargetForm.WindowState = FormWindowState.Normal;
                    }
                    TargetForm.TopMost = true;
                    TargetForm.Activate();
                    TargetForm.TopMost = false;
                } catch { }
                return;
            }
        }
        base.WndProc(ref m);
    }
}
'@ -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction Stop
    }
    $script:RestoreHookAvailable = $true
} catch {
    Write-Log "RestoreHook compile error: $($_.Exception.Message)" -Level WARN
}

# ============================================================
# FILE FILTER
# ============================================================
$script:DocumentExtensions = New-Object 'System.Collections.Generic.HashSet[string]' (
    [System.StringComparer]::OrdinalIgnoreCase
)

@(
    # Office
    '.doc','.docx','.docm','.dot','.dotx',
    '.xls','.xlsx','.xlsm','.xlt','.xltx',
    '.ppt','.pptx','.pptm','.pot','.potx',
    '.csv','.rtf','.odt','.ods','.odp',
    # PDF / e-book
    '.pdf','.epub','.mobi',
    # Text / markup
    '.txt','.md','.markdown','.log','.html','.htm','.xml','.json',
    # Archives
    '.zip','.rar','.7z','.tar','.gz','.tgz','.bz2','.xz','.cab'
) | ForEach-Object { [void]$script:DocumentExtensions.Add($_) }
$script:MultimediaExtensions = New-Object 'System.Collections.Generic.HashSet[string]' (
    [System.StringComparer]::OrdinalIgnoreCase
)

@(
    # Images
    '.png','.jpg','.jpeg','.gif','.bmp','.tif','.tiff',
    '.svg','.webp','.heic','.heif',
    # Media
    '.mp3','.mp4','.mkv','.wav','.flac',
    '.m4a','.m4v','.avi','.mov','.wmv','.webm','.ogg','.aac','.wma',
    # Disk images
    '.iso','.vhd','.vhdx','.img'
) | ForEach-Object { [void]$script:MultimediaExtensions.Add($_) }

function Test-IsExcludedTarget {
    param([string]$Target)
    if (-not $Target) { return $false }
    $t = $Target.Trim()
    if ($t.Length -eq 0) { return $false }
    try {
        if (Test-Path -LiteralPath $t -PathType Container) { return $false }
        $ext = [System.IO.Path]::GetExtension($t)
        if (-not $ext) { return $false }
        
        if ($script:DocumentExtensions.Contains($ext) -and -not $script:Settings.IncludeDocuments) {
            return $true
        }
        if ($script:MultimediaExtensions.Contains($ext) -and -not $script:Settings.IncludeMultimedia) {
            return $true
        }
        return $false
    } catch { return $false }
}

# Follow one extra .lnk hop so a shortcut-to-a-shortcut-to-a-document
# is still classified correctly. Deliberately limited to one hop to
# avoid cycles and pathological chains.
function Resolve-ChainedLnkTarget {
    param([string]$TargetPath)
    if (-not $TargetPath) { return $null }
    try {
        if ([System.IO.Path]::GetExtension($TargetPath).ToLowerInvariant() -eq '.lnk' -and
            (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
            return $WshShell.CreateShortcut($TargetPath).TargetPath
        }
    } catch { }
    return $null
}

# ============================================================
# P/INVOKE (Localized Strings)
# ============================================================
$script:ShlwapiAvailable = $false
try {
    if (-not ([System.Management.Automation.PSTypeName]'Native.Shlwapi').Type) {
        Add-Type -Namespace Native -Name Shlwapi -MemberDefinition @"
    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode, SetLastError = false)]
    public static extern int SHLoadIndirectString(string pszSource, System.Text.StringBuilder pszOutBuf, uint cchOutBuf, IntPtr ppvReserved);

    [DllImport("kernel32.dll")]
    public static extern ushort SetThreadUILanguage(ushort LangId);
"@
    }
    $script:ShlwapiAvailable = $true
} catch {
    Write-Log "SHLoadIndirectString P/Invoke compile failed: $($_.Exception.Message)" -Level WARN
}


# ============================================================
# SEARCH HELPERS
# ============================================================
function Normalize-SearchText {
    param([string]$Text)
    if (-not $Text) { return '' }
    # Remove zero-width characters and variation selectors
    $clean = $Text -replace '[\u200B-\u200D\uFE00-\uFE0F]', ''
    # Normalize to FormKC (compatibility composition) and lowercase
    return $clean.Trim().Normalize([System.Text.NormalizationForm]::FormKC).ToLowerInvariant()
}

function Get-AumidEnglishHint {
    param([string]$Aumid)
    if (-not $Aumid) { return $null }
    try {
        $pkgPart = $Aumid.Split('!')[0]
        if (-not $pkgPart) { return $null }
        $pkg  = $pkgPart.Split('_')[0]
        $segs = $pkg.Split('.')
        $last = if ($segs.Count -ge 2) { $segs[-1] } else { $segs[0] }
        if (-not $last) { return $null }
        $stripped = $last -replace '^(Windows|Microsoft)', ''
        if ($stripped) { return $stripped }
        return $last
    } catch { return $null }
}

# Helper to resolve an indirect string from the registry using SHLoadIndirectString
function Resolve-IndirectString {
    param([string]$Source)
    if (-not $Source -or -not $script:ShlwapiAvailable) { return $null }
    try {
        # Get current system UI language (e.g., zh-CN corresponds to LCID 0x0804)
        $langId = [System.Globalization.CultureInfo]::CurrentUICulture.LCID
        
        # Temporarily set the current thread language to force SHLoadIndirectString to use system language
        $oldLang = [Native.Shlwapi]::SetThreadUILanguage([uint16]$langId)
        
        $sb = New-Object System.Text.StringBuilder 1024
        $hr = [Native.Shlwapi]::SHLoadIndirectString($Source, $sb, [uint32]$sb.Capacity, [IntPtr]::Zero)
        
        # Restore the original thread language
        [void][Native.Shlwapi]::SetThreadUILanguage($oldLang)
        
        if ($hr -eq 0 -and $sb.Length -gt 0) {
            return $sb.ToString()
        }
    } catch { }
    return $null
}


function Get-SearchRank {
    param([string]$Text, [string]$PatternLower, [regex]$Regex)
    if (-not $Text) { return -1 }
    
    if ($Regex) {
        $m = $Regex.Match($Text)
        if (-not $m.Success) { return -1 }
        if ($m.Index -eq 0 -and $m.Length -eq $Text.Length) { return 0 }
        if ($m.Index -eq 0) { return 1 }
        return 2
    } else {
        $t = Normalize-SearchText $Text
        $i = $t.IndexOf($PatternLower, [System.StringComparison]::Ordinal)
        if ($i -lt 0) { return -1 }
        if ($t -eq $PatternLower) { return 0 }
        if ($i -eq 0)             { return 1 }
        return 2
    }
}

# ============================================================
# COLLECTORS
# ============================================================
$script:ItemsFiltered = 0

function Get-AumidFromLnk {
    param([string]$LnkPath)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($LnkPath)
        $u16   = [System.Text.Encoding]::Unicode.GetString($bytes)
        $pattern = '([A-Za-z0-9\.\-]+_[a-z0-9]{13}![A-Za-z0-9\.\-]+)'
        $m = [regex]::Match($u16, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    return $null
}

function Get-ShortcutInfo {
    param([string]$LnkPath)
    try {
        $lnk     = $WshShell.CreateShortcut($LnkPath)
        $target  = $lnk.TargetPath
        $argLine = $lnk.Arguments
        $workdir = $lnk.WorkingDirectory
        $name    = [System.IO.Path]::GetFileNameWithoutExtension($LnkPath)
        $altNames = @()

        if ($target) {
            try {
                $tstem = [System.IO.Path]::GetFileNameWithoutExtension($target)
                if ($tstem -and $tstem -ne $name -and $tstem -notin $altNames) {
                    $altNames += $tstem
                }
            } catch { }
        }
        
        try {
            $desc = $lnk.Description
            if ($desc -and $desc -ne $name -and $desc -notin $altNames) {
                $altNames += $desc
            }
        } catch { }

        if ($target) {
            $classifyTarget = $target
            $hop = Resolve-ChainedLnkTarget -TargetPath $target
            if ($hop) { $classifyTarget = $hop }
            
            $exec = $target
            if ($argLine -and $argLine.Trim().Length -gt 0) {
                $exec = "$exec $argLine"
            }
            
            return [PSCustomObject]@{
                Name        = $name
                Kind        = 'Classic'
                Target      = $target
                Args        = $argLine
                WorkDir     = $workdir
                Exec        = $exec
                Path        = $LnkPath
                IsExcluded  = Test-IsExcludedTarget $classifyTarget
                AltNames    = $altNames
                WindowStyle = [int]$lnk.WindowStyle
            }
        }
        
        $aumid = Get-AumidFromLnk -LnkPath $LnkPath
        if ($aumid) {
            $en  = Get-AumidEnglishHint $aumid
            $alt = @()
            if ($en -and $en -ne $name) { $alt += $en }
            
            return [PSCustomObject]@{
                Name        = $name
                Kind        = 'UWP'
                Target      = $aumid
                Args        = ''
                WorkDir     = ''
                Exec        = "shell:AppsFolder\$aumid"
                Path        = $LnkPath
                IsDocument  = $false
                AltNames    = $alt
                WindowStyle = [int]$lnk.WindowStyle
            }
        }
        
        return [PSCustomObject]@{
            Name        = $name
            Kind        = 'Unknown'
            Target      = ''
            Args        = ''
            WorkDir     = ''
            Exec        = ''
            Path        = $LnkPath
            IsDocument  = $false
            AltNames    = @()
            WindowStyle = [int]$lnk.WindowStyle
        }
    } catch { return $null }
}

function Get-Shortcuts {
    param([string[]]$Paths)
    $out = @()
    foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p) {
            $files = Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                if ($f.Extension -eq '.lnk') {
                    $info = Get-ShortcutInfo -LnkPath $f.FullName
                    if ($info) {
                        if ($info.IsExcluded) { 
                            $script:ItemsFiltered++ 
                        } else { 
                            $out += $info 
                        }
                    }
                } else {
                    # Check if the raw file is allowed (Documents or Multimedia)
                    if (-not (Test-IsExcludedTarget $f.FullName)) {
                        $out += [PSCustomObject]@{
                            Name        = $f.BaseName
                            Kind        = 'File'
                            Target      = $f.FullName
                            Args        = ''
                            WorkDir     = $f.DirectoryName
                            Exec        = $f.FullName
                            Path        = $f.FullName
                            IsExcluded  = $false
                            AltNames    = @($f.Name)
                            WindowStyle = 1
                        }
                    } else {
                        $script:ItemsFiltered++
                    }
                }
            }
        }
    }
    return $out
}

function Get-StartMenuApps {
    $out = @()

    
    # Pre-build a lookup table of PackageFullName -> Localized DisplayName from the registry
    $registryNames = @{}
    try {
        $regPath = 'HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages'
        $regKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey(
            $regPath.Replace('HKEY_CLASSES_ROOT\', '')
        )
        if ($regKey) {
            foreach ($subKeyName in $regKey.GetSubKeyNames()) {
                $subKey = $regKey.OpenSubKey($subKeyName)
                if ($subKey) {
                    $indirect = $subKey.GetValue('DisplayName')
                    if ($indirect) {
                        $localized = Resolve-IndirectString -Source $indirect
                        if ($localized) { $registryNames[$subKeyName] = $localized }
                    }
                }
            }
        }
    } catch { }


    try { $apps = Get-StartApps } catch { return $out }
    if ($null -eq $apps) { return $out }
    
    foreach ($app in $apps) {
        $id = $app.AppID
        if (-not $id) { continue }

        # UWP / Store app -> always an app.
        if ($id -match '^[A-Za-z0-9\.\-]+_[a-z0-9]{13}!') {
            $displayName = $app.Name
            
            # Try to get localized name from registry cache
            $aumidPackage = $id.Split('!')[0]
            $packageNamePart = $aumidPackage.Split('_')[0] # e.g., Microsoft.WindowsCalculator
            
            if ($registryNames.ContainsKey($aumidPackage)) {
                $displayName = $registryNames[$aumidPackage]
            } else {
                # Fallback: try to resolve by iterating (slower)
                foreach ($k in $registryNames.Keys) {
                    if ($k -like "$packageNamePart*") {
                        $displayName = $registryNames[$k]
                        break
                    }
                }
            }
        
            $en = Get-AumidEnglishHint $id
            $alt = @()
            if ($en -and $en -ne $displayName) { $alt += $en }
            
            $out += [PSCustomObject]@{
                Name        = $displayName
                Kind        = 'UWP'
                Target      = $id
                Args        = ''
                WorkDir     = ''
                Exec        = "shell:AppsFolder\$id"
                Path        = "shell:AppsFolder\$id"
                IsDocument  = $false
                AltNames    = $alt
                WindowStyle = 1
            }
            continue
        }

        # Classic Start-menu entry
        $classifyTarget = $null
        $altNames = @()
        try {
            if (Test-Path -LiteralPath $id -PathType Leaf) {
                $lnk = $WshShell.CreateShortcut($id)
                $classifyTarget = $lnk.TargetPath
                $hop = Resolve-ChainedLnkTarget -TargetPath $classifyTarget
                if ($hop) { $classifyTarget = $hop }
                try {
                    $stem = [System.IO.Path]::GetFileNameWithoutExtension($id)
                    if ($stem -and $stem -ne $app.Name) { $altNames += $stem }
                } catch { }
            }
        } catch { }
        
        if (Test-IsExcludedTarget $classifyTarget) {
            $script:ItemsFiltered++
            continue
        }
        
        if ($id -match '^\{[^}]+\}\\(.+)$') {
            try {
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($Matches[1])
                if ($stem -and $stem -ne $app.Name -and $stem -notin $altNames) {
                    $altNames += $stem
                }
            } catch { }
        }
        
        $out += [PSCustomObject]@{
            Name        = $app.Name
            Kind        = 'Classic'
            Target      = $id
            Args        = ''
            WorkDir     = ''
            Exec        = $id
            Path        = $id
            IsDocument  = $false
            AltNames    = $altNames
            WindowStyle = 1
        }
    }
    return $out
}

function Get-AppPathCommands {
    $out = @()
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    )
    $seenExe = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        
        foreach ($key in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $exe = $key.GetValue('')
                if (-not $exe) { continue }
                $exe = [Environment]::ExpandEnvironmentVariables([string]$exe)
                if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
                if (-not $seenExe.Add($exe)) { continue }
                
                $friendly = $null
                try {
                    $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
                    if ($vi.FileDescription) { $friendly = $vi.FileDescription.Trim() }
                } catch { }
                
                if (-not $friendly) {
                    $friendly = [System.IO.Path]::GetFileNameWithoutExtension($exe)
                }
                
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($exe)
                $alt = @()
                if ($stem -and $stem -ne $friendly) { $alt += $stem }
                
                $out += [PSCustomObject]@{
                    Name        = $friendly
                    Kind        = 'Command'
                    Target      = $exe
                    Args        = ''
                    WorkDir     = (Split-Path -Parent $exe)
                    Exec        = $exe
                    Path        = $exe
                    IsDocument  = $false
                    AltNames    = $alt
                    WindowStyle = 1
                }
            } catch { }
        }
    }
    return $out
}

# Administrative / Control Panel tools
function Get-SystemTools {
    $out = @()
    $sys32 = Join-Path $env:SystemRoot 'System32'
    if (-not (Test-Path -LiteralPath $sys32)) { return $out }
    
    foreach ($ext in @('*.msc', '*.cpl')) {
        $files = Get-ChildItem -LiteralPath $sys32 -Filter $ext -File -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $file = $f.FullName
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $friendly = $null
            
            try {
                $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file)
                if ($vi.FileDescription) { $friendly = $vi.FileDescription.Trim() }
            } catch { }
            
            if (-not $friendly -or $friendly -match '^@') { $friendly = $stem }
            $alt = @()
            if ($stem -and $stem -ne $friendly) { $alt += $stem }
            
            $out += [PSCustomObject]@{
                Name        = $friendly
                Kind        = 'Tool'
                Target      = $file
                Args        = ''
                WorkDir     = $sys32
                Exec        = $file
                Path        = $file
                IsDocument  = $false
                AltNames    = $alt
                WindowStyle = 1
            }
        }
    }
    return $out
}

function Get-SettingsPages {
    $out = @()
    foreach ($p in $script:L.SettingsPages) {
        $alt = @($p.Uri) | Where-Object { $_ } | Select-Object -Unique
        $out += [PSCustomObject]@{
            Name        = $p.Name
            Kind        = 'Settings'
            Target      = $p.Uri
            Args        = ''
            WorkDir     = ''
            Exec        = $p.Uri
            Path        = $p.Uri
            IsDocument  = $false
            AltNames    = @($alt)
            WindowStyle = 1
        }
    }
    return $out
}

# ============================================================
# MAIN BODY
# ============================================================
try {

# ---------------------------------------------------------------- palette & fonts
$script:EffectiveTheme = Resolve-Theme -Theme $script:Settings.Theme
$script:colors         = Get-ThemePalette -Effective $script:EffectiveTheme
$script:fontName       = New-Object System.Drawing.Font('Segoe UI', 11)
$script:fontHint       = New-Object System.Drawing.Font('Segoe UI', 9)

# ---------------------------------------------------------------- core UI actions
function Update-Results {
    param([string]$Query)
    $lb = $script:listBox
    if (-not $lb -or $lb.IsDisposed) { return }

    $q = ''
    if ($null -ne $Query) { $q = $Query.Trim() }

    $results = if ($q.Length -eq 0) { $script:shortcuts } else { Invoke-Search -Pattern $q }

    $lb.BeginUpdate()
    try {
        $lb.Items.Clear()
        foreach ($r in $results) { [void]$lb.Items.Add($r) }
    } finally {
        $lb.EndUpdate()
    }

    if ($lb.Items.Count -gt 0) { $lb.SelectedIndex = 0 }

    $script:countLabel.ForeColor = $script:colors.muted
    if ($q.Length -eq 0) {
        $script:countLabel.Text = $script:L.StatusIndexed -f $script:shortcuts.Count
    } else {
        $script:countLabel.Text = $script:L.StatusResults -f $lb.Items.Count, $q
    }
}

function Invoke-Search {
    param([string]$Pattern)
    $safe = $Pattern.Trim()
    if (-not $safe -and -not $script:Settings.MatchRegex) { return @() }
    
    $useAlt   = [bool]$script:Settings.SearchAltNames
    $ranked   = New-Object System.Collections.ArrayList
    
    $useRegex = $script:Settings.MatchRegex -or $script:Settings.MatchWholeWord -or $script:Settings.MatchCase
    $regex = $null
    $patLower = $null

    if ($useRegex) {
        $regexOptions = if ($script:Settings.MatchCase) { [System.Text.RegularExpressions.RegexOptions]::None } else { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        $regexStr = $safe
        if (-not $script:Settings.MatchRegex) {
            $regexStr = [regex]::Escape($regexStr)
        }
        if ($script:Settings.MatchWholeWord) {
            $regexStr = '\b' + $regexStr + '\b'
        }
        try {
            $regex = New-Object System.Text.RegularExpressions.Regex($regexStr, $regexOptions)
        } catch {
            return @() # Invalid regex
        }
    } else {
        $patLower = Normalize-SearchText $safe
    }
    
    foreach ($rec in $script:shortcuts) {
        $best = -1
        $nr = Get-SearchRank -Text $rec.Name -PatternLower $patLower -Regex $regex
        if ($nr -ge 0) { $best = $nr * 2 }

        if ($useAlt -and $rec.AltNames -and @($rec.AltNames).Count -gt 0) {
            foreach ($alt in $rec.AltNames) {
                if (-not $alt) { continue }
                $ar = Get-SearchRank -Text $alt -PatternLower $patLower -Regex $regex
                if ($ar -ge 0) {
                    $w = $ar * 2 + 1
                    if ($best -lt 0 -or $w -lt $best) { $best = $w }
                }
            }
        }
        if ($best -lt 0) { continue }
        [void]$ranked.Add([PSCustomObject]@{ Rank = $best; Record = $rec })
    }
    
    $sorted = $ranked | Sort-Object Rank, @{ Expression = { $_.Record.Name } }
    return @($sorted | ForEach-Object { $_.Record })
}

function Get-SelectedItem {
    $lb = $script:listBox
    if (-not $lb -or $lb.Items.Count -eq 0) { return $null }
    if ($lb.SelectedIndex -ge 0) { return $lb.SelectedItem }
    return $lb.Items[0]
}

function Invoke-Shortcut {
    param($Shortcut)
    if (-not $Shortcut) { return $null }
    
    $desc = "name='$($Shortcut.Name)' kind=$($Shortcut.Kind) target='$($Shortcut.Target)'"
    if ($Shortcut.Args)    { $desc += " args='$($Shortcut.Args)'" }
    if ($Shortcut.WorkDir) { $desc += " workdir='$($Shortcut.WorkDir)'" }

    try {
        $lnkPath = $Shortcut.Path
        if ($lnkPath -and $lnkPath -match '\.lnk$' -and
            (Test-Path -LiteralPath $lnkPath -PathType Leaf)) {
            Start-Process -FilePath $lnkPath
            Write-Log "Launch OK: $desc via original .lnk"
            return $null
        }
        
        if ($Shortcut.Kind -eq 'UWP') {
            Start-Process -FilePath "explorer.exe" `
                          -ArgumentList "shell:AppsFolder\$($Shortcut.Target)"
            Write-Log "Launch OK: $desc via AppsFolder"
            return $null
        }
        
        if ($Shortcut.Target) {
            if ($Shortcut.Target -match '^[a-zA-Z][a-zA-Z0-9+.\-]+:') {
                Start-Process -FilePath $Shortcut.Target
                Write-Log "Launch OK: $desc via URI scheme"
                return $null
            }
            
            if ($Shortcut.Target -match '^\{[^}]+\}') {
                Start-Process -FilePath "explorer.exe" `
                              -ArgumentList "shell:AppsFolder\$($Shortcut.Target)"
                Write-Log "Launch OK: $desc via AppsFolder GUID"
                return $null
            }
            
            $isFilePath = $false
            try {
                $isFilePath = Test-Path -LiteralPath $Shortcut.Target -PathType Leaf
            } catch { }
            
            if ($isFilePath) {
                $params = @{ FilePath = $Shortcut.Target }
                
                if ($Shortcut.Args -and $Shortcut.Args.Trim().Length -gt 0) {
                    $params.ArgumentList = $Shortcut.Args
                }
                if ($Shortcut.WorkDir -and (Test-Path -LiteralPath $Shortcut.WorkDir)) {
                    $params.WorkingDirectory = $Shortcut.WorkDir
                }
                if ($Shortcut.PSObject.Properties['WindowStyle']) {
                    switch ([int]$Shortcut.WindowStyle) {
                        3 { $params.WindowStyle = 'Maximized' }
                        7 { $params.WindowStyle = 'Minimized' }
                    }
                }
                Start-Process @params
                Write-Log "Launch OK: $desc"
                return $null
            }
            
            Start-Process -FilePath "explorer.exe" `
                          -ArgumentList "shell:AppsFolder\$($Shortcut.Target)"
            Write-Log "Launch OK: $desc via AppsFolder fallback"
        } else {
            Start-Process -FilePath $Shortcut.Path
            Write-Log "Launch OK: $desc via shortcut path"
        }
        return $null
    } catch {
        $msg = $_.Exception.Message
        Write-Log "Launch FAILED: $desc error='$msg'" -Level ERROR
        return $msg
    }
}

function Invoke-Selected {
    param($Item)
    if (-not $Item) { return }
    
    $err = Invoke-Shortcut -Shortcut $Item
    if ($err) {
        $script:countLabel.ForeColor = $script:colors.error
        $script:countLabel.Text = $script:L.StatusFailed -f $err
        $script:searchBox.Focus()
        return
    }
    
    $box = $script:searchBox
    if ($box -and -not $box.IsDisposed) {
        # Bring our window forward
        try { $script:form.Activate() } catch { }
        $box.Text = $Item.Name
        $box.SelectionStart = $box.Text.Length
        $box.SelectionLength = 0
        $box.Focus()
    }
}

# ---------------------------------------------------------------- dialogs (F1/F2)
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $script:L.HelpTitle
    $dlg.Size            = New-Object System.Drawing.Size(560, 500)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = $script:colors.bg
    $dlg.ForeColor       = $script:colors.text
    $dlg.Font            = $script:fontName

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $layout.Padding     = New-Object System.Windows.Forms.Padding(16)
    $layout.ColumnCount = 1
    $layout.RowCount    = 3
    
    $stylePercent = [System.Windows.Forms.SizeType]::Percent
    $styleAbs     = [System.Windows.Forms.SizeType]::Absolute
    
    [void]$layout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle($stylePercent, 100))
    )
    [void]$layout.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle($styleAbs, 270))
    )
    [void]$layout.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle($stylePercent, 100))
    )
    [void]$layout.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle($styleAbs, 44))
    )
    $dlg.Controls.Add($layout)

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $listView.View          = 'Details'
    $listView.HeaderStyle   = 'None'
    $listView.FullRowSelect = $true
    $listView.BorderStyle   = 'FixedSingle'
    $listView.BackColor     = $script:colors.bg
    $listView.ForeColor     = $script:colors.text
    $listView.Font          = New-Object System.Drawing.Font('Segoe UI', 10)
    $listView.TabStop       = $false
    
    [void]$listView.Columns.Add('Key', 120)
    [void]$listView.Columns.Add('Action', 380)

    $shortcuts = @(
        @($script:L.KeyType,   $script:L.ActType),
        @($script:L.KeyUpDown, $script:L.ActUpDown),
        @($script:L.KeyEnter,  $script:L.ActEnter),
        @($script:L.KeyEsc,    $script:L.ActEsc),
        @($script:L.KeyF1,     $script:L.ActF1),
        @($script:L.KeyF2,     $script:L.ActF2),
        @($script:L.KeyF3,     $script:L.ActF3),
        @($script:L.KeyF4,     $script:L.ActF4),
        @($script:L.KeyF5,     $script:L.ActF5),
        @($script:L.KeyAltF4,  $script:L.ActAltF4)
    )
    
    foreach ($s in $shortcuts) {
        $item = New-Object System.Windows.Forms.ListViewItem($s[0])
        [void]$item.SubItems.Add($s[1])
        [void]$listView.Items.Add($item)
    }
    [void]$layout.Controls.Add($listView, 0, 0)

    $notes = New-Object System.Windows.Forms.TextBox
    $notes.Multiline   = $true
    $notes.ReadOnly    = $true
    $notes.ScrollBars  = 'Vertical'
    $notes.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $notes.BorderStyle = 'None'
    $notes.BackColor   = $script:colors.bg
    $notes.ForeColor   = $script:colors.muted
    $notes.Font        = New-Object System.Drawing.Font('Segoe UI', 9)
    $notes.TabStop     = $false
    $notes.Margin      = New-Object System.Windows.Forms.Padding(4, 12, 4, 12)
    
    $notesRaw = @"
$($script:L.HelpSearch)
  $($script:L.HelpSearchDesc)

$($script:L.HelpLaunch)
  $($script:L.HelpLaunchDesc)

$($script:L.HelpFiles)
  $($script:L.HelpLog) $($script:LogPath)
  $($script:L.HelpConfig) $($script:SettingsPath)
"@
    $notes.Text = $notesRaw -replace "`r`n", "`n" -replace "`n", "`r`n"
    [void]$layout.Controls.Add($notes, 0, 1)

    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnRow.FlowDirection = 'RightToLeft'
    $btnRow.AutoSize      = $true
    $btnRow.WrapContents  = $false
    $btnRow.Dock          = [System.Windows.Forms.DockStyle]::Fill
    
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text         = $script:L.BtnOK
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOK.Width        = 80
    
    [void]$btnRow.Controls.Add($btnOK)
    [void]$layout.Controls.Add($btnRow, 0, 2)

    $dlg.AcceptButton = $btnOK
    $dlg.CancelButton = $btnOK
    
    [void]$dlg.ShowDialog($script:form)
    $dlg.Dispose()
}

function Invoke-Help {
    Show-HelpDialog
    if ($script:searchBox -and -not $script:searchBox.IsDisposed) {
        $script:searchBox.Focus()
    }
}

function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $script:L.SettingsTitle
    $dlg.Size            = New-Object System.Drawing.Size(560, 740)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = $script:colors.bg
    $dlg.ForeColor       = $script:colors.text
    $dlg.Font            = $script:fontName

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $layout.Padding     = New-Object System.Windows.Forms.Padding(16)
    $layout.ColumnCount = 1
    $layout.RowCount    = 5
    
    $stylePercent = [System.Windows.Forms.SizeType]::Percent
    $styleAuto    = [System.Windows.Forms.SizeType]::AutoSize
    
    [void]$layout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle($stylePercent, 100))
    )
    for ($i = 0; $i -lt 5; $i++) {
        [void]$layout.RowStyles.Add(
            (New-Object System.Windows.Forms.RowStyle($styleAuto))
        )
    }
    $dlg.Controls.Add($layout)

    function New-SectionLabel {
        param([string]$Text)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Text
        $l.AutoSize = $true
        $l.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $l.ForeColor = $script:colors.accent
        $l.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 4)
        return $l
    }
    
    function New-Check {
        param([string]$Text, [bool]$Checked)
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $Text
        $c.Checked = $Checked
        $c.AutoSize = $true
        $c.ForeColor = $script:colors.text
        $c.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
        return $c
    }

    $colSection = New-Object System.Windows.Forms.FlowLayoutPanel
    $colSection.FlowDirection = 'TopDown'
    $colSection.AutoSize = $true
    $colSection.WrapContents = $false
    
    [void]$colSection.Controls.Add((New-SectionLabel $script:L.SecCollections))
    
    $chkDesktop  = New-Check $script:L.ColDesktop       $script:Settings.IncludeDesktop
    $chkTaskbar  = New-Check $script:L.ColTaskbar       $script:Settings.IncludeTaskbar
    $chkStartLnk = New-Check $script:L.ColStartLnk      $script:Settings.IncludeStartMenuLnk
    $chkStartAp  = New-Check $script:L.ColStartApps     $script:Settings.IncludeStartApps
    $chkAppPaths = New-Check $script:L.ColAppPaths      $script:Settings.IncludeAppPaths
    $chkTools    = New-Check $script:L.ColTools         $script:Settings.IncludeSystemTools
    $chkSettings = New-Check $script:L.ColSettings      $script:Settings.IncludeSettingsPages
    
    $chkDocsText = if ($script:L.ColDocuments) { $script:L.ColDocuments } else { "Documents" }
    $chkMediaText = if ($script:L.ColMultimedia) { $script:L.ColMultimedia } else { "Multimedia" }
    $chkDocs     = New-Check $chkDocsText               $script:Settings.IncludeDocuments
    $chkMedia    = New-Check $chkMediaText              $script:Settings.IncludeMultimedia
    
    $checkboxes = @(
        $chkDesktop, $chkTaskbar, $chkStartLnk, $chkStartAp, 
        $chkAppPaths, $chkTools, $chkSettings, $chkDocs, $chkMedia
    )
    foreach ($c in $checkboxes) { [void]$colSection.Controls.Add($c) }
    [void]$layout.Controls.Add($colSection, 0, 0)

    $searchSection = New-Object System.Windows.Forms.FlowLayoutPanel
    $searchSection.FlowDirection = 'TopDown'
    $searchSection.AutoSize = $true
    $searchSection.WrapContents = $false
    
    [void]$searchSection.Controls.Add((New-SectionLabel $script:L.SecSearch))
    
    $chkAlt = New-Check $script:L.OptAltNames $script:Settings.SearchAltNames
    [void]$searchSection.Controls.Add($chkAlt)
    [void]$layout.Controls.Add($searchSection, 0, 1)

    $voiceSection = New-Object System.Windows.Forms.FlowLayoutPanel
    $voiceSection.FlowDirection = 'TopDown'
    $voiceSection.AutoSize = $true
    $voiceSection.WrapContents = $false
    
    [void]$voiceSection.Controls.Add((New-SectionLabel $script:L.SecVoice))
    
    $voiceRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $voiceRow.FlowDirection = 'LeftToRight'
    $voiceRow.AutoSize = $true
    $voiceRow.WrapContents = $false
    $voiceRow.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    
    $voiceLbl = New-Object System.Windows.Forms.Label
    $voiceLbl.Text = $script:L.VoiceLang
    $voiceLbl.AutoSize = $true
    $voiceLbl.Margin = New-Object System.Windows.Forms.Padding(0, 6, 8, 0)
    $voiceLbl.ForeColor = $script:colors.text
    [void]$voiceRow.Controls.Add($voiceLbl)
    
    $cboVoice = New-Object System.Windows.Forms.ComboBox
    $cboVoice.DropDownStyle = 'DropDownList'
    $cboVoice.Width = 180
    $cboVoice.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    
    $installedCultures = @()
    try {
        $recognizers = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
        $installedCultures = $recognizers | ForEach-Object { $_.Culture.Name } | Select-Object -Unique
    } catch { }
    
    if ($installedCultures.Count -eq 0) {
        [void]$cboVoice.Items.Add($script:L.VoiceNoRecognizers)
        $cboVoice.SelectedIndex = 0
        $cboVoice.Enabled = $false
    } else {
        foreach ($c in $installedCultures) { [void]$cboVoice.Items.Add($c) }
        if ($installedCultures -contains $script:Settings.VoiceCulture) {
            $cboVoice.SelectedItem = $script:Settings.VoiceCulture
        } else {
            $cboVoice.SelectedIndex = 0
        }
    }
    [void]$voiceRow.Controls.Add($cboVoice)
    [void]$voiceSection.Controls.Add($voiceRow)
    [void]$layout.Controls.Add($voiceSection, 0, 2)

    $appearanceSection = New-Object System.Windows.Forms.FlowLayoutPanel
    $appearanceSection.FlowDirection = 'TopDown'
    $appearanceSection.AutoSize = $true
    $appearanceSection.WrapContents = $false
    
    [void]$appearanceSection.Controls.Add((New-SectionLabel $script:L.SecAppearance))
    
    # Theme Row
    $themeRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $themeRow.FlowDirection = 'LeftToRight'
    $themeRow.AutoSize = $true
    $themeRow.WrapContents = $false
    $themeRow.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    
    $themeLbl = New-Object System.Windows.Forms.Label
    $themeLbl.Text = $script:L.ThemeLabel
    $themeLbl.AutoSize = $false
    $themeLbl.Width = 70
    $themeLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $themeLbl.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
    $themeLbl.ForeColor = $script:colors.text
    [void]$themeRow.Controls.Add($themeLbl)
    
    $cboTheme = New-Object System.Windows.Forms.ComboBox
    $cboTheme.DropDownStyle = 'DropDownList'
    $cboTheme.Width = 180
    $cboTheme.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    
    [void]$cboTheme.Items.Add($script:L.ThemeSystem)
    [void]$cboTheme.Items.Add($script:L.ThemeLight)
    [void]$cboTheme.Items.Add($script:L.ThemeDark)
    
    if ($script:Settings.Theme -eq 'System') {
        $cboTheme.SelectedIndex = 0
    } elseif ($script:Settings.Theme -eq 'Light') {
        $cboTheme.SelectedIndex = 1
    } elseif ($script:Settings.Theme -eq 'Dark') {
        $cboTheme.SelectedIndex = 2
    } else {
        $cboTheme.SelectedIndex = 0
    }
    
    [void]$themeRow.Controls.Add($cboTheme)
    [void]$appearanceSection.Controls.Add($themeRow)

    # Opacity Row
    $opacityRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $opacityRow.FlowDirection = 'LeftToRight'
    $opacityRow.AutoSize = $true
    $opacityRow.WrapContents = $false
    $opacityRow.Margin = New-Object System.Windows.Forms.Padding(8, 6, 0, 0)
    
    $opacityLbl = New-Object System.Windows.Forms.Label
    $opacityLbl.Text = $script:L.OpacityLabel
    $opacityLbl.AutoSize = $false
    $opacityLbl.Width = 70
    $opacityLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $opacityLbl.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
    $opacityLbl.ForeColor = $script:colors.text
    [void]$opacityRow.Controls.Add($opacityLbl)
    
    $opacitySlider = New-Object System.Windows.Forms.TrackBar
    $opacitySlider.Minimum = 30
    $opacitySlider.Maximum = 100
    $opacitySlider.TickFrequency = 10
    $opacitySlider.SmallChange = 5
    $opacitySlider.LargeChange = 10
    $opacitySlider.Width = 180
    $opacitySlider.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    
    $initialPct = [int][Math]::Round((Clamp-Opacity -Value $script:Settings.Opacity) * 100)
    if ($initialPct -lt 30)  { $initialPct = 30 }
    if ($initialPct -gt 100) { $initialPct = 100 }
    $opacitySlider.Value = $initialPct
    [void]$opacityRow.Controls.Add($opacitySlider)
    
    $opacityValue = New-Object System.Windows.Forms.Label
    $opacityValue.Text = "$initialPct%"
    $opacityValue.AutoSize = $true
    $opacityValue.Width = 48
    $opacityValue.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $opacityValue.ForeColor = $script:colors.accent
    $opacityValue.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    [void]$opacityRow.Controls.Add($opacityValue)
    
    $opacitySlider.Tag = $opacityValue
    $opacitySlider.Add_ValueChanged({
        param($sender, $e)
        $pct = $sender.Value
        $lbl = $sender.Tag
        if ($lbl -and -not $lbl.IsDisposed) { $lbl.Text = "$pct%" }
        if ($script:form -and -not $script:form.IsDisposed) {
            try { $script:form.Opacity = ($pct / 100.0) } catch { }
        }
    })
    [void]$appearanceSection.Controls.Add($opacityRow)

    # UI Language Row
    $langRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $langRow.FlowDirection = 'LeftToRight'
    $langRow.AutoSize = $true
    $langRow.WrapContents = $false
    $langRow.Margin = New-Object System.Windows.Forms.Padding(8, 6, 0, 0)
    
    $langLbl = New-Object System.Windows.Forms.Label
    $langLbl.Text = $script:L.UILangLabel
    $langLbl.AutoSize = $false
    $langLbl.Width = 70
    $langLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $langLbl.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
    $langLbl.ForeColor = $script:colors.text
    [void]$langRow.Controls.Add($langLbl)
    
    $cboLang = New-Object System.Windows.Forms.ComboBox
    $cboLang.DropDownStyle = 'DropDownList'
    $cboLang.Width = 180
    $cboLang.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    
    # Locolization
    [void]$cboLang.Items.Add($script:L.UILangSystem)
    [void]$cboLang.Items.Add('English')
    [void]$cboLang.Items.Add('简体中文')
    [void]$cboLang.Items.Add('日本語')
    [void]$cboLang.Items.Add('বাংলা')
    
    $curLang = if ($script:Settings.UILanguage) { [string]$script:Settings.UILanguage } else { 'System' }
    if ($curLang -eq 'System') { $cboLang.SelectedIndex = 0 }
    elseif ($curLang -eq 'en-US') { $cboLang.SelectedIndex = 1 }
    elseif ($curLang -eq 'zh-CN') { $cboLang.SelectedIndex = 2 }
    elseif ($curLang -eq 'ja-JP') { $cboLang.SelectedIndex = 3 }
    elseif ($curLang -eq 'bn-BD') { $cboLang.SelectedIndex = 4 }
    else { $cboLang.SelectedIndex = 0 }
    
    [void]$langRow.Controls.Add($cboLang)
    [void]$appearanceSection.Controls.Add($langRow)
    [void]$layout.Controls.Add($appearanceSection, 0, 3)

    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnRow.FlowDirection = 'RightToLeft'
    $btnRow.AutoSize = $true
    $btnRow.WrapContents = $false
    $btnRow.Dock = [System.Windows.Forms.DockStyle]::Fill
    $btnRow.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 0)
    
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = $script:L.BtnOK
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOK.Width = 80
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = $script:L.BtnCancel
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Width = 80
    
    [void]$btnRow.Controls.Add($btnOK)
    [void]$btnRow.Controls.Add($btnCancel)
    [void]$layout.Controls.Add($btnRow, 0, 4)
    
    $dlg.AcceptButton = $btnOK
    $dlg.CancelButton = $btnCancel

    $result = $dlg.ShowDialog($script:form)
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:Settings.IncludeDesktop       = $chkDesktop.Checked
        $script:Settings.IncludeTaskbar       = $chkTaskbar.Checked
        $script:Settings.IncludeStartMenuLnk  = $chkStartLnk.Checked
        $script:Settings.IncludeStartApps     = $chkStartAp.Checked
        $script:Settings.IncludeAppPaths      = $chkAppPaths.Checked
        $script:Settings.IncludeSystemTools   = $chkTools.Checked
        $script:Settings.IncludeSettingsPages = $chkSettings.Checked
        $script:Settings.IncludeDocuments     = $chkDocs.Checked
        $script:Settings.IncludeMultimedia    = $chkMedia.Checked
        $script:Settings.SearchAltNames       = $chkAlt.Checked
        
        if ($cboVoice.Enabled -and $cboVoice.SelectedItem) {
            $script:Settings.VoiceCulture = [string]$cboVoice.SelectedItem
        }
        
        if ($cboTheme.SelectedIndex -eq 0) {
            $script:Settings.Theme = 'System'
        } elseif ($cboTheme.SelectedIndex -eq 1) {
            $script:Settings.Theme = 'Light'
        } elseif ($cboTheme.SelectedIndex -eq 2) {
            $script:Settings.Theme = 'Dark'
        }
        
        # Locolization
        $oldLang = $script:Settings.UILanguage
        $newLang = 'System'
        if ($cboLang.SelectedIndex -eq 1) { $newLang = 'en-US' }
        elseif ($cboLang.SelectedIndex -eq 2) { $newLang = 'zh-CN' }
        elseif ($cboLang.SelectedIndex -eq 3) { $newLang = 'ja-JP' }
        elseif ($cboLang.SelectedIndex -eq 4) { $newLang = 'bn-BD' }
        $script:Settings.UILanguage = $newLang
        
        $langChanged = ($newLang -ne $oldLang)
        
        Apply-Opacity -Value ($opacitySlider.Value / 100.0)
        Save-Settings
        Apply-Theme -ThemeName $script:Settings.Theme
        Build-Index
        Update-Results $script:searchBox.Text
        Reset-Voice
        Update-VoiceUi
        Write-Log "Settings: applied"
        
        if ($langChanged) {
            $msg = $script:L.UILangRestart
            [void][System.Windows.Forms.MessageBox]::Show($msg, $script:L.AppTitle, 'OK', 'Information')
        }
    } else {
        if ($script:form -and -not $script:form.IsDisposed) {
            try {
                $orig = Clamp-Opacity -Value $script:Settings.Opacity
                $script:form.Opacity = $orig
            } catch { }
        }
        Write-Log "Settings: cancelled"
    }
    $dlg.Dispose()
}

function Invoke-Settings {
    Show-SettingsDialog
    if ($script:searchBox -and -not $script:searchBox.IsDisposed) {
        $script:searchBox.Focus()
    }
}

# ---------------------------------------------------------------- F3: Desktop Icons
function Toggle-DesktopIcons {
    if (-not $script:DesktopIconsAvailable) {
        Write-Log "Desktop icons: P/Invoke unavailable" -Level WARN
        return
    }
    try {
        $progman = [Native.DesktopIcons]::FindWindow('Progman', $null)
        $defView = [IntPtr]::Zero
        
        if ($progman -ne [IntPtr]::Zero) {
            $defView = [Native.DesktopIcons]::FindWindowEx(
                $progman, [IntPtr]::Zero, 'SHELLDLL_DefView', $null
            )
        }
        
        if ($defView -eq [IntPtr]::Zero) {
            $worker = [IntPtr]::Zero
            do {
                $worker = [Native.DesktopIcons]::FindWindowEx(
                    [IntPtr]::Zero, $worker, 'WorkerW', $null
                )
                if ($worker -ne [IntPtr]::Zero) {
                    $defView = [Native.DesktopIcons]::FindWindowEx(
                        $worker, [IntPtr]::Zero, 'SHELLDLL_DefView', $null
                    )
                }
            } while ($defView -eq [IntPtr]::Zero -and $worker -ne [IntPtr]::Zero)
        }
        
        if ($defView -ne [IntPtr]::Zero) {
            [void][Native.DesktopIcons]::SendMessage(
                $defView, 0x0111, [IntPtr]0x7402, [IntPtr]::Zero
            )
            Write-Log "Desktop icons: toggled"
        } else {
            Write-Log "Desktop icons: SHELLDLL_DefView not found" -Level WARN
        }
    } catch {
        Write-Log "Desktop icons toggle failed: $($_.Exception.Message)" -Level ERROR
    }
}

# ---------------------------------------------------------------- F4: Voice Input
$script:VoiceAvailable = $false
$script:VoiceListening = $false
$script:Recognizer     = $null
$script:VoiceSub       = $null
$script:VoiceSubRej    = $null
$script:VoiceQueue     = [System.Collections.Queue]::Synchronized(
    (New-Object System.Collections.Queue)
)

function Initialize-Voice {
    param([System.Collections.Queue]$Queue, [string[]]$ShortcutNames, [string]$CultureName)
    try {
        if (-not $CultureName) { $CultureName = 'en-US' }
        $culture = New-Object System.Globalization.CultureInfo($CultureName)
        $recognizerInfo = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() |
                          Where-Object { $_.Culture.Name -eq $culture.Name } |
                          Select-Object -First 1
        
        if (-not $recognizerInfo) { throw "No '$CultureName' speech recognizer installed." }

        $r = New-Object System.Speech.Recognition.SpeechRecognitionEngine($recognizerInfo)
        $r.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
        
        if ($ShortcutNames -and $ShortcutNames.Count -gt 0) {
            try {
                $choices = New-Object System.Speech.Recognition.Choices
                foreach ($n in $ShortcutNames) {
                    if ($n) { [void]$choices.Add([string]$n) }
                }
                $gb = New-Object System.Speech.Recognition.GrammarBuilder
                $gb.Culture = $culture
                $gb.Append($choices)
                $r.LoadGrammar((New-Object System.Speech.Recognition.Grammar($gb)))
            } catch { }
        }
        
        $r.SetInputToDefaultAudioDevice()
        
        $script:VoiceSub = Register-ObjectEvent -InputObject $r -EventName SpeechRecognized -MessageData $Queue -Action {
            try {
                $t = $Event.SourceEventArgs.Result.Text
                if ($t) { $Event.MessageData.Enqueue($t) }
            } catch { }
        }
        $script:VoiceSubRej = Register-ObjectEvent -InputObject $r -EventName SpeechRecognitionRejected -Action { }
        
        $script:Recognizer = $r
        $script:VoiceAvailable = $true
        return $true
    } catch {
        $script:VoiceAvailable = $false
        Write-Log "Voice init failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Start-VoiceListen {
    if (-not $script:VoiceAvailable -or $script:VoiceListening) { return }
    try {
        $script:Recognizer.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)
        $script:VoiceListening = $true
    } catch { }
}

function Stop-VoiceListen {
    if (-not $script:VoiceAvailable -or -not $script:VoiceListening) { return }
    try { $script:Recognizer.RecognizeAsyncCancel() } catch { }
    $script:VoiceListening = $false
}

function Reset-Voice {
    Stop-VoiceListen
    if ($script:VoiceSub)    {
        Unregister-Event -SourceIdentifier $script:VoiceSub.Name -ErrorAction SilentlyContinue
    }
    if ($script:VoiceSubRej) {
        Unregister-Event -SourceIdentifier $script:VoiceSubRej.Name -ErrorAction SilentlyContinue
    }
    if ($script:Recognizer)  { try { $script:Recognizer.Dispose() } catch { } }
    
    $script:VoiceSub = $null
    $script:VoiceSubRej = $null
    $script:Recognizer = $null
    $script:VoiceAvailable = $false
    $script:VoiceListening = $false
    
    while ($script:VoiceQueue.Count -gt 0) { [void]$script:VoiceQueue.Dequeue() }
    
    [void](Initialize-Voice `
        -Queue $script:VoiceQueue `
        -ShortcutNames $script:voiceGrammarNames `
        -CultureName $script:Settings.VoiceCulture)
}

function Add-VoiceText {
    param([string]$Text)
    $t = $Text.Trim()
    if ($t.Length -eq 0) { return }
    
    $box = $script:searchBox
    if (-not $box -or $box.IsDisposed) { return }
    
    $pos = $box.SelectionStart
    $box.Text = $box.Text.Insert($pos, $t)
    $box.SelectionStart = $pos + $t.Length
    $box.SelectionLength = 0
    $box.Focus()
}

function Update-VoiceUi {
    if (-not $script:VoiceAvailable) {
        $script:form.Text = $script:L.AppTitle
        if ($script:promptIcon) {
            $script:promptIcon.Text = [char]::ConvertFromUtf32(0x1F50E) # Magnifying glass
            $script:promptIcon.ForeColor = $script:colors.muted
        }
        return
    }
    
    if ($script:VoiceListening) {
        $script:form.Text = $script:L.AppListening
        if ($script:promptIcon) {
            $script:promptIcon.Text = [char]::ConvertFromUtf32(0x1F399) + [char]::ConvertFromUtf32(0xFE0F) # Mic
            $script:promptIcon.ForeColor = $script:colors.accent
        }
    } else {
        $script:form.Text = $script:L.AppTitle
        if ($script:promptIcon) {
            $script:promptIcon.Text = [char]::ConvertFromUtf32(0x1F50E)# Magnifying glass
            $script:promptIcon.ForeColor = $script:colors.muted
        }
    }
}

function Invoke-VoiceInput {
    if (-not $script:VoiceAvailable) { return }
    
    if ($script:VoiceListening) {
        Stop-VoiceListen
        Write-Log "Voice: stopped (F4)"
    } else {
        Start-VoiceListen
        Write-Log "Voice: started (F4)"
    }
    Update-VoiceUi
}

# ---------------------------------------------------------------- F5: Refresh Index
function Invoke-Refresh {
    Write-Log "Refresh requested (F5)"
    $script:countLabel.Text = $script:L.StatusRefreshing
    $script:countLabel.ForeColor = $script:colors.accent
    [System.Windows.Forms.Application]::DoEvents()
    
    Build-Index
    Update-Results $script:searchBox.Text
    Reset-Voice
    Update-VoiceUi
}

# ---------------------------------------------------------------- visuals & index
function Apply-Opacity {
    param($Value)
    $v = Clamp-Opacity -Value $Value
    $script:Settings.Opacity = $v
    if ($script:form -and -not $script:form.IsDisposed) {
        $script:form.Opacity = $v
    }
    Write-Log "Opacity: applied $v"
}

function Apply-Theme {
    param([string]$ThemeName)
    $effective = Resolve-Theme -Theme $ThemeName
    $script:EffectiveTheme = $effective
    $script:colors = Get-ThemePalette -Effective $effective
    
    if (-not $script:form -or $script:form.IsDisposed) { return }

    $script:form.BackColor = $script:colors.bg
    $script:form.ForeColor = $script:colors.text
    
    if ($script:container)   { $script:container.BackColor = $script:colors.bg }
    if ($script:searchPanel) { $script:searchPanel.BackColor = $script:colors.surface }
    
    if ($script:searchBox)   {
        $script:searchBox.BackColor = $script:colors.surface
        $script:searchBox.ForeColor = $script:colors.text
    }
    
    if ($script:settingsButton) { 
        $script:settingsButton.BackColor = $script:colors.surface
        $script:settingsButton.ForeColor = $script:colors.muted 
    }
    
    if ($script:optPanel) { $script:optPanel.BackColor = $script:colors.surface }
    if ($script:btnCase) { 
        $script:btnCase.BackColor = $script:colors.surface
        $script:btnCase.ForeColor = if ($script:Settings.MatchCase) { $script:colors.accent } else { $script:colors.muted }
    }
    if ($script:btnWord) { 
        $script:btnWord.BackColor = $script:colors.surface
        $script:btnWord.ForeColor = if ($script:Settings.MatchWholeWord) { $script:colors.accent } else { $script:colors.muted }
    }
    if ($script:btnRegex) { 
        $script:btnRegex.BackColor = $script:colors.surface
        $script:btnRegex.ForeColor = if ($script:Settings.MatchRegex) { $script:colors.accent } else { $script:colors.muted }
    }
    
    if ($script:promptIcon) {
        $script:promptIcon.BackColor = $script:colors.surface
        if ($script:VoiceAvailable -and $script:VoiceListening) {
            $script:promptIcon.ForeColor = $script:colors.accent
        } else {
            $script:promptIcon.ForeColor = $script:colors.muted
        }
    }
    
    if ($script:listBox) {
        $script:listBox.BackColor = $script:colors.bg
        $script:listBox.ForeColor = $script:colors.text
    }
    
    if ($script:footer)      { $script:footer.BackColor = $script:colors.bg }
    if ($script:countLabel)  { $script:countLabel.ForeColor = $script:colors.muted }

    try { if ($script:searchPanel) { $script:searchPanel.Invalidate() } } catch { }
    try { if ($script:listBox)    { $script:listBox.Invalidate()    } } catch { }
    
    Write-Log "Theme: applied requested='$ThemeName' effective='$effective'"
}

function Build-Index {
    $desktopPaths = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    ) | Where-Object { $_ } | Select-Object -Unique
    
    $taskbarPath = Join-Path $env:APPDATA `
        'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    
    $startMenuPaths = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    $script:ItemsFiltered = 0
    $all = @()

    if ($script:Settings.IncludeDesktop) {
        $all += @(Get-Shortcuts -Paths $desktopPaths)
    }
    if ($script:Settings.IncludeTaskbar) {
        $all += @(Get-Shortcuts -Paths @($taskbarPath))
    }
    if ($script:Settings.IncludeStartMenuLnk) {
        $all += @(Get-Shortcuts -Paths $startMenuPaths)
    }
    if ($script:Settings.IncludeStartApps) {
        $all += @(Get-StartMenuApps)
    }
    if ($script:Settings.IncludeAppPaths) {
        $all += @(Get-AppPathCommands)
    }
    if ($script:Settings.IncludeSystemTools) {
        $all += @(Get-SystemTools)
    }
    if ($script:Settings.IncludeSettingsPages) {
        $all += @(Get-SettingsPages)
    }

    $rawCount = $all.Count
    $seen = @{}
    $dupCount = 0
    $deduped = New-Object System.Collections.ArrayList
    
    foreach ($s in $all) {
        if (-not $s) { continue }
        if ($s.PSObject.Properties['IsExcluded'] -and $s.IsExcluded) { continue }
        if (Test-IsExcludedTarget $s.Target) { continue }
        
        $key = $s.Name.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$deduped.Add($s)
        } else {
            $dupCount++
        }
    }
    $script:shortcuts = @($deduped | Sort-Object Name)

    $voiceNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($r in $script:shortcuts) {
        if ($r.Name) { $voiceNames.Add($r.Name) }
        if ($script:Settings.SearchAltNames -and
            $r.PSObject.Properties['AltNames'] -and $r.AltNames) {
            foreach ($a in $r.AltNames) { if ($a) { $voiceNames.Add($a) } }
        }
    }
    $script:voiceGrammarNames = @($voiceNames | Select-Object -Unique)
    Write-Log "Index: raw=$rawCount files_filtered=$($script:ItemsFiltered) duplicates_dropped=$dupCount indexed=$($script:shortcuts.Count)"
}

# ---------------------------------------------------------------- window
$script:form = New-Object System.Windows.Forms.Form
$form = $script:form
$form.Text            = $script:L.AppTitle
$form.Size            = New-Object System.Drawing.Size(680, 500)
$form.MinimumSize     = New-Object System.Drawing.Size(480, 320)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox     = $true
$form.MinimizeBox     = $true
$form.BackColor       = $script:colors.bg
$form.ForeColor       = $script:colors.text
$form.ShowInTaskbar   = $true
$form.KeyPreview      = $true
$form.TabStop         = $false
$form.Opacity         = Clamp-Opacity -Value $script:Settings.Opacity

$container = New-Object System.Windows.Forms.TableLayoutPanel
$container.Dock        = [System.Windows.Forms.DockStyle]::Fill
$container.Padding     = New-Object System.Windows.Forms.Padding(20, 18, 20, 16)
$container.BackColor   = $script:colors.bg
$container.ColumnCount = 1
$container.RowCount    = 3
$container.TabStop     = $false

$stylePercent = [System.Windows.Forms.SizeType]::Percent
$styleAbs     = [System.Windows.Forms.SizeType]::Absolute

[void]$container.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle($stylePercent, 100))
)
[void]$container.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle($styleAbs, 66))
)
[void]$container.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle($stylePercent, 100))
)
[void]$container.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle($styleAbs, 28))
)
$form.Controls.Add($container)
$script:container = $container

# --- footer (row 2) -----------------------------------------------------
$footer = New-Object System.Windows.Forms.TableLayoutPanel
$footer.Dock        = [System.Windows.Forms.DockStyle]::Fill
$footer.BackColor   = $script:colors.bg
$footer.ColumnCount = 1
$footer.RowCount    = 1
$footer.TabStop     = $false

[void]$footer.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle($stylePercent, 100))
)
[void]$footer.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle($stylePercent, 100))
)
$script:footer = $footer

$countLabel = New-Object System.Windows.Forms.Label
$countLabel.Dock      = [System.Windows.Forms.DockStyle]::Fill
$countLabel.TextAlign = 'MiddleLeft'
$countLabel.ForeColor = $script:colors.muted
$countLabel.Font      = $script:fontHint
$countLabel.TabStop   = $false
$countLabel.Text      = $script:L.StatusIndexed -f 0
$script:countLabel    = $countLabel

[void]$footer.Controls.Add($countLabel, 0, 0)


# --- search field (row 0) ----------------------------------------------
$searchPanel = New-Object System.Windows.Forms.TableLayoutPanel
$searchPanel.Dock        = [System.Windows.Forms.DockStyle]::Fill
$searchPanel.BackColor   = $script:colors.surface
$searchPanel.Padding     = New-Object System.Windows.Forms.Padding(2)
$searchPanel.Margin      = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
$searchPanel.ColumnCount = 4
$searchPanel.RowCount    = 1
$searchPanel.TabStop     = $false

[void]$searchPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle($styleAbs, 40))
)
[void]$searchPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle($stylePercent, 100))
)
[void]$searchPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle($styleAbs, 112))
)
[void]$searchPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle($styleAbs, 40))
)
[void]$searchPanel.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle($stylePercent, 100))
)
$script:searchPanel = $searchPanel

$promptIcon = New-Object System.Windows.Forms.TextBox
$promptIcon.Dock      = [System.Windows.Forms.DockStyle]::Fill
$promptIcon.Margin    = New-Object System.Windows.Forms.Padding(0, 8, 0, 8)
$promptIcon.Multiline = $false
$promptIcon.ReadOnly  = $true
$promptIcon.BorderStyle = 'None'
$promptIcon.TextAlign = 'Center'
$promptIcon.Text      = [char]::ConvertFromUtf32(0x1F50E)  # Magnifying glass
$promptIcon.Font      = New-Object System.Drawing.Font('Segoe UI Emoji', 15)
$promptIcon.BackColor = $script:colors.surface
$promptIcon.ForeColor = $script:colors.muted
$promptIcon.TabStop   = $false
$script:promptIcon    = $promptIcon

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Dock        = [System.Windows.Forms.DockStyle]::Fill
$searchBox.Margin      = New-Object System.Windows.Forms.Padding(0, 8, 0, 8)
$searchBox.BorderStyle = 'None'
$searchBox.BackColor   = $script:colors.surface
$searchBox.ForeColor   = $script:colors.text
$searchBox.Font        = New-Object System.Drawing.Font('Segoe UI', 15)
$searchBox.TabStop     = $true
$script:searchBox = $searchBox

$settingsButton = New-Object System.Windows.Forms.Button
$settingsButton.Text      = [char]::ConvertFromUtf32(0x2699)  # Gear
$settingsButton.Dock      = [System.Windows.Forms.DockStyle]::Fill
$settingsButton.FlatStyle = 'Flat'
$settingsButton.FlatAppearance.BorderSize = 0
$settingsButton.BackColor = $script:colors.surface
$settingsButton.ForeColor = $script:colors.muted
$settingsButton.Font      = New-Object System.Drawing.Font('Segoe UI Symbol', 22)
$settingsButton.TabStop   = $false
$settingsButton.Cursor    = [System.Windows.Forms.Cursors]::Hand
$script:settingsButton    = $settingsButton

$script:tooltip = New-Object System.Windows.Forms.ToolTip
$script:tooltip.ShowAlways   = $true
$script:tooltip.InitialDelay = 300
$script:tooltip.ReshowDelay  = 100

$script:tooltip.SetToolTip($settingsButton, $script:L.TooltipSettings)

function New-OptButton {
    param($text, $tooltip, $checked, $fontStyle)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Width = 30
    $btn.Height = 28
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $script:colors.surface
    $btn.ForeColor = if ($checked) { $script:colors.accent } else { $script:colors.muted }
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 10, $fontStyle)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.TabStop = $false
    $btn.Margin = New-Object System.Windows.Forms.Padding(0, 10, 2, 10)
    $btn.Padding = New-Object System.Windows.Forms.Padding(0)
    $script:tooltip.SetToolTip($btn, $tooltip)
    return $btn
}

$optPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$optPanel.Dock          = [System.Windows.Forms.DockStyle]::Fill
$optPanel.FlowDirection = 'RightToLeft'
$optPanel.WrapContents  = $false
$optPanel.BackColor     = $script:colors.surface
$optPanel.TabStop       = $false
$script:optPanel        = $optPanel

$script:btnCase = New-OptButton 'Aa' $script:L.TooltipCase $script:Settings.MatchCase ([System.Drawing.FontStyle]::Regular)
$script:btnCase.Add_Click({
    $script:Settings.MatchCase = -not $script:Settings.MatchCase
    $script:btnCase.ForeColor = if ($script:Settings.MatchCase) { $script:colors.accent } else { $script:colors.muted }
    Save-Settings
    Update-Results $script:searchBox.Text
    $script:searchBox.Focus()
})

$script:btnWord = New-OptButton 'ab' $script:L.TooltipWord $script:Settings.MatchWholeWord ([System.Drawing.FontStyle]::Underline)
$script:btnWord.Add_Click({
    $script:Settings.MatchWholeWord = -not $script:Settings.MatchWholeWord
    $script:btnWord.ForeColor = if ($script:Settings.MatchWholeWord) { $script:colors.accent } else { $script:colors.muted }
    Save-Settings
    Update-Results $script:searchBox.Text
    $script:searchBox.Focus()
})

$script:btnRegex = New-OptButton '.*' $script:L.TooltipRegex $script:Settings.MatchRegex ([System.Drawing.FontStyle]::Regular)
$script:btnRegex.Add_Click({
    $script:Settings.MatchRegex = -not $script:Settings.MatchRegex
    $script:btnRegex.ForeColor = if ($script:Settings.MatchRegex) { $script:colors.accent } else { $script:colors.muted }
    Save-Settings
    Update-Results $script:searchBox.Text
    $script:searchBox.Focus()
})

[void]$optPanel.Controls.Add($script:btnRegex)
[void]$optPanel.Controls.Add($script:btnWord)
[void]$optPanel.Controls.Add($script:btnCase)

[void]$searchPanel.Controls.Add($promptIcon,  0, 0)
[void]$searchPanel.Controls.Add($searchBox,   1, 0)
[void]$searchPanel.Controls.Add($optPanel,    2, 0)
[void]$searchPanel.Controls.Add($settingsButton, 3, 0)

$searchPanel.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($script:colors.accent, 2)
    try {
        $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1)
    } finally {
        $pen.Dispose()
    }
})

# --- results list (row 1) -----------------------------------------------
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Dock           = [System.Windows.Forms.DockStyle]::Fill
$listBox.BorderStyle    = 'None'
$listBox.BackColor      = $script:colors.bg
$listBox.ForeColor      = $script:colors.text
$listBox.DrawMode       = 'OwnerDrawFixed'
$listBox.ItemHeight     = 36
$listBox.IntegralHeight = $false
$listBox.Font           = $script:fontName
$listBox.TabStop        = $false
$script:listBox = $listBox

$listBox.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $sender.Items.Count) { return }
    
    $item     = $sender.Items[$e.Index]
    $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0

    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bg = if ($selected) { $script:colors.surface } else { $script:colors.bg }
    $bgBrush = New-Object System.Drawing.SolidBrush($bg)
    try {
        $g.FillRectangle($bgBrush, $e.Bounds)
    } finally {
        $bgBrush.Dispose()
    }

    if ($selected) {
        $barBrush = New-Object System.Drawing.SolidBrush($script:colors.accent)
        try {
            $g.FillRectangle($barBrush, $e.Bounds.Left, $e.Bounds.Top + 6, 3, $e.Bounds.Height - 12)
        } finally {
            $barBrush.Dispose()
        }
    }

    $nameColor = if ($selected) { $script:colors.accent } else { $script:colors.text }
    $nameBrush = New-Object System.Drawing.SolidBrush($nameColor)
    
    try {
        $nameRect = New-Object System.Drawing.RectangleF(
            ($e.Bounds.Left + 16),
            $e.Bounds.Top,
            ($e.Bounds.Width - 32),
            $e.Bounds.Height
        )
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $fmt.Trimming      = [System.Drawing.StringTrimming]::EllipsisCharacter
        $fmt.FormatFlags   = [System.Drawing.StringFormatFlags]::NoWrap
        
        $g.DrawString($item.Name, $script:fontName, $nameBrush, $nameRect, $fmt)
        $fmt.Dispose()
    } finally {
        $nameBrush.Dispose()
    }
})

$container.Controls.Add($searchPanel, 0, 0)
$container.Controls.Add($listBox,     0, 1)
$container.Controls.Add($footer,      0, 2)

# ---------------------------------------------------------------- events
$keepFocus = {
    if ($script:form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        return
    }
    $box = $script:searchBox
    if ($box -and -not $box.IsDisposed -and -not $box.Focused) {
        $box.Focus()
    }
}

$focusables = @($container, $searchPanel, $footer, $countLabel, $promptIcon, $listBox)
foreach ($c in $focusables) {
    if ($null -ne $c) { $c.Add_GotFocus($keepFocus) }
}

$searchBox.Add_TextChanged({ Update-Results $script:searchBox.Text })
$searchBox.Add_KeyDown({
    param($sender, $e)
    $lb = $script:listBox
    
    if ($lb.Items.Count -eq 0) { return }
    
    $currentIdx = if ($lb.SelectedIndex -ge 0) { $lb.SelectedIndex } else { 0 }

    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Down) {
        if ($lb.SelectedIndex -lt $lb.Items.Count - 1) {
            $lb.SelectedIndex++
        }
        $e.SuppressKeyPress = $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Up) {
        if ($lb.SelectedIndex -gt 0) {
            $lb.SelectedIndex--
        }
        $e.SuppressKeyPress = $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::PageUp -and $e.Ctrl) {
        $lb.SelectedIndex = 0
        $e.SuppressKeyPress = $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::PageDown -and $e.Ctrl) {
        $lb.SelectedIndex = $lb.Items.Count - 1
        $e.SuppressKeyPress = $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::PageDown) {
        $newIdx = $currentIdx + 10
        if ($newIdx -ge $lb.Items.Count) { $newIdx = $lb.Items.Count - 1 }
        $lb.SelectedIndex = $newIdx
        $e.SuppressKeyPress = $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::PageUp) {
        $newIdx = $currentIdx - 10
        if ($newIdx -lt 0) { $newIdx = 0 }
        $lb.SelectedIndex = $newIdx
        $e.SuppressKeyPress = $true
    }
})

$listBox.Add_MouseDown({
    param($sender, $e)
    $idx = $sender.IndexFromPoint($e.Location)
    if ($idx -ge 0) { $sender.SelectedIndex = $idx }
    $script:searchBox.Focus()
})

$listBox.Add_MouseDoubleClick({ Invoke-Selected -Item (Get-SelectedItem) })

$settingsButton.Add_Click({
    Invoke-Settings
    if ($script:searchBox -and -not $script:searchBox.IsDisposed) {
        $script:searchBox.Focus()
    }
})

$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $e.SuppressKeyPress = $true
        $box = $script:searchBox
        if ($box.Text.Length -gt 0) { $box.Clear() }
        $box.Focus()
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        if ($script:searchBox.Text.Length -gt 0) {
            Invoke-Selected -Item (Get-SelectedItem)
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F1 -and -not $e.Alt) {
        $e.SuppressKeyPress = $true
        Invoke-Help
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F2 -and -not $e.Alt) {
        $e.SuppressKeyPress = $true
        Invoke-Settings
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F3 -and -not $e.Alt) {
        $e.SuppressKeyPress = $true
        Toggle-DesktopIcons
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F4 -and -not $e.Alt) {
        $e.SuppressKeyPress = $true
        Invoke-VoiceInput
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5 -and -not $e.Alt) {
        $e.SuppressKeyPress = $true
        Invoke-Refresh
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Tab) {
        $e.SuppressKeyPress = $true
    }
})

# Activation events (raise-to-front, restore-from-taskbar).
$form.Add_Activated({
    if ($script:form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $script:form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $script:form.TopMost = $true
        $script:form.Activate()
        $script:form.TopMost = $false
    }
    $script:searchBox.Focus()
})

$form.Add_Shown({
    Update-Results ''
    Update-VoiceUi
    if (-not $script:VoiceAvailable) {
        $script:countLabel.ForeColor = $script:colors.error
        $script:countLabel.Text = $script:L.StatusVoiceUnavailable
    }
    $script:searchBox.Focus()
})

# ---------------------------------------------------------------- run
Build-Index
$voiceOk = Initialize-Voice `
    -Queue $script:VoiceQueue `
    -ShortcutNames $script:voiceGrammarNames `
    -CultureName $script:Settings.VoiceCulture

[void]$form.Show()

$script:RestoreHook = $null
if ($script:RestoreHookAvailable) {
    try {
        $script:RestoreHook = New-Object RestoreHook
        $script:RestoreHook.TargetForm = $form
        $script:RestoreHook.AssignHandle($form.Handle)
    } catch {
        $script:RestoreHook = $null
    }
}


while (-not $form.IsDisposed) {
    [System.Windows.Forms.Application]::DoEvents()
    
    if ($script:ActivateEvent -and $script:ActivateEvent.WaitOne(0)) {
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $form.TopMost = $true
        $form.Activate()
        $form.TopMost = $false
        $script:searchBox.Focus()
    }
    
    if ($script:VoiceListening) {
        while ($script:VoiceQueue.Count -gt 0) {
            $t = $script:VoiceQueue.Dequeue()
            if ($t) {
                Write-Log "Voice: recognized '$t'"
                Add-VoiceText -Text $t
            }
        }
    }
    Start-Sleep -Milliseconds 20
}

# ---------------------------------------------------------------- cleanup
if ($script:RestoreHook) {
    try { $script:RestoreHook.ReleaseHandle() } catch { }
}
if ($script:AppMutex) {
    try { $script:AppMutex.ReleaseMutex() } catch { }
    try { $script:AppMutex.Dispose() } catch { }
}
if ($script:ActivateEvent) {
    try { $script:ActivateEvent.Dispose() } catch { }
}

Stop-VoiceListen
if ($script:VoiceSub)    {
    Unregister-Event -SourceIdentifier $script:VoiceSub.Name -ErrorAction SilentlyContinue
}
if ($script:VoiceSubRej) {
    Unregister-Event -SourceIdentifier $script:VoiceSubRej.Name -ErrorAction SilentlyContinue
}
if ($script:Recognizer)  { try { $script:Recognizer.Dispose() } catch { } }
try { $form.Dispose() } catch { }

}
catch {
    try {
        [void][System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            $script:L.AppFatalError,
            'OK',
            'Error'
        )
    } catch { }
}