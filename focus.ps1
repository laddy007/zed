# focus.ps1
# Bring the zed wt window to the foreground. Invoked by the zed:// URL
# protocol handler when the user clicks the toast notification.

# First choice: wt CLI knows how to focus a named window.
try {
    & wt.exe -w zed focus-tab --target 0
    exit 0
} catch {}

# Fallback: raw Win32 focus on the first wt window we can find.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Foc {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
}
"@ -ErrorAction SilentlyContinue

Get-Process WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) {
        [Foc]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE
        [Foc]::SetForegroundWindow($h) | Out-Null
    }
}
