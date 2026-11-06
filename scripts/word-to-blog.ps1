#requires -Version 5
param(
  [Parameter(Mandatory = $true)] [string]$Source,
  [Parameter(Mandatory = $false)] [string]$BlogRoot,
  [Parameter(Mandatory = $false)] [bool]$Draft = $true,
  [Parameter(Mandatory = $false)] [switch]$PromoteBoldHeadings
)

if (-not $BlogRoot) { $BlogRoot = Split-Path $PSScriptRoot -Parent }
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Source)) { Write-Error "Source not found: $Source"; exit 1 }

$mdOutDir  = Join-Path $BlogRoot "src\content\blog"
$imgOutDir = Join-Path $BlogRoot "public\images"
$pandocExe = Join-Path $env:LOCALAPPDATA "Pandoc\pandoc.exe"
if (-not (Test-Path $pandocExe)) {
  $pandocExe = (Get-Command pandoc -ErrorAction SilentlyContinue).Source
  if (-not $pandocExe) { Write-Error "pandoc.exe not found"; exit 1 }
}
New-Item -ItemType Directory -Force -Path $mdOutDir  | Out-Null
New-Item -ItemType Directory -Force -Path $imgOutDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-SafeFilename($name) {
  $invalid = [IO.Path]::GetInvalidFileNameChars() -join ""
  return ($name -replace "[$invalid]", "_")
}

function Copy-ImagesAndRewriteRefs($mdContent, $mediaDir, $imgOutDir, $datePrefix) {
  if (-not (Test-Path $mediaDir)) { return $mdContent }
  $imgFiles = Get-ChildItem $mediaDir -File -Recurse | Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|webp|svg|bmp)$' }
  foreach ($img in $imgFiles) {
    $ext  = $img.Extension.ToLower()
    $base = [IO.Path]::GetFileNameWithoutExtension($img.Name)
    $newName = Get-SafeFilename ($datePrefix + "_" + $base + $ext)
    $dest    = Join-Path $imgOutDir $newName
    $cnt = 1
    while ((Test-Path $dest) -and (Get-FileHash $img.FullName -Algorithm MD5).Hash -ne (Get-FileHash $dest -Algorithm MD5).Hash) {
      $newName = Get-SafeFilename ($datePrefix + "_" + $base + "_" + $cnt + $ext)
      $dest    = Join-Path $imgOutDir $newName
      $cnt++
    }
    Copy-Item $img.FullName $dest -Force
    $escaped = [regex]::Escape($img.Name)
    $pattern = '!\((?:[^)]*[\\/])?' + $escaped + '\)'
    $replace = '](/images/' + $newName + ')'
    $mdContent = $mdContent -replace $pattern, $replace
  }
  return $mdContent
}

function ConvertHtmlImages($mdContent, $imgOutDir, $datePrefix) {
  # Handle pandoc <img src="local absolute path"> output
  # PowerShell 5: use .NET regex for match evaluation (not -replace scriptblock)
  $pattern = '<img\s+src="([^"]+)"'
  $result = $mdContent
  $regex = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $matches = $regex.Matches($mdContent)
  foreach ($m in $matches) {
    $src = $m.Groups[1].Value
    if ($src -match '^[A-Z]:\\') {
      $filename = [IO.Path]::GetFileName($src)
      $newName = Get-SafeFilename ($datePrefix + "_" + $filename)
      $dest = Join-Path $imgOutDir $newName
      if ((Test-Path $src) -and -not (Test-Path $dest)) {
        Copy-Item $src $dest -Force
      }
      $replaceImg = '![](' + '/images/' + $newName + ')'
      $result = $result.Replace($m.Value, $replaceImg)
    }
  }
  return $result
}

function Convert-BoldLinesToHeadings($mdContent) {
  $lines = $mdContent -split "`n"
  $result = [System.Collections.Generic.List[string]]::new()
  $firstBold = $true
  $inCode = $false
  foreach ($line in $lines) {
    if ($line.Trim() -match '^```') { $inCode = -not $inCode; $result.Add($line); continue }
    if ($inCode) { $result.Add($line); continue }
    $t = $line.Trim()
    if ($t -match '^#|^[-*+] |^\d+\. |^> |^\s*$') { $result.Add($line); continue }
    if ($t -match '^\*\*(.+?)\*\*\s*[:\uff1a]?\s*$') {
      $inner = $Matches[1]
      if ($firstBold) { $result.Add('# ' + $inner); $firstBold = $false } else { $result.Add('## ' + $inner) }
      continue
    }
    $result.Add($line)
  }
  return ($result -join "`n")
}

function MakeFrontmatter($title, $pubDate, $tags, $draft) {
  $esc = $title.Replace('"', '\"')
  $d = $draft.ToString().ToLower()
  return "---`ntitle: `"$esc`"`ndescription: To be filled`npubDate: $pubDate`ntags: [$tags]`ndraft: $d`n---`n`n"
}

$docxFiles = Get-ChildItem $Source -File -Filter *.docx
if ($docxFiles.Count -eq 0) { Write-Warning "No .docx in $Source"; exit 0 }
Write-Host "Found $($docxFiles.Count) .docx file(s), converting..." -ForegroundColor Cyan
$okCount = 0
$skipList = @()

foreach ($doc in $docxFiles) {
  $baseName   = $doc.BaseName
  $safeName   = Get-SafeFilename $baseName
  $pubDate    = $doc.LastWriteTime.ToString("yyyy-MM-dd")
  $mdFileName = "$pubDate-$safeName.md"
  $mdOutPath  = Join-Path $mdOutDir $mdFileName
  if (Test-Path $mdOutPath) { Write-Warning "Skip (exists): $mdFileName"; $skipList += $baseName; continue }

  $tempDir   = Join-Path $env:TEMP ("word2blog_" + [guid]::NewGuid().ToString("N"))
  $tempMedia = Join-Path $tempDir "media"
  $tempMd    = Join-Path $tempDir "$safeName.md"
  try {
    & $pandocExe $doc.FullName -f docx -t gfm --wrap=none --extract-media=$tempMedia -o $tempMd 2>&1 | Out-Null
    if (-not (Test-Path $tempMd)) { throw "pandoc did not generate Markdown" }
    $mdContent = Get-Content $tempMd -Raw -Encoding UTF8
    $mdContent = Copy-ImagesAndRewriteRefs $mdContent $tempMedia $imgOutDir $pubDate
    $mdContent = ConvertHtmlImages $mdContent $imgOutDir $pubDate
    if ($PromoteBoldHeadings) { $mdContent = Convert-BoldLinesToHeadings $mdContent }
    $fm      = MakeFrontmatter $baseName $pubDate "" $Draft
    $finalMd = $fm + $mdContent.TrimStart()
    [IO.File]::WriteAllText($mdOutPath, $finalMd, $utf8)
    Write-Host "  OK: $mdFileName" -ForegroundColor Green
    $okCount++
  } catch {
    Write-Host "  FAIL $baseName : $($_.Exception.Message)" -ForegroundColor Red
  } finally {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
Write-Host ""
Write-Host "Done: $okCount / $($docxFiles.Count)" -ForegroundColor Cyan
if ($skipList.Count -gt 0) {
  Write-Host "Skipped: $($skipList -join ', ')" -ForegroundColor Yellow
}