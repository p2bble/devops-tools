# launcher.ps1 - 관리자 권한 확인 후 collect.ps1 실행
$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$collectScript = Join-Path $scriptDir "collect.ps1"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "관리자 권한으로 재실행합니다..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$collectScript`" -ScriptDir `"$scriptDir`""
    Start-Process powershell -ArgumentList $argList -Verb RunAs -Wait
} else {
    & $collectScript -ScriptDir $scriptDir
    Write-Host ""
    Write-Host "완료! results 폴더에서 CSV 파일을 확인하세요." -ForegroundColor Green
    Write-Host "아무 키나 누르면 종료됩니다..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
