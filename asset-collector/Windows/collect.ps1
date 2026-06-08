#Requires -Version 5.0
param([string]$ScriptDir = (Split-Path -Parent $MyInvocation.MyCommand.Path))

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$hostname  = $env:COMPUTERNAME
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# config.txt 에서 RESULTS_PATH 읽기 (없으면 로컬 results/ 사용)
$configFile = Join-Path $ScriptDir "..\config.txt"
$resultsDir = Join-Path $ScriptDir "..\results"
if (Test-Path $configFile) {
    $cfgLine = Select-String -Path $configFile -Pattern "^RESULTS_PATH=(.+)" | Select-Object -First 1
    if ($cfgLine -and $cfgLine.Matches[0].Groups[1].Value.Trim() -ne "") {
        $resultsDir = $cfgLine.Matches[0].Groups[1].Value.Trim()
    }
}
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

$csvFile = Join-Path $resultsDir "${hostname}_${timestamp}.csv"
$rawFile = Join-Path $resultsDir "${hostname}_${timestamp}_raw.txt"

function Log($msg) { Write-Host $msg; Add-Content -Path $rawFile -Value $msg -Encoding UTF8 }

Log "=========================================="
Log " 자산 수집 시작: $hostname  [$timestamp]"
Log "=========================================="

# ── OS ──────────────────────────────────────────────────────────────────────
$osInfo     = Get-CimInstance Win32_OperatingSystem
$osCaption  = $osInfo.Caption.Trim()
Log "[OS] $osCaption"

# ── 메인보드 ─────────────────────────────────────────────────────────────────
$board      = Get-CimInstance Win32_BaseBoard
$boardMfr   = $board.Manufacturer.Trim()
$boardProd  = $board.Product.Trim()
$boardSN    = $board.SerialNumber.Trim()
Log "[메인보드] $boardMfr / $boardProd / S/N: $boardSN"

# ── CPU ──────────────────────────────────────────────────────────────────────
$cpu        = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
Log "[CPU] $cpu"

# ── GPU ──────────────────────────────────────────────────────────────────────
# 1단계: nvidia-smi로 NVIDIA GPU 상세 정보 수집 (S/N, UUID)
$nvidiaMap = @{}  # Key: GPU 이름(소문자), Value: {Serial, UUID}
try {
    $nvOut = nvidia-smi --query-gpu=name,serial,uuid --format=csv,noheader 2>$null
    if ($nvOut) {
        foreach ($line in ($nvOut -split "`n" | Where-Object { $_.Trim() -ne "" })) {
            $p = $line -split ",\s*"
            if ($p.Count -ge 3) {
                $nvidiaMap[$p[0].Trim().ToLower()] = @{ Serial = $p[1].Trim(); UUID = $p[2].Trim() }
            }
        }
    }
} catch {}

# 2단계: WMI로 전체 GPU 목록 수집 (Intel / AMD / NVIDIA 모두 포함)
$gpus = @()
Get-CimInstance Win32_VideoController | ForEach-Object {
    $name = $_.Name.Trim()
    $key  = $name.ToLower()
    if ($nvidiaMap.ContainsKey($key)) {
        $gpus += [PSCustomObject]@{
            Name   = $name
            Serial = $nvidiaMap[$key].Serial
            UUID   = $nvidiaMap[$key].UUID
            Source = "nvidia-smi"
        }
    } else {
        $gpus += [PSCustomObject]@{
            Name   = $name
            Serial = "N/A"
            UUID   = "N/A"
            Source = "WMI"
        }
    }
}

Log "[GPU] 총 $($gpus.Count)개 감지:"
foreach ($g in $gpus) {
    Log "  [$($g.Source)] $($g.Name) | S/N: $($g.Serial) | UUID: $($g.UUID)"
}

# ── 스토리지 ──────────────────────────────────────────────────────────────────
$disks = @()
try {
    Get-PhysicalDisk | ForEach-Object {
        $sizeGB = [math]::Round($_.Size / 1GB, 0)
        $disks += [PSCustomObject]@{
            Model  = $_.FriendlyName.Trim()
            Serial = $_.SerialNumber.Trim()
            Size   = "${sizeGB} GB"
            Type   = $_.MediaType   # SSD / HDD / Unspecified
        }
    }
} catch {
    Get-CimInstance Win32_DiskDrive | ForEach-Object {
        $sizeGB = if ($_.Size) { [math]::Round([long]$_.Size / 1GB, 0) } else { 0 }
        $disks += [PSCustomObject]@{
            Model  = $_.Model.Trim()
            Serial = $_.SerialNumber.Trim()
            Size   = "${sizeGB} GB"
            Type   = "Unknown"
        }
    }
}
Log "[스토리지] 총 $($disks.Count)개 감지:"
foreach ($d in $disks) {
    Log "  [$($d.Type)] $($d.Model) | S/N: $($d.Serial) | Size: $($d.Size)"
}

# ── RAM ───────────────────────────────────────────────────────────────────────
$ramModules = @(Get-CimInstance Win32_PhysicalMemory)
$ramTotalGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 0)
Log "[RAM] 총 ${ramTotalGB}GB / 슬롯 $($ramModules.Count)개:"
foreach ($m in $ramModules) {
    $mSize = [math]::Round($m.Capacity / 1GB, 0)
    Log "  $($m.Manufacturer.Trim()) ${mSize}GB | P/N: $($m.PartNumber.Trim()) | S/N: $($m.SerialNumber.Trim())"
}

# ── CSV 생성 ──────────────────────────────────────────────────────────────────
$maxRows = (@($gpus.Count, $disks.Count, $ramModules.Count) | Measure-Object -Maximum).Maximum
if ($maxRows -lt 1) { $maxRows = 1 }

$rows = for ($i = 0; $i -lt $maxRows; $i++) {
    [ordered]@{
        Hostname         = if ($i -eq 0) { $hostname }    else { "" }
        OS               = if ($i -eq 0) { $osCaption }   else { "" }
        Board_Mfr        = if ($i -eq 0) { $boardMfr }    else { "" }
        Board_Product    = if ($i -eq 0) { $boardProd }   else { "" }
        Board_SN         = if ($i -eq 0) { $boardSN }     else { "" }
        CPU              = if ($i -eq 0) { $cpu }          else { "" }
        GPU_Name         = if ($i -lt $gpus.Count)     { $gpus[$i].Name }   else { "" }
        GPU_Serial       = if ($i -lt $gpus.Count)     { $gpus[$i].Serial } else { "" }
        GPU_UUID         = if ($i -lt $gpus.Count)     { $gpus[$i].UUID }   else { "" }
        Disk_Model       = if ($i -lt $disks.Count)    { $disks[$i].Model }  else { "" }
        Disk_Serial      = if ($i -lt $disks.Count)    { $disks[$i].Serial } else { "" }
        Disk_Size        = if ($i -lt $disks.Count)    { $disks[$i].Size }   else { "" }
        Disk_Type        = if ($i -lt $disks.Count)    { $disks[$i].Type }   else { "" }
        RAM_Total        = if ($i -eq 0) { "${ramTotalGB}GB" } else { "" }
        RAM_Mfr          = if ($i -lt $ramModules.Count) { $ramModules[$i].Manufacturer.Trim() }                               else { "" }
        RAM_Size         = if ($i -lt $ramModules.Count) { "$([math]::Round($ramModules[$i].Capacity/1GB,0))GB" }              else { "" }
        RAM_PartNumber   = if ($i -lt $ramModules.Count) { $ramModules[$i].PartNumber.Trim() }                                 else { "" }
        RAM_Serial       = if ($i -lt $ramModules.Count) { $ramModules[$i].SerialNumber.Trim() }                               else { "" }
    } | ForEach-Object { [PSCustomObject]$_ }
}

$rows | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

# ── 무결성 해시 생성 (SHA256) ─────────────────────────────────────────────────
$hashFile = $csvFile -replace '\.csv$', '.sha256'
$hash     = (Get-FileHash $csvFile -Algorithm SHA256).Hash.ToLower()
"$hash  $(Split-Path $csvFile -Leaf)" | Out-File $hashFile -Encoding UTF8 -NoNewline

Log ""
Log "CSV 저장 완료: $csvFile"
Log "SHA256  완료: $hashFile"
Log "RAW 저장 완료: $rawFile"
