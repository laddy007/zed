# zed.ps1
# Open Windows Terminal panes with colored backgrounds and labeled prompts.
# Two modes:
#   1) Batch:       zed.ps1 -Tasks T1,T2,T3
#   2) Interactive: zed.ps1   (prompts for Claude prompt + pane name)
#
# Each pane: distinct background (profile zed-1..zed-8), task label in
# tab title, $env:ZED_TASK set for the Claude Code statusLine.
#
# Requires: Windows Terminal, PowerShell 7+, and zed-1..zed-8 profiles
# in wt settings.json (see wt-profiles.json).

param(
    [Parameter(Position=0)][string[]]$Tasks,
    [Parameter(Position=1)][Alias("Prompt","p")][string]$ClaudePrompt = "",
    [string]$WorkDir = "C:\gps42",
    [string]$Window = "zed",
    [switch]$none,
    [switch]$audio,
    [switch]$toast,
    [switch]$both
)

$NotifyMode = ""
if     ($none)  { $NotifyMode = "none" }
elseif ($audio) { $NotifyMode = "audio" }
elseif ($toast) { $NotifyMode = "toast" }
elseif ($both)  { $NotifyMode = "both" }

$ErrorActionPreference = "Stop"

$profiles = @("zed-1","zed-2","zed-3","zed-4","zed-5","zed-6","zed-7","zed-8")

# Interactive mode: ask for Claude prompt and pane name.
if (-not $Tasks -or $Tasks.Count -eq 0) {
    Write-Host "zed - interactive mode" -ForegroundColor Cyan
    $ClaudePrompt = Read-Host "Claude prompt"
    if (-not $ClaudePrompt.Trim()) {
        throw "Empty prompt. Aborting."
    }
    $nameInput = Read-Host "Pane (z1-z8, empty = auto)"
    if (-not $nameInput.Trim()) {
        $nameInput = "z$((Get-Random -Minimum 1 -Maximum 9))"
        Write-Host "Auto-assigned: $nameInput" -ForegroundColor DarkCyan
    } elseif ($nameInput -notmatch '^z[1-8]$') {
        throw "Invalid name '$nameInput'. Use z1-z8 or leave empty."
    }
    $Tasks = @($nameInput)
}

if ($Tasks.Count -lt 1 -or $Tasks.Count -gt 8) {
    throw "Provide 1-8 tasks (got $($Tasks.Count))."
}

foreach ($t in $Tasks) {
    if ($t -notmatch '^[A-Za-z0-9_.\-]+$') {
        throw "Invalid task name '$t'. Allowed: A-Z a-z 0-9 _ . -"
    }
}

if (-not (Test-Path $WorkDir)) {
    throw "WorkDir does not exist: $WorkDir"
}

$topCount = [Math]::Min(4, $Tasks.Count)
$botCount = $Tasks.Count - $topCount

# If a Claude prompt was given, dump it to a temp file so the inner
# PowerShell can read it without any quoting/escape issues.
$promptFile = $null
if ($ClaudePrompt) {
    $promptDir = Join-Path $env:TEMP "zed-prompts"
    New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
    $promptFile = Join-Path $promptDir ("p-" + (Get-Date -Format "yyyyMMdd-HHmmss-fff") + ".txt")
    Set-Content -Path $promptFile -Value $ClaudePrompt -Encoding UTF8
}

function Get-ProfileForTask([string]$task, [int]$index) {
    if ($task -match '^z(?:ed-)?([1-8])$') { return "zed-$($Matches[1])" }
    return $profiles[$index % $profiles.Count]
}

function Get-EncodedCommand([string]$task, [string]$promptPath) {
    $claudeLine = ""
    if ($promptPath) {
        $escPath = $promptPath.Replace("'", "''")
        $claudeLine = "& claude (Get-Content -Raw '$escPath')"
    }
    $notifyLine = if ($NotifyMode) { "`$env:ZED_NOTIFY = '$NotifyMode'" } else { "" }
    $promptFileLine = if ($promptPath) {
        "`$env:ZED_PROMPT_FILE = '$($promptPath.Replace("'", "''"))'"
    } else { "" }
    $script = @"
`$env:ZED_TASK = '$task'
$notifyLine
$promptFileLine
`$Host.UI.RawUI.WindowTitle = '$task'

`$global:ZED_FLAG_DIR = Join-Path `$env:TEMP 'zed-done'
`$global:ZED_FLAG_NAME = '$task.flag'
New-Item -ItemType Directory -Force -Path `$global:ZED_FLAG_DIR | Out-Null

`$global:ZED_FSW = New-Object System.IO.FileSystemWatcher
`$global:ZED_FSW.Path = `$global:ZED_FLAG_DIR
`$global:ZED_FSW.Filter = `$global:ZED_FLAG_NAME
`$global:ZED_FSW.EnableRaisingEvents = `$true

Register-ObjectEvent -InputObject `$global:ZED_FSW -EventName Created -SourceIdentifier 'zed-done-$task' -Action {
    try {
        Start-Sleep -Milliseconds 100
        `$esc = [char]27
        # OSC 10: brighten default foreground of the whole pane.
        [Console]::Write("`$esc]10;#FFFFFF`$esc\")
        # Inline done banner.
        [Console]::Write("``n`$esc[42m`$esc[97m  *** DONE: $task ***  `$esc[0m``n")
        # Flag is intentionally NOT deleted — it persists so statusline.sh
        # can color the badge green until user acks via zed-reset.
    } catch {}
} | Out-Null

function global:prompt { "[$task] `$(`$PWD.Path)``n> " }

# zed-reset: restore default foreground + clear DONE flag (acknowledge).
function global:zed-reset {
    `$esc = [char]27
    [Console]::Write("`$esc]110`$esc\")
    `$f = Join-Path `$global:ZED_FLAG_DIR `$global:ZED_FLAG_NAME
    if (Test-Path `$f) { Remove-Item `$f -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ('  ' + '$task'.PadRight(60)) -BackgroundColor DarkBlue -ForegroundColor White
Write-Host ''
$claudeLine
"@
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
}

function Get-PaneArgs {
    param(
        [string]$Action,
        [string]$Direction = "",
        [double]$Size = -1,
        [string]$Profile,
        [string]$Title,
        [string]$Task,
        [string]$PromptPath = ""
    )
    $a = @($Action)
    if ($Direction) { $a += $Direction }
    if ($Size -ge 0) {
        $sFmt = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:0.###}", $Size)
        $a += @("--size", $sFmt)
    }
    $a += @(
        "--profile", $Profile,
        "--title", $Title,
        "--startingDirectory", $WorkDir,
        "--",
        "powershell", "-NoExit", "-EncodedCommand", (Get-EncodedCommand $Task $PromptPath)
    )
    return $a
}

$wt = @("-w", $Window)

# Single task: add a pane to the current tab via split-pane (auto direction).
# Multiple tasks: build a grid in a new tab via new-tab.
$firstAction = if ($Tasks.Count -eq 1) { "split-pane" } else { "new-tab" }
$wt += Get-PaneArgs -Action $firstAction `
    -Profile (Get-ProfileForTask $Tasks[0] 0) -Title $Tasks[0] -Task $Tasks[0] -PromptPath $promptFile

# Bottom row anchor first, then top row, then rest of bottom row.
if ($botCount -gt 0) {
    $wt += ";"
    $wt += Get-PaneArgs -Action "split-pane" -Direction "-H" -Size 0.5 `
        -Profile (Get-ProfileForTask $Tasks[$topCount] $topCount) `
        -Title $Tasks[$topCount] -Task $Tasks[$topCount] -PromptPath $promptFile
    $wt += ";"
    $wt += @("move-focus", "up")
}

for ($i = 1; $i -lt $topCount; $i++) {
    $s = ($topCount - $i) / ($topCount - $i + 1)
    $wt += ";"
    $wt += Get-PaneArgs -Action "split-pane" -Direction "-V" -Size $s `
        -Profile (Get-ProfileForTask $Tasks[$i] $i) -Title $Tasks[$i] -Task $Tasks[$i] -PromptPath $promptFile
}

if ($botCount -gt 1) {
    $wt += ";"
    $wt += @("move-focus", "down")
    for ($j = 1; $j -lt $botCount; $j++) {
        $s = ($botCount - $j) / ($botCount - $j + 1)
        $idx = $topCount + $j
        $wt += ";"
        $wt += Get-PaneArgs -Action "split-pane" -Direction "-V" -Size $s `
            -Profile (Get-ProfileForTask $Tasks[$idx] $idx) `
            -Title $Tasks[$idx] -Task $Tasks[$idx] -PromptPath $promptFile
    }
}

Write-Host "Launching wt window '$Window' with $($Tasks.Count) pane(s)..."
& wt.exe $wt
