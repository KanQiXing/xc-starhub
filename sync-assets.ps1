# ================================================================
#  sync-assets.ps1
#  从 XC-星枢 源码同步小星素材到 wiki 仓库
#  用法: 在推送 wiki 前运行此脚本
# ================================================================

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $scriptDir
$wikiName  = Split-Path -Leaf $scriptDir

# Find sibling directory that contains the xiaoxing assets
$srcRepo = Get-ChildItem -Path $parentDir -Directory |
    Where-Object { $_.Name -ne $wikiName -and (Test-Path (Join-Path $_.FullName 'src\asset\img\xiaoxing')) } |
    Select-Object -First 1

if (-not $srcRepo) {
    Write-Error "XC source repo not found in: $parentDir"
    exit 1
}

$sourceDir = Join-Path $srcRepo.FullName 'src\asset\img\xiaoxing'
$targetDir = Join-Path $scriptDir 'assets\xiaoxing'

if (-not (Test-Path $sourceDir)) {
    Write-Error "Source directory not found: $sourceDir"
    exit 1
}

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

$count = 0
Get-ChildItem -Path $sourceDir -File | ForEach-Object {
    Copy-Item $_.FullName -Destination $targetDir -Force
    $count++
}

Write-Output "Synced $count asset files to assets/xiaoxing/ (from $($srcRepo.Name))"
