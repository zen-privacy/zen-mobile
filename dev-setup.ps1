# Zen Mobile - Dev Environment Setup
# Run this script at the start of each dev session:
#   . .\dev-setup.ps1
# (Use dot-sourcing to keep env vars in the current session)

$FLUTTER_SDK = "$env:USERPROFILE\dev\flutter-sdk"
$ANDROID_SDK = "$env:USERPROFILE\dev\android-sdk"
$PLATFORM_TOOLS = "$ANDROID_SDK\platform-tools"

# Set environment variables
$env:ANDROID_HOME = $ANDROID_SDK
$env:ANDROID_SDK_ROOT = $ANDROID_SDK
$env:PATH = "$FLUTTER_SDK\bin;$PLATFORM_TOOLS;$ANDROID_SDK\cmdline-tools\latest\bin;$env:PATH"

Write-Host ""
Write-Host "=== Zen Mobile Dev Environment ===" -ForegroundColor Cyan
Write-Host ""

# Check Flutter
try {
    $flutterVer = (flutter --version 2>&1 | Select-String "Flutter").ToString().Trim()
    Write-Host "  [OK] $flutterVer" -ForegroundColor Green
} catch {
    Write-Host "  [MISSING] Flutter SDK not found at $FLUTTER_SDK" -ForegroundColor Red
}

# Check ADB & devices
try {
    $adbVer = (adb version 2>&1 | Select-Object -First 1).ToString().Trim()
    Write-Host "  [OK] $adbVer" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "  Connected devices:" -ForegroundColor Yellow
    adb devices -l | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" } | ForEach-Object {
        Write-Host "    $_" -ForegroundColor White
    }
} catch {
    Write-Host "  [MISSING] ADB not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Quick Commands ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Build & run:" -ForegroundColor Yellow
Write-Host "    flutter run                              - Debug build on device (hot reload)" -ForegroundColor Gray
Write-Host "    flutter run --release                    - Release build on device" -ForegroundColor Gray
Write-Host "    flutter run --profile                    - Profile build on device" -ForegroundColor Gray
Write-Host ""
Write-Host "  Logs (run in separate terminal):" -ForegroundColor Yellow
Write-Host "    .\logcat-vpn.ps1                         - VPN service logs only" -ForegroundColor Gray
Write-Host "    .\logcat-vpn.ps1 -All                    - All app logs" -ForegroundColor Gray
Write-Host "    adb logcat -s ZenVpnService              - Manual logcat filter" -ForegroundColor Gray
Write-Host ""
Write-Host "  Hot reload/restart (while flutter run is active):" -ForegroundColor Yellow
Write-Host "    r    - Hot reload (Dart changes only)" -ForegroundColor Gray
Write-Host "    R    - Hot restart (full restart)" -ForegroundColor Gray
Write-Host "    q    - Quit" -ForegroundColor Gray
Write-Host ""
