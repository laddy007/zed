# zed — Windows Terminal launcher + Claude Code status integration

🇬🇧 English version | 🇨🇿 [Česká verze](./readme.md)

Stack for running multiple Claude Code agents side-by-side in a single
Windows Terminal window. Each pane:

- has its **own background color** (zed-1 … zed-8 profiles)
- is **labeled** in the tab title, prompt function (`[z3] PS C:\...>`),
  and Claude Code's status bar
- **visually signals state**: active (gray badge) / Claude finished
  (bright fg + green DONE badge + banner)
- triggers a **cross-monitor notification**: BEL flash + Windows toast
  (click focuses the wt window) + optional system sound
- **auto-resets** to active when you send Claude a new message

```powershell
# Interactive mode (prompts for prompt + pane name):
zed.ps1

# Batch — multiple panes with one shared prompt:
zed.ps1 z1,z2,z3,z4 "Review the auth changes"

# Single pane → split-pane into the current tab:
zed.ps1 z5 "Triage GPS-456"
```

---

## Files

| File | Purpose |
|---|---|
| `zed.ps1` | Pane launcher (interactive + batch) |
| `notify.ps1` | Visual notification — invoked by Claude Code Stop hook |
| `ack.ps1` | Clears the "done" flag — invoked by Claude Code UserPromptSubmit hook |
| `focus.ps1` | Activates the wt window — invoked by the `zed://` URL protocol |
| `statusline.sh` | Claude Code statusLine — two-line with task badge |
| `wt-profiles.json` | wt profile + keybind snippet (for settings.json) |

---

## Requirements

- **Windows Terminal**
- **PowerShell 7+** (pwsh)
- **Git Bash** (for statusline.sh + jq)
- **Claude Code**

---

## Setup (one-time)

### 1) Profiles and zoom keybind in wt settings.json

Path (depends on wt installation):
```
C:\Users\<name>\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

Open via: arrow-down next to the tabs → **Settings** → **Open JSON file**
at the bottom left.

From `wt-profiles.json`:
- Copy the **8 objects from `profiles.list`** into your `profiles.list`
- Copy the **1 object from `actions`** into your `actions` (binds
  `Alt+Y` to `togglePaneZoom`)

Key properties of each zed-N profile:
- `background` — distinct dark color
- `suppressApplicationTitle: true` — Claude can't overwrite the tab label
- `bellStyle: ["visual", "window", "taskbar"]` — BEL = silent flash
- `unfocusedAppearance.foreground: "#808080"` — unfocused panes have
  gray text

### 2) Register the `zed://` URL protocol (so toast click focuses wt)

```powershell
$root = "HKCU:\Software\Classes\zed"
$cmd  = "$root\shell\open\command"
New-Item -Path $root -Force | Out-Null
Set-ItemProperty -Path $root -Name '(default)'    -Value 'URL:zed Protocol'
Set-ItemProperty -Path $root -Name 'URL Protocol' -Value ''
New-Item -Path $cmd -Force | Out-Null
$pwsh = (Get-Command pwsh).Source
$handler = "`"$pwsh`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\myprogramfiles\zed\focus.ps1`""
Set-ItemProperty -Path $cmd -Name '(default)' -Value $handler
```

Test: `Start-Process "zed://focus"` → the wt window should come forward.
Uninstall: `Remove-Item HKCU:\Software\Classes\zed -Recurse -Force`

### 3) Claude Code hooks + statusLine

In `~\.claude\settings.json`, add / merge:

```json
"statusLine": {
    "type": "command",
    "command": "bash /c/myprogramfiles/zed/statusline.sh"
},
"hooks": {
    "Stop": [
        { "matcher": "", "hooks": [
            { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\myprogramfiles\\zed\\notify.ps1\"" }
        ]}
    ],
    "Notification": [
        { "matcher": "", "hooks": [
            { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\myprogramfiles\\zed\\notify.ps1\" -Title \"zed - needs input\"" }
        ]}
    ],
    "UserPromptSubmit": [
        { "matcher": "", "hooks": [
            { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\myprogramfiles\\zed\\ack.ps1\"" }
        ]}
    ]
}
```

---

## Usage

### zed.ps1

```powershell
# Batch (multi-pane grid in a new tab):
zed.ps1 z1,z2,z3,z4

# Batch with a shared prompt for all panes:
zed.ps1 z1,z2 "Fix the auth bug"        # positional (shortest)
zed.ps1 z1,z2 -p "Fix the auth bug"     # alias
zed.ps1 z1,z2 -ClaudePrompt "Fix..."    # full name

# Single pane → split-pane into the current tab:
zed.ps1 z3
zed.ps1 z3 "Review GPS-123"

# Interactive mode:
zed.ps1
# → "Claude prompt:" + "Pane (z1-z8, empty = auto):"

# Custom working directory / wt window:
zed.ps1 z1 -WorkDir "C:\projects\foo"
zed.ps1 z1 -Window another-project

# Notification mode (overrides ZED_NOTIFY env):
zed.ps1 z1 -audio
zed.ps1 z1 -toast
zed.ps1 z1 -none
zed.ps1 z1 -both       # default
```

### Layout

- **1 task** → split-pane into the current tab of the existing window
- **2-4 tasks** → single row of panes in a new tab
- **5-8 tasks** → top row of 4, bottom row of the rest
- **9+** → error

### Pane states

| State | Pane foreground | Status badge | Trigger |
|---|---|---|---|
| Unfocused | gray #808080 | (hidden) | — |
| Active | default ~#CCCCCC | **gray** `z3: ...preview...` | — |
| Done | **bright #FFFFFF** + banner | **green** `z3: ... DONE` | Stop hook |
| Resumed | bright stays | gray again | UserPromptSubmit hook |

### Status bar (Claude Code statusLine)

Two-line layout:

```
C:\gps42 | Opus 4.7 (1M context) | 40k/200k (20%)
 z3: Fix the auth bug from GPS-123, the Bearer token...
```

- **Line 2** appears only inside a zed pane (where `$env:ZED_TASK` is
  set)
- **Preview** = first line of `$env:ZED_PROMPT_FILE`, up to **200
  characters**, longer → `...`
- **Color**: gray (active) / green (DONE)

### In-pane functions

- **`zed-reset`** — restores the pane's default foreground + clears the
  done flag (manual acknowledgement)

### Notification modes

Default: `both`. Switch via:

```powershell
$env:ZED_NOTIFY = 'audio'    # globally (in your PS profile)
zed.ps1 z1 -toast            # per-pane at launch
notify.ps1 -Task t -none     # manual test
```

| Mode | From default shell | From a zed pane |
|---|---|---|
| `none` | nothing | nothing |
| `audio` | system sound | system sound |
| `toast` | silent toast | silent toast + taskbar flash |
| `both` | toast with sound | toast with sound + taskbar flash |

### wt keybinds

- `Alt+Y` — zoom the focused pane to full window
- `Alt+arrows` — focus between panes
- `Ctrl+Tab` — switch between tabs

---

## Limitations / known behavior

- **Max 8 panes** per call.
- **Task names**: `^[A-Za-z0-9_.\-]+$`. No spaces, no diacritics.
  `z1-z8` maps to the matching `zed-N` profile (= color). Other names
  cycle profiles by position.
- **Claude prompt** (positional arg 2 / `-p` / `-ClaudePrompt`) is free
  text — spaces, diacritics, multiline, special characters all OK (passed
  via a UTF-8 temp file).
- **PowerShell 5.1** is untested.
- **`-Window <name>`** — a named wt window is reused if it already
  exists, otherwise a new one is created.
- **Pane bright fg persists after Stop hook** through subsequent Claude
  turns — visual history "something recently finished here." Manual
  reset: `zed-reset`.
- **Auto-assignment in interactive mode** is random from 1-8, doesn't
  avoid colors already in use.
- **Prompt temp files** in `%TEMP%\zed-prompts\` are not cleaned up
  automatically.
