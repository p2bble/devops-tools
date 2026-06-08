#Requires -Version 5.0
# 사용법: powershell -ExecutionPolicy Bypass -File merge_results.ps1 [CSV폴더경로]
# 예시:   powershell -ExecutionPolicy Bypass -File merge_results.ps1 D:\asset_results
param([string]$InputDir = "")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

if ($InputDir -eq "") { $InputDir = Join-Path $PSScriptRoot "..\results" }
$resolved = Resolve-Path $InputDir -ErrorAction SilentlyContinue
if ($resolved) { $InputDir = $resolved.Path }
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $InputDir "MASTER_${timestamp}.csv"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host " 자산 CSV 병합 + 무결성 검증 도구" -ForegroundColor Cyan
Write-Host " 입력 폴더: $InputDir" -ForegroundColor Cyan
Write-Host "======================================`n"

# MASTER_ 파일 제외하고 모든 CSV 수집
$csvFiles = Get-ChildItem $InputDir -Filter "*.csv" -ErrorAction Stop |
            Where-Object { $_.Name -notlike "MASTER_*" } |
            Sort-Object Name

if ($csvFiles.Count -eq 0) {
    Write-Host "CSV 파일이 없습니다." -ForegroundColor Red
    exit 1
}

$allRows   = [System.Collections.Generic.List[PSObject]]::new()
$okCount   = 0
$tampCount = 0
$noHashCount = 0

foreach ($file in $csvFiles) {
    # ── SHA256 무결성 검증 ──────────────────────────────────────────────────
    $hashFile  = $file.FullName -replace '\.csv$', '.sha256'
    $integrity = "UNVERIFIED"

    if (Test-Path $hashFile) {
        $hashLine    = (Get-Content $hashFile -Encoding UTF8 -Raw).Trim()
        $expectedHash = ($hashLine -split '\s+')[0].ToLower()
        $actualHash   = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()

        if ($expectedHash -eq $actualHash) {
            $integrity = "OK"
            $okCount++
            Write-Host "  [OK]      " -ForegroundColor Green -NoNewline
        } else {
            $integrity = "TAMPERED"
            $tampCount++
            Write-Host "  [!!변조!!]" -ForegroundColor Red -NoNewline
        }
    } else {
        $noHashCount++
        Write-Host "  [미검증]  " -ForegroundColor Yellow -NoNewline
    }

    # ── CSV 로드 및 컬럼 추가 ───────────────────────────────────────────────
    try {
        $rows = Import-Csv $file.FullName -Encoding UTF8
        Write-Host " $($file.Name)  ($($rows.Count)행)"
        $rows | ForEach-Object {
            $_ | Add-Member -NotePropertyName "Source_File" -NotePropertyValue $file.Name -PassThru |
                 Add-Member -NotePropertyName "Integrity"   -NotePropertyValue $integrity  -PassThru
        } | ForEach-Object { $allRows.Add($_) }
    } catch {
        Write-Host " $($file.Name) 읽기 실패: $_" -ForegroundColor Yellow
    }
}

if ($allRows.Count -eq 0) {
    Write-Host "`n유효한 데이터가 없습니다." -ForegroundColor Red
    exit 1
}

$allRows | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

# ── 최종 요약 ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " 검증 결과 요약" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  총 PC 수    : $($csvFiles.Count)대"
Write-Host "  총 데이터   : $($allRows.Count)행"
Write-Host "  [OK]  정상  : ${okCount}개" -ForegroundColor Green
if ($tampCount -gt 0) {
    Write-Host "  [!!] 변조의심: ${tampCount}개  ← MASTER CSV에서 Integrity=TAMPERED 확인" -ForegroundColor Red
}
if ($noHashCount -gt 0) {
    Write-Host "  [??] 미검증 : ${noHashCount}개  ← .sha256 파일 없이 제출됨" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "출력 파일: $outputFile"
Write-Host ""
Write-Host "아무 키나 누르면 종료됩니다..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
