# verify-pages.ps1  UTF-8 BOM
# 用法: .\scripts\verify-pages.ps1          (默认:远程 Pages)
#       .\scripts\verify-pages.ps1 -LocalOnly (只看本地 9 HTML 产物)
param([switch]$LocalOnly)
$ErrorActionPreference = 'Stop'

$pos = [ordered]@{
  'v312-title'       = '插件终于能写了'
  'v311-title'       = '22 件事一天内全怼上去了'
  'v310-title'       = '一口气做了 12 件大活'
  'v309-title'       = '彻底把核心从 Codex 里剥离出来,自己写了'
  'v381-title'       = '多场景 + 多情绪,陪伴的感觉终于出来了'
  'v307-title'       = '起点'
  'v312-opening'     = '源码自己一行行写的'
  'pitfall-adapter'  = '壳里留 4 个方法,每家写个薄适配层'
  'pitfall-e2b'      = 'firecracker 在 Windows 本地起很折腾'
  'pitfall-lsp'      = 'jdtls 启动是真的慢'
  'pitfall-play'     = 'Playwright 首装要下浏览器二进制'
  'pitfall-title'    = '账单砍到 1/6'
  'core-agentloop'   = '不是说完一句话就傻等你'
  'core-fs'          = '想改文件得你点头才行'
  'core-sdk'         = '30 行代码能写出 Hello World 插件'
}

$negPatterns = @(
  '差值',
  '\bP0\b',
  '\bP1\b',
  '\bP2\b',
  '提炼',
  '奠基',
  '核心作用',
  '推动',
  '铺路'
)

$anchors = @(
  'v3-12',
  'v3-11',
  'v3-10',
  'v3-9',
  'v3-8-1',
  'v3-7'
)

function ReadFile($p) { return [System.IO.File]::ReadAllText($p,[System.Text.Encoding]::UTF8) }
function HttpGet($url) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
    if ($r.StatusCode -ne 200) { Write-Warning ('HTTP ' + $r.StatusCode + ' $url'); return $null }
    return [string]$r.Content
  } catch {
    Write-Warning ('HTTP FAIL $url : ' + $_.Exception.Message)
    return $null
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ($LocalOnly) {
  Write-Host "[LocalOnly] 不联网,使用本地 9 HTML 产物" -ForegroundColor Cyan
  $changeLog = ReadFile (Join-Path $repoRoot 'wiki-pages\更新日志.html')
  $coreText  = ReadFile (Join-Path $repoRoot 'wiki-pages\核心功能.html')
  $cssText   = ReadFile (Join-Path $repoRoot 'wiki-pages\wiki.css')
} else {
  $Base = 'https://kanqixing.github.io/xc-starhub/wiki-pages'
  Write-Host ("[Remote] HTTP 抓取: " + $Base + " ...") -ForegroundColor Cyan
  $changeLog = HttpGet ($Base + '/更新日志.html')
  $coreText  = HttpGet ($Base + '/核心功能.html')
  $cssText   = HttpGet ($Base + '/wiki.css')
}

$ok = 0; $miss = 0;
Write-Host ""; Write-Host "--- (1/4) 正面关键字命中 ---"
$posRows = foreach ($k in $pos.Keys) {
  $pat  = $pos[$k]
  $blob = if ($k -like 'core-*') { $coreText } else { $changeLog }
  $hit  = $false
  if ($null -ne $blob -and $blob.Contains($pat)) { $hit = $true }
  if ($hit) { $ok++ } else { $miss++ }
  [pscustomobject]@{ Key=$k; Pattern=$pat; Hit=$hit }
}
$posRows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host

Write-Host ""; Write-Host "--- (2/4) 反面关键字残留统计 ---"
$negHits = 0;
$negRows = foreach ($p in $negPatterns) {
  $c1 = 0; $c2 = 0;
  if ($null -ne $changeLog) { $c1 = ([regex]::Matches($changeLog,$p)).Count }
  if ($null -ne $coreText)    { $c2 = ([regex]::Matches($coreText,$p)).Count }
  $tot = $c1 + $c2; if ($tot -gt 0) { $negHits++ }
  [pscustomobject]@{ Pattern=$p; Changelog=$c1; Core=$c2; Total=$tot }
}
$negRows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
if ($negHits -eq 0) { Write-Host "  OK  0 残留" -ForegroundColor Green } else { Write-Host ("  WARN 残留 " + $negHits + " 项") -ForegroundColor Red }

Write-Host ""; Write-Host "--- (3/4) 版本锚点 id 命中 ---"
$anchorHits = 0;
$anchorRows = foreach ($a in $anchors) {
  $pat  = 'id="' + $a + '"'
  $hit  = $false
  if ($null -ne $changeLog -and $changeLog.Contains($pat)) { $hit = $true; $anchorHits++ }
  [pscustomobject]@{ Anchor=$a; Hit=$hit }
}
$anchorRows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host

Write-Host ""; Write-Host "--- (4/4) CSS 媒体查询 ---"
$w = $false; $f = $false; $t640 = $false;
if ($null -ne $cssText) {
  if ($cssText.Contains('wide-caps table tbody tr')) { $w = $true }
  if ($cssText -match 'flex-direction:\s*column')     { $f = $true }
  if ($cssText -match 'max-width:\s*640px')            { $t640 = $true }
}
[pscustomobject]@{ WideCaps720=$w; FlexColumn=$f; Topbar640=$t640 } | Format-List | Out-String -Width 220 | Write-Host

Write-Host ""; Write-Host "=== TOTAL ==="
$m1 = "正面关键字命中: " + $ok + "/" + ($ok+$miss)
$m2 = "反面关键字残留: " + $negHits + " 项"
$m3 = "版本锚点命中:   " + $anchorHits + "/" + $anchors.Count
$m4 = "CSS媒体查询:    wide-caps=" + $w + "  flex-column=" + $f + "  topbar640=" + $t640
$c1 = if ($miss -eq 0) {'Green'} else {'Yellow'}
$c2 = if ($negHits -eq 0) {'Green'} else {'Red'}
$c3 = if ($anchorHits -eq $anchors.Count) {'Green'} else {'Yellow'}
$c4 = if ($w -and $f -and $t640) {'Green'} else {'Yellow'}
Write-Host $m1 -ForegroundColor $c1
Write-Host $m2 -ForegroundColor $c2
Write-Host $m3 -ForegroundColor $c3
Write-Host $m4 -ForegroundColor $c4

if ($negHits -gt 0) { exit 1 }
exit 0
