# Shortcut Launcher

A fast, keyboard-first launcher for Windows. Indexes desktop shortcuts, taskbar pins, Start-menu entries, UWP apps, System32 tools, Settings pages, and more — all searchable from a single hotkey.

## Features

- **Advanced Search**: Case-insensitive by default, with toggles for **Match Case** (`Aa`), **Whole Word** (`ab`), and **Regex** (`.*`).
- **Multilingual UI**: Fully translated into English, বাংলা (Bengali), 简体中文 (Chinese), and 日本語 (Japanese).
- **Voice Input**: Integrated with Windows Speech Recognition for hands-free launching.
- **Modern UI**: Follows the system theme (Light / Dark / System) with adjustable window opacity.
- **Extensive Indexing**:
  - Desktop & Taskbar shortcuts
  - Start-menu `.lnk` files and UWP apps
  - Registry `App Paths` (e.g., `cmd`, `notepad`)
  - System32 admin tools (`.msc` / `.cpl`)
  - Windows Settings pages (`ms-settings:`)
  - *Optional:* Documents and Multimedia files
- **Fast & Portable**: Pure PowerShell script. No installation, no background services.

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/zeesha/ShortcutLauncher.git
   cd ShortcutLauncher
   ```

2. Run the script:
    ```powershell
    powershell -ExecutionPolicy Bypass -File Launcher.ps1
    ```

## Keyboard Shortcuts

| Key | Action |
| :--- | :--- |
| **Type** | Filter shortcuts |
| **Up / Down** | Move selection in the list |
| **Enter** | Launch the selected item |
| **Esc** | Clear the search prompt |
| **F1** | Open Help |
| **F2** | Open Setup |
| **F3** | Toggle desktop icons visibility |
| **F4** | Toggle voice input |
| **F5** | Refresh shortcut index |
| **Alt + F4** | Close the window |

## Localization

The UI supports multiple languages out of the box. The launcher will automatically select the language based on your Windows display language, falling back to English if no exact match is found.

To add a new language:
1. Copy `Strings.psd1` and rename it to `Strings.<culture>.psd1` (e.g., `Strings.fr-FR.psd1`).
2. Translate the values (keep the keys unchanged).
3. **Important:** Save the file as **UTF-8 with BOM** to ensure non-ASCII characters render correctly in Windows PowerShell 5.1.
4. Open a Pull Request!

## License

This project is licensed under the MIT License - see the [LICENSE.txt](LICENSE.txt) file for details.
