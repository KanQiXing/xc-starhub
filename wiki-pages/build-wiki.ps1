# ================================================================
#  build-wiki.ps1
#  读取 wiki/*.md（排除 _Sidebar.md / _Footer.md），简易 Markdown→HTML
#  转换，包裹完整 HTML 文档（固定顶栏 + 内容 + 底部导航），
#  输出到 wiki-pages/[文件名].html（UTF-8 无 BOM）
# ================================================================

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir
$wikiDir   = Join-Path $repoRoot 'wiki'
$outDir    = $scriptDir

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# ---------- 页面顺序（用于上一篇 / 下一篇导航） ----------
$pages = @(
    @{ file = 'Home';              name = '首页';            title = 'Home · 小星 Wiki' }
    @{ file = '功能总览';           name = '功能总览';         title = '功能总览 · 小星 Wiki' }
    @{ file = '快速开始';           name = '快速开始';         title = '快速开始 · 小星 Wiki' }
    @{ file = '核心功能';           name = '核心功能';         title = '核心功能 · 小星 Wiki' }
    @{ file = '主对话与任务编排';    name = '主对话与任务编排'; title = '主对话与任务编排 · 小星 Wiki' }
    @{ file = '高级功能';           name = '高级功能';         title = '高级功能 · 小星 Wiki' }
    @{ file = '常见问题';           name = '常见问题';         title = '常见问题 · 小星 Wiki' }
    @{ file = '截图画廊';           name = '截图画廊';         title = '截图画廊 · 小星 Wiki' }
    @{ file = '更新日志';           name = '更新日志';         title = '更新日志 · 小星 Wiki' }
)

# ---------- 转换器共享状态（script 作用域） ----------
$script:out      = [System.Collections.ArrayList]::new()
$script:listType = 'none'
$script:paraBuf  = [System.Collections.ArrayList]::new()
$script:tableBuf = [System.Collections.ArrayList]::new()
$script:quoteBuf = [System.Collections.ArrayList]::new()

# ---------- 行内转换：先保护 `code`，其余依次处理图片 / 链接 / 粗体 / 斜体 ----------
function Convert-InlineNoCode {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    # 图片: ![alt](url)  —— 路径原样保留（../assets/... 不变）
    $Text = [regex]::Replace($Text, '!\[([^\]]*)\]\(([^)]+)\)', {
        param($m)
        $alt = $m.Groups[1].Value
        $url = $m.Groups[2].Value
        '<img src="{0}" alt="{1}">' -f $url, $alt
    })

    # 链接: [text](url)  —— .md 末尾或 .md# 锚点转 .html
    $Text = [regex]::Replace($Text, '\[([^\]]+)\]\(([^)]+)\)', {
        param($m)
        $t = $m.Groups[1].Value
        $u = $m.Groups[2].Value
        $u = $u -replace '\.md(#|$)', '.html$1'
        '<a href="{0}">{1}</a>' -f $u, $t
    })

    # 粗体: **text**
    $Text = $Text -replace '\*\*([^*]+)\*\*', '<strong>$1</strong>'
    # 斜体: *text*
    $Text = $Text -replace '\*([^*\s][^*]*?)\*', '<em>$1</em>'

    return $Text
}

function Convert-Inline {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $sb = [System.Text.StringBuilder]::new()
    $codeRe = [regex]::new('`([^`]+)`')
    $last = 0
    foreach ($m in $codeRe.Matches($Text)) {
        if ($m.Index -gt $last) {
            $before = $Text.Substring($last, $m.Index - $last)
            [void]$sb.Append((Convert-InlineNoCode $before))
        }
        $code = $m.Groups[1].Value
        $code = $code -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
        [void]$sb.Append('<code>')
        [void]$sb.Append($code)
        [void]$sb.Append('</code>')
        $last = $m.Index + $m.Length
    }
    if ($last -lt $Text.Length) {
        [void]$sb.Append((Convert-InlineNoCode $Text.Substring($last)))
    }
    return $sb.ToString()
}

# ---------- 判断一行是否为「原样保留」的 HTML / 实体行 ----------
function Is-RawHtml {
    param([string]$Line)
    $t = $Line.Trim()
    if ($t -eq '') { return $false }
    if ($t.StartsWith('<')) { return $true }
    if ($Line -match '</?[a-zA-Z]') { return $true }
    if ($Line -match '&[a-zA-Z#][a-zA-Z0-9]*;') { return $true }
    return $false
}

# ---------- 各种 flush ----------
function Flush-Para {
    if ($script:paraBuf.Count -gt 0) {
        $t = [string]::Join(' ', $script:paraBuf.ToArray())
        $t = Convert-Inline $t
        [void]$script:out.Add(('<p>{0}</p>' -f $t))
        $script:paraBuf.Clear()
    }
}
function Close-List {
    if ($script:listType -eq 'ul') { [void]$script:out.Add('</ul>'); $script:listType = 'none' }
    elseif ($script:listType -eq 'ol') { [void]$script:out.Add('</ol>'); $script:listType = 'none' }
}
function Flush-Table {
    if ($script:tableBuf.Count -eq 0) { return }

    # 拆分每行单元格
    $rows = [System.Collections.ArrayList]::new()
    foreach ($r in $script:tableBuf) {
        $cells = [System.Collections.ArrayList]::new()
        $parts = $r.Trim() -split '\|'
        # 去掉首尾因 | 产生的空串
        if ($parts.Count -gt 0 -and $parts[0].Trim() -eq '') { $parts = $parts[1..($parts.Count - 1)] }
        if ($parts.Count -gt 0 -and $parts[$parts.Count - 1].Trim() -eq '') { $parts = $parts[0..($parts.Count - 2)] }
        foreach ($c in $parts) { [void]$cells.Add($c) }
        [void]$rows.Add($cells)
    }

    [void]$script:out.Add('<table>')
    $afterSep = $false
    $tbodyOpen = $false
    foreach ($cells in $rows) {
        # 分隔行判断（:--:  :---  ---: 等）
        $isSep = $true
        if ($cells.Count -eq 0) { $isSep = $false }
        foreach ($c in $cells) {
            if ($c.Trim() -notmatch '^:?-+:?$') { $isSep = $false; break }
        }
        if ($isSep) { $afterSep = $true; continue }

        if (-not $afterSep) {
            [void]$script:out.Add('<thead><tr>')
            foreach ($c in $cells) { [void]$script:out.Add(('<th>{0}</th>' -f (Convert-Inline $c.Trim()))) }
            [void]$script:out.Add('</tr></thead>')
        }
        else {
            if (-not $tbodyOpen) { [void]$script:out.Add('<tbody>'); $tbodyOpen = $true }
            [void]$script:out.Add('<tr>')
            foreach ($c in $cells) { [void]$script:out.Add(('<td>{0}</td>' -f (Convert-Inline $c.Trim()))) }
            [void]$script:out.Add('</tr>')
        }
    }
    if ($tbodyOpen) { [void]$script:out.Add('</tbody>') }
    [void]$script:out.Add('</table>')
    $script:tableBuf.Clear()
}
function Flush-Quote {
    if ($script:quoteBuf.Count -eq 0) { return }
    [void]$script:out.Add('<blockquote>')
    foreach ($q in $script:quoteBuf) {
        $t = Convert-Inline $q
        [void]$script:out.Add(('<p>{0}</p>' -f $t))
    }
    [void]$script:out.Add('</blockquote>')
    $script:quoteBuf.Clear()
}
function Flush-All {
    Flush-Para
    Close-List
    Flush-Table
    Flush-Quote
}

# ---------- 主转换 ----------
function Convert-MdToHtml {
    param([string]$Md)

    # 重置共享状态
    $script:out.Clear()
    $script:listType = 'none'
    $script:paraBuf.Clear()
    $script:tableBuf.Clear()
    $script:quoteBuf.Clear()

    $lines = $Md -split "`r?`n"
    $inCode = $false
    $codeLines = [System.Collections.ArrayList]::new()
    $inComment = $false

    foreach ($line in $lines) {
        # ---- HTML 注释块（多行）----
        if ($inComment) {
            [void]$script:out.Add($line)
            if ($line -match '-->') { $inComment = $false }
            continue
        }
        # ---- 代码块内 ----
        if ($inCode) {
            if ($line -match '^\s*```\s*$') {
                $code = [string]::Join("`n", $codeLines.ToArray())
                $code = $code -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
                [void]$script:out.Add(('<pre><code>{0}</code></pre>' -f $code))
                $codeLines.Clear()
                $inCode = $false
            }
            else {
                [void]$codeLines.Add($line)
            }
            continue
        }
        # ---- 开启代码块 ----
        if ($line -match '^\s*```(.*)$') {
            Flush-All
            $inCode = $true
            continue
        }
        # ---- 开启 HTML 注释 ----
        if ($line -match '<!--') {
            Flush-All
            [void]$script:out.Add($line)
            if ($line -notmatch '-->') { $inComment = $true }
            continue
        }
        # ---- 空行 ----
        if ($line.Trim() -eq '') { Flush-All; continue }

        # ---- 标题 ----
        if ($line -match '^(#{1,3})\s+(.*)$') {
            Flush-All
            $lvl = $matches[1].Length
            $rawTitle = $matches[2].Trim()
            $t = Convert-Inline $rawTitle
            # 为标题生成稳定的 id 锚点，便于分享链接直接跳到对应版本：
            # 规则：保留字母数字，中文去掉，空格 / / · 破折号 / 句号 / ，/ ： 都换成 -，然后 trim 两端 -
            # V3.12 · 插件终于能写了...  ->  v3-12
            # 优先匹配 V\d+(\.\d+)? 这种版本号开头
            $id = ''
            if ($rawTitle -match 'V(\d+(?:\.\d+){0,3})') {
                $id = 'v' + $matches[1].Replace('.', '-')
            } else {
                # 没版本号就做一次朴素 slug:把 ASCII 标点和常见中文标点、破折号、书名号都换成 -,再 trim。
                # 字符串字面量单独用单引号拼,避免 PowerShell 解析器在方括号内看到反斜杠 + 双引号时懵掉。
                $punctPattern = '[\s'
                $punctPattern += [char]0x00B7  # ·
                $punctPattern += '\-'
                $punctPattern += [char]0x2014  # —
                $punctPattern += '\.'
                $punctPattern += [char]0xFF0C  # ,
                $punctPattern += ','
                $punctPattern += [char]0xFF1A  # :
                $punctPattern += ':'
                $punctPattern += '!!??'
                $punctPattern += [char]0xFF01  # ！
                $punctPattern += [char]0xFF1F  # ？
                $punctPattern += '/\\'
                $punctPattern += [char]0xFF08  # (
                $punctPattern += [char]0xFF09  # )
                $punctPattern += '\(\)'
                $punctPattern += [char]0x3010  # 【
                $punctPattern += [char]0x3011  # 】
                $punctPattern += '\[\]'
                $punctPattern += [char]0x300A  # 《
                $punctPattern += [char]0x300B  # 》
                $punctPattern += '<>'
                $punctPattern += '`~#$%^&*+=|@'
                $punctPattern += ''            # 单引号
                $punctPattern += '"'           # 双引号
                $punctPattern += ']+'
                $slug = $rawTitle -replace $punctPattern, '-'
                $slug = $slug -replace '-+', '-'
                $slug = $slug.Trim('-')
                if ($slug.Length -gt 48) { $slug = $slug.Substring(0, 48) }
                $id = $slug.ToLowerInvariant()
            }
            if ([string]::IsNullOrWhiteSpace($id)) { $id = 'section' }
            [void]$script:out.Add(('<h{0} id="{1}">{2}</h{0}>' -f $lvl, $id, $t))
            continue
        }
        # ---- 水平线 ----
        if ($line -match '^\s*-{3,}\s*$') { Flush-All; [void]$script:out.Add('<hr>'); continue }

        # ---- 表格 ----
        if ($line -match '^\|') {
            Flush-Para; Close-List; Flush-Quote
            [void]$script:tableBuf.Add($line)
            continue
        }
        # ---- 引用块 ----
        if ($line -match '^>\s?(.*)$') {
            Flush-Para; Close-List; Flush-Table
            [void]$script:quoteBuf.Add($matches[1].TrimEnd())
            continue
        }
        # ---- 无序列表 ----
        if ($line -match '^\s*-\s+(.*)$') {
            Flush-Para; Flush-Table; Flush-Quote
            if ($script:listType -ne 'ul') {
                Close-List
                [void]$script:out.Add('<ul>')
                $script:listType = 'ul'
            }
            [void]$script:out.Add(('<li>{0}</li>' -f (Convert-Inline $matches[1])))
            continue
        }
        # ---- 有序列表 ----
        if ($line -match '^\s*(\d+)\.\s+(.*)$') {
            Flush-Para; Flush-Table; Flush-Quote
            if ($script:listType -ne 'ol') {
                Close-List
                $startNum = [int]$matches[1]
                [void]$script:out.Add(('<ol start="{0}">' -f $startNum))
                $script:listType = 'ol'
            }
            [void]$script:out.Add(('<li>{0}</li>' -f (Convert-Inline $matches[2])))
            continue
        }
        # ---- 原样保留的 HTML / 实体行 ----
        # （仅把相对 .md 链接修正为 .html，外部链接与资源路径不动）
        if (Is-RawHtml $line) {
            Flush-All
            $line = [regex]::Replace($line, 'href="([^"]+)"', {
                param($m)
                $u = $m.Groups[1].Value
                if ($u -match '^https?:') { return $m.Value }
                $u = $u -replace '\.md(#|$)', '.html$1'
                'href="{0}"' -f $u
            })
            [void]$script:out.Add($line)
            continue
        }
        # ---- 普通段落 ----
        [void]$script:paraBuf.Add($line.Trim())
    }

    # 收尾
    Flush-All
    if ($inCode) {
        $code = [string]::Join("`n", $codeLines.ToArray())
        $code = $code -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
        [void]$script:out.Add(('<pre><code>{0}</code></pre>' -f $code))
    }

    return [string]::Join("`n", $script:out.ToArray())
}

# ================================================================
#  主流程：遍历页面，读 md → 转 HTML → 包裹文档 → 写出
# ================================================================
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$generated = 0

for ($i = 0; $i -lt $pages.Count; $i++) {
    $p = $pages[$i]
    $mdPath = Join-Path $wikiDir ($p.file + '.md')
    if (-not (Test-Path -LiteralPath $mdPath)) {
        Write-Warning "缺少源文件: $mdPath"
        continue
    }
    $md = [System.IO.File]::ReadAllText($mdPath, [System.Text.Encoding]::UTF8)
    $body = Convert-MdToHtml $md

    # 上一篇 / 下一篇
    $prevChip  = '<span class="nav-chip muted">← 上一篇</span>'
    $nextChip  = '<span class="nav-chip muted">下一篇 →</span>'
    $prevLink  = '<span class="kbd-btn">已是第一页</span>'
    $nextLink  = '<span class="kbd-btn">已是最后一页</span>'
    if ($i -gt 0) {
        $pp = $pages[$i - 1]
        $prevChip = '<a class="nav-chip arrow" href="./{0}.html">← <span class="long">{1}</span></a>' -f $pp.file, $pp.name
        $prevLink = '<a class="kbd-btn" href="./{0}.html">← {1}</a>' -f $pp.file, $pp.name
    }
    if ($i -lt $pages.Count - 1) {
        $np = $pages[$i + 1]
        $nextChip = '<a class="nav-chip arrow" href="./{0}.html"><span class="long">{1}</span> →</a>' -f $np.file, $np.name
        $nextLink = '<a class="kbd-btn" href="./{0}.html">{1} →</a>' -f $np.file, $np.name
    }

    # 底部 kbd 按钮组（9 页互链）
    $kbd = [System.Collections.ArrayList]::new()
    for ($j = 0; $j -lt $pages.Count; $j++) {
        $q = $pages[$j]
        if ($j -eq $i) {
            [void]$kbd.Add(('<span class="kbd-btn active">{0}</span>' -f $q.name))
        }
        else {
            [void]$kbd.Add(('<a class="kbd-btn" href="./{0}.html">{1}</a>' -f $q.file, $q.name))
        }
    }
    $kbdHtml = [string]::Join(' ', $kbd.ToArray())

    $desc = 'XC 星枢 · 小星 Wiki — ' + $p.name

    $fontLinks = @'
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Noto+Serif+SC:wght@500;700;900&family=Noto+Sans+SC:wght@400;500;700&family=JetBrains+Mono:wght@400;600;800&display=swap" rel="stylesheet">
'@.Trim()

    $pageName = $p.name
    $heroHtml = @"
<section class="wiki-hero">
  <h1>$pageName</h1>
  <span class="hero-sub">XC · 星枢 · 小星 Wiki</span>
</section>
"@

    # 单引号 here-string 不插值，避免 $body 里的 $ 被解析；用 .Replace 注入
    $tpl = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>__TITLE__</title>
<meta name="description" content="__DESC__">
<meta property="og:title" content="__TITLE__">
<meta property="og:description" content="__DESC__">
<meta property="og:image" content="../assets/xiaoxing/character-fullbody.png">
<meta property="og:type" content="article">
<meta property="og:locale" content="zh_CN">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="__TITLE__">
<meta name="twitter:description" content="__DESC__">
<meta name="twitter:image" content="../assets/xiaoxing/character-fullbody.png">
__FONTS__
<link rel="stylesheet" href="./wiki.css">
</head>
<body>
<nav class="topbar">
  <div class="nav-left">
    <a class="nav-chip" href="../index.html">&larr; <span class="long">门户首页</span></a>
  </div>
  <div class="nav-title">__PAGENAME__<span class="crumb-sub">· 小星 Wiki</span></div>
  <div class="nav-right">
    __PREVCHIP__
    __NEXTCHIP__
  </div>
</nav>
<main class="wiki-wrap">
__HERO__
  <article class="wiki-content">
__BODY__
  </article>
</main>
<nav class="bottom-nav">
  <span class="bn-label">📖 Wiki 导航</span>
  <div class="bn-group">
__KBD__
  </div>
  <div class="bn-prevnext">
    __PREVLINK__
    __NEXTLINK__
  </div>
</nav>
<footer class="wiki-footer">
  <sub>✦ XC · 星枢 · 小星 · HELIOS V3.16 · LOCAL-FIRST · OBSERVABLE · COMPOSABLE · CRAFTED ✦</sub>
</footer>
</body>
</html>
'@

    $html = $tpl.
        Replace('__TITLE__', $p.title).
        Replace('__DESC__', $desc).
        Replace('__FONTS__', $fontLinks).
        Replace('__PAGENAME__', $p.name).
        Replace('__HERO__', $heroHtml).
        Replace('__PREVCHIP__', $prevChip).
        Replace('__NEXTCHIP__', $nextChip).
        Replace('__PREVLINK__', $prevLink).
        Replace('__NEXTLINK__', $nextLink).
        Replace('__KBD__', $kbdHtml).
        Replace('__BODY__', $body)

    $outPath = Join-Path $outDir ($p.file + '.html')
    [System.IO.File]::WriteAllText($outPath, $html, $utf8NoBom)
    $generated++
    Write-Host ("generated: {0}.html" -f $p.file)
}

Write-Host ("done. {0} pages generated into {1}" -f $generated, $outDir)