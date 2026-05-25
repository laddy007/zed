# ack.ps1
# Clear the "claude finished" flag for the current pane's task.
# Used by Claude Code's UserPromptSubmit hook so the status line badge
# switches green -> yellow as soon as the user starts a new turn.

param([string]$Task = $env:ZED_TASK)

if (-not $Task) { exit 0 }
$flag = Join-Path $env:TEMP "zed-done\$Task.flag"
if (Test-Path $flag) {
    Remove-Item $flag -Force -ErrorAction SilentlyContinue
}
