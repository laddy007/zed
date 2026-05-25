# zed — Windows Terminal launcher + Claude Code status integration

🇨🇿 Česká verze | 🇬🇧 [English version](./readme.en.md)

Stack pro souběžnou práci s více Claude Code agenty v jednom Windows
Terminal okně. Každý pane:

- má **vlastní barvu pozadí** (zed-1 … zed-8 profily)
- je **labelován** v tab title, prompt funkci (`[z3] PS C:\...>`)
  a v Claude Code status baru
- **vizuálně signalizuje stav**: aktivní (šedý badge) / Claude doběhl
  (bright fg + zelený DONE badge + banner)
- triggeruje **cross-monitor notifikaci**: BEL flash + Windows toast
  (klik zaměří wt okno) + volitelně systémový zvuk
- **automaticky se vrátí** do active stavu když pošleš Claude novou
  zprávu

```powershell
# Interaktivní mode (zeptá se na prompt + pane name):
zed.ps1

# Batch — víc panes s jedním promptem:
zed.ps1 z1,z2,z3,z4 "Review the auth changes"

# Single pane → přidá do current tab:
zed.ps1 z5 "Triage GPS-456"
```

---

## Soubory

| Soubor | Účel |
|---|---|
| `zed.ps1` | Launcher panes (interactive + batch) |
| `notify.ps1` | Visual notification — volá Claude Code Stop hook |
| `ack.ps1` | Vymaže "done" flag — volá Claude Code UserPromptSubmit hook |
| `focus.ps1` | Aktivuje wt okno — volá `zed://` URL protocol |
| `statusline.sh` | Claude Code statusLine — dvouřádkový s task badge |
| `wt-profiles.json` | Snippet wt profilů + keybind (do settings.json) |

---

## Požadavky

- **Windows Terminal**
- **PowerShell 7+** (pwsh)
- **Git Bash** (statusline.sh + jq)
- **Claude Code**

---

## Setup (jednorázově)

### 1) Profily a zoom keybind do wt settings.json

Cesta (podle wt instalace):
```
C:\Users\<jmeno>\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

Otevři: šipka dolů vedle tabů → **Settings** → **Open JSON file** vlevo
dole.

Z `wt-profiles.json`:
- **8 objektů z `profiles.list`** vlož do svého `profiles.list`
- **1 objekt z `actions`** vlož do svého `actions` (bind `Alt+Y`
  na `togglePaneZoom`)

Klíčové vlastnosti každého zed-N profilu:
- `background` — distinct dark color
- `suppressApplicationTitle: true` — tab label nepřemaže Claude
- `bellStyle: ["visual", "window", "taskbar"]` — BEL = tichý flash
- `unfocusedAppearance.foreground: "#808080"` — neaktivní panes mají
  šedé písmo

### 2) Registrace `zed://` URL protocol (pro klik na toast → focus wt)

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

Test: `Start-Process "zed://focus"` → wt okno skočí do popředí.
Uninstall: `Remove-Item HKCU:\Software\Classes\zed -Recurse -Force`

### 3) Claude Code hooks + statusLine

V `~\.claude\settings.json` přidej / uprav:

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

## Použití

### zed.ps1

```powershell
# Batch (vícepane grid v novém tabu):
zed.ps1 z1,z2,z3,z4

# Batch s promptem pro všechny panes:
zed.ps1 z1,z2 "Fix the auth bug"        # poziční (nejkratší)
zed.ps1 z1,z2 -p "Fix the auth bug"     # alias
zed.ps1 z1,z2 -ClaudePrompt "Fix..."    # full name

# Single pane → split-pane do current tabu:
zed.ps1 z3
zed.ps1 z3 "Review GPS-123"

# Interaktivní mode:
zed.ps1
# → "Claude prompt:" + "Pane (z1-z8, empty = auto):"

# Vlastní pracovní adresář / wt okno:
zed.ps1 z1 -WorkDir "C:\projects\foo"
zed.ps1 z1 -Window jiny-projekt

# Notification mode (přebije ZED_NOTIFY env):
zed.ps1 z1 -audio
zed.ps1 z1 -toast
zed.ps1 z1 -none
zed.ps1 z1 -both       # default
```

### Layout

- **1 task** → split-pane do current tabu existujícího okna
- **2-4 tasks** → jedna řada panes v novém tabu
- **5-8 tasks** → horní řada 4, dolní zbytek
- **9+** → vyhodí chybu

### Stavy pane

| Stav | Pane foreground | Status badge | Trigger |
|---|---|---|---|
| Unfocused | šedý #808080 | (skrytý) | — |
| Active | default ~#CCCCCC | **šedý** `z3: ...preview...` | — |
| Done | **bright #FFFFFF** + banner | **zelený** `z3: ... DONE` | Stop hook |
| Resumed | bright zůstává | šedý zpět | UserPromptSubmit hook |

### Status bar (Claude Code statusLine)

Dvouřádkový:

```
C:\gps42 | Opus 4.7 (1M context) | 40k/200k (20%)
 z3: Fix the auth bug from GPS-123, the Bearer token...
```

- **Řádek 2** se zobrazí jen v zed pane (kde je `$env:ZED_TASK`
  nastavený)
- **Preview** = první řádek z `$env:ZED_PROMPT_FILE`, max **200 znaků**,
  delší → `...`
- **Barva**: šedá (active) / zelená (DONE)

### Funkce uvnitř pane

- **`zed-reset`** — vrátí pane foreground na default + smaže done flag
  (manuální acknowledgement)

### Notifikační módy

Default: `both`. Přepnutí přes:

```powershell
$env:ZED_NOTIFY = 'audio'    # globálně (do PS profilu)
zed.ps1 z1 -toast            # per-pane při launchi
notify.ps1 -Task t -none     # manuální test
```

| Mode | Z default shellu | Z zed pane |
|---|---|---|
| `none` | nic | nic |
| `audio` | systémový zvuk | systémový zvuk |
| `toast` | silent toast | silent toast + taskbar flash |
| `both` | toast se zvukem | toast se zvukem + taskbar flash |

### Klávesy v wt

- `Alt+Y` — zoom fokusovaného pane
- `Alt+šipky` — focus mezi panes
- `Ctrl+Tab` — přepínání mezi taby

---

## Omezení / známé chování

- **Max 8 panes** v jednom volání.
- **Jména tasků**: `^[A-Za-z0-9_.\-]+$`. Bez mezer, bez diakritiky.
  `z1-z8` se mapuje na `zed-N` profil (= barva). Jiná jména cyklí
  profily podle pozice.
- **Claude prompt** (poziční arg 2 / `-p` / `-ClaudePrompt`) je text
  bez omezení — mezery, diakritika, multiline, speciální znaky všechno
  OK (jde přes temp UTF-8 soubor).
- **PowerShell 5.1** netestováno.
- **`-Window <name>`** — pojmenované wt okno se reusne, jinak vznikne
  nové.
- **Pane bright fg po Stop hooku zůstává** i během dalšího claude
  turnu — vizuální historie "tady něco doběhlo". Manuální reset:
  `zed-reset`.
- **Auto-přiřazení v interaktivním módu** je random z 1-8, neumí se
  vyhnout použité barvě.
- **Temp soubory s promptem** v `%TEMP%\zed-prompts\` se neuklízí
  automaticky.
