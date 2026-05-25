# notify.ps1
# Visual notification for "Claude finished" — used as a Stop hook.
#
# Three layers, ordered by reach:
#   1) BEL char           -> wt visual + taskbar flash (per profile bellStyle)
#   2) Windows toast      -> visible from any monitor (primary monitor corner)
#   3) Banner in the pane -> seen when user switches back
#
# Usage:
#   notify.ps1              # uses $env:ZED_TASK
#   notify.ps1 -Task t3     # explicit override

param(
    [string]$Task = $env:ZED_TASK,
    [string]$Title = "zed - Claude done",
    [switch]$none,
    [switch]$audio,
    [switch]$toast,
    [switch]$both
)

if (-not $Task) { $Task = "?" }

# Resolve mode: explicit switch > $env:ZED_NOTIFY > default "both".
$Mode = ""
if     ($none)  { $Mode = "none" }
elseif ($audio) { $Mode = "audio" }
elseif ($toast) { $Mode = "toast" }
elseif ($both)  { $Mode = "both" }
if (-not $Mode) {
    $Mode = if ($env:ZED_NOTIFY) { $env:ZED_NOTIFY.ToLower() } else { "both" }
}
$wantToast = $Mode -in @("toast", "both")
$wantSound = $Mode -eq "audio"   # system sound only in audio-only mode
$toastSilent = $Mode -eq "toast" # toast popup with no sound

# 0) Drop a "done" flag the pane's prompt picks up to render itself green.
try {
    $flagDir = Join-Path $env:TEMP "zed-done"
    New-Item -ItemType Directory -Force -Path $flagDir | Out-Null
    Set-Content -Path (Join-Path $flagDir "$Task.flag") -Value (Get-Date -Format o) -Encoding UTF8
} catch {}

# 1) BEL -> wt flash. Only emit when:
#    - we're inside a zed pane ($env:ZED_TASK set) where the profile has
#      bellStyle = visual+window+taskbar without "audible" (silent flash);
#    - AND the mode wants a visual notification (toast/both).
#    Without these gates, BEL from a default profile (bellStyle "audible")
#    would beep audibly regardless of $Mode.
$inZedPane = -not [string]::IsNullOrEmpty($env:ZED_TASK)
if ($inZedPane -and $wantToast) {
    try { [Console]::Out.Write([char]7) } catch {}
}

# 1b) Audio-only mode: play Windows system notification sound directly.
if ($wantSound) {
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
}

# 2) Banner is now rendered by the pane itself (via FileSystemWatcher reacting
#    to the flag file from step 0). Keeping notify.ps1 silent so manual tests
#    from a different terminal don't print there.

# 3) Windows toast. Best-effort: silently skip if WinRT not available.
if (-not $wantToast) { return }
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null

    $safeTitle = [System.Security.SecurityElement]::Escape($Title)
    $safeTask  = [System.Security.SecurityElement]::Escape($Task)

    $audioTag = if ($toastSilent) {
        '<audio silent="true"/>'
    } else {
        '<audio src="ms-winsoundevent:Notification.Default"/>'
    }

    # Click invokes zed:// protocol -> focus.ps1 -> brings wt window forward.
    $template = @"
<toast launch="zed://focus" activationType="protocol"><visual><binding template="ToastGeneric"><text>$safeTitle</text><text>$safeTask</text></binding></visual>$audioTag</toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    # AppID of installed Windows Terminal -> toast shows the wt icon.
    $appId = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
} catch {
    # No-op: BEL + banner already happened.
}
