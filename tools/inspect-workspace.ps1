<#
.SYNOPSIS
    Workspace inspection script for Azure DevOps sparse checkout demonstrations.
    Compatible with Windows PowerShell 5.1+ and PowerShell 7+.

.DESCRIPTION
    Enumerates the workspace produced by the pipeline checkout step and emits
    a deterministic, easy-to-compare evidence summary showing which files and
    directories were materialised.

    Environment variables consumed:
        SPARSE_MODE   – label injected by the calling pipeline (e.g. FULL-CHECKOUT)
        SOURCES_DIR   – $(Build.SourcesDirectory); defaults to $PWD if not set

.NOTES
    - Always exits 0; never fails the build.
    - Output is designed to be grep-able: every evidence line begins with a tag.
    - Requires only git and pwsh/powershell that ships with a typical agent.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'   # never abort the build

# ---------------------------------------------------------------------------
# Resolve workspace root
# ---------------------------------------------------------------------------
$sourcesDir = if ($env:SOURCES_DIR) { $env:SOURCES_DIR } else { (Get-Location).Path }
$sparseMode = if ($env:SPARSE_MODE)  { $env:SPARSE_MODE  } else { 'UNKNOWN' }

# ---------------------------------------------------------------------------
# Sentinel paths to verify
# ---------------------------------------------------------------------------
$sentinels = [ordered]@{
    'CDN/cdnfile1.txt'          = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES','SPARSE-PATTERNS','SPARSE-BOTH-PATTERNS-WIN') }
    'CDN/cdnfile2.txt'          = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES','SPARSE-PATTERNS','SPARSE-BOTH-PATTERNS-WIN') }
    'CDN/styles.css'            = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES','SPARSE-PATTERNS','SPARSE-BOTH-PATTERNS-WIN') }
    'CDN/bundle.js'             = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES','SPARSE-PATTERNS','SPARSE-BOTH-PATTERNS-WIN') }
    'CDN/nested/cdnfile2.txt'   = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES','SPARSE-PATTERNS','SPARSE-BOTH-PATTERNS-WIN') }
    'CDN/nested/deep/asset.json'= @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES','SPARSE-PATTERNS','SPARSE-BOTH-PATTERNS-WIN') }
    'FolderA/a1.txt'            = @{ ExpectIn = @('FULL-CHECKOUT') }
    'FolderA/a2.txt'            = @{ ExpectIn = @('FULL-CHECKOUT') }
    'FolderB/b1.txt'            = @{ ExpectIn = @('FULL-CHECKOUT') }
    'FolderB/b2.txt'            = @{ ExpectIn = @('FULL-CHECKOUT') }
    'RootFile1.yml'             = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES') }
    'RootFile2.yml'             = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES') }
    'config.json'               = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES') }
    'root-notes.txt'            = @{ ExpectIn = @('FULL-CHECKOUT','SPARSE-DIRECTORIES') }
}

# ---------------------------------------------------------------------------
# Helper: print a separator line
# ---------------------------------------------------------------------------
function Write-Section([string]$title) {
    $line = '=' * 70
    Write-Host ""
    Write-Host $line
    Write-Host "  $title"
    Write-Host $line
}

# ---------------------------------------------------------------------------
# Helper: check a sentinel file and return result object
# ---------------------------------------------------------------------------
function Test-Sentinel([string]$relativePath, [string[]]$expectIn, [string]$mode) {
    $fullPath  = Join-Path $sourcesDir ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $exists    = Test-Path -LiteralPath $fullPath -PathType Leaf
    $expected  = $expectIn -contains $mode

    $outcome   = if ($expected -and $exists)      { 'PASS' }
                 elseif (!$expected -and !$exists) { 'PASS' }
                 elseif ($expected -and !$exists)  { 'FAIL-MISSING' }
                 else                              { 'FAIL-UNEXPECTED' }

    return [PSCustomObject]@{
        Path     = $relativePath
        Present  = $exists
        Expected = $expected
        Outcome  = $outcome
    }
}

# ---------------------------------------------------------------------------
# SECTION 1 – Header
# ---------------------------------------------------------------------------
Write-Section "WORKSPACE INSPECTION REPORT"
Write-Host "INSPECTION_MODE    : $sparseMode"
Write-Host "INSPECTION_TIME    : $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
Write-Host "SOURCES_DIR        : $sourcesDir"
Write-Host "PS_VERSION         : $($PSVersionTable.PSVersion)"
Write-Host "HOSTNAME           : $env:COMPUTERNAME"

# ---------------------------------------------------------------------------
# SECTION 2 – Top-level directories
# ---------------------------------------------------------------------------
Write-Section "TOP-LEVEL DIRECTORIES"
try {
    $dirs = Get-ChildItem -LiteralPath $sourcesDir -Directory -ErrorAction Stop |
            Sort-Object Name
    if ($dirs.Count -eq 0) {
        Write-Host "DIR_ENUM           : (no directories found)"
    }
    foreach ($d in $dirs) {
        Write-Host "DIR_PRESENT        : $($d.Name)/"
    }
    Write-Host "DIR_COUNT          : $($dirs.Count)"
} catch {
    Write-Host "DIR_ENUM_ERROR     : $_"
}

# ---------------------------------------------------------------------------
# SECTION 3 – Top-level files
# ---------------------------------------------------------------------------
Write-Section "TOP-LEVEL FILES"
try {
    $rootFiles = Get-ChildItem -LiteralPath $sourcesDir -File -ErrorAction Stop |
                 Sort-Object Name
    if ($rootFiles.Count -eq 0) {
        Write-Host "FILE_ENUM          : (no root-level files found)"
    }
    foreach ($f in $rootFiles) {
        Write-Host "ROOT_FILE_PRESENT  : $($f.Name)"
    }
    Write-Host "ROOT_FILE_COUNT    : $($rootFiles.Count)"
} catch {
    Write-Host "ROOT_FILE_ENUM_ERROR: $_"
}

# ---------------------------------------------------------------------------
# SECTION 4 – Sentinel file checks
# ---------------------------------------------------------------------------
Write-Section "SENTINEL FILE CHECKS"
Write-Host ""
Write-Host ("{0,-45} {1,-8} {2,-10} {3}" -f "PATH", "EXISTS", "EXPECTED", "OUTCOME")
Write-Host ("{0,-45} {1,-8} {2,-10} {3}" -f ('-' * 44), ('─' * 7), ('─' * 9), ('─' * 14))

$results    = [System.Collections.Generic.List[object]]::new()
$passCount  = 0
$failCount  = 0

foreach ($entry in $sentinels.GetEnumerator()) {
    $r = Test-Sentinel -relativePath $entry.Key -expectIn $entry.Value.ExpectIn -mode $sparseMode
    $results.Add($r)

    $existsTxt   = if ($r.Present)  { 'YES' }  else { 'NO' }
    $expectedTxt = if ($r.Expected) { 'YES' }  else { 'NO' }
    Write-Host ("{0,-45} {1,-8} {2,-10} {3}" -f $r.Path, $existsTxt, $expectedTxt, $r.Outcome)

    if ($r.Outcome -eq 'PASS') { $passCount++ } else { $failCount++ }
}

# ---------------------------------------------------------------------------
# SECTION 5 – Content spot-check (read sentinel strings from select files)
# ---------------------------------------------------------------------------
Write-Section "CONTENT SPOT-CHECK"
$spotFiles = @(
    'CDN/cdnfile1.txt',
    'CDN/nested/cdnfile2.txt',
    'FolderA/a1.txt',
    'RootFile1.yml'
)
foreach ($rel in $spotFiles) {
    $fp = Join-Path $sourcesDir ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $fp -PathType Leaf) {
        $sentinel = Select-String -LiteralPath $fp -Pattern 'SENTINEL:' -ErrorAction SilentlyContinue |
                    Select-Object -First 1
        $tag = if ($sentinel) { $sentinel.Line.Trim() } else { '(no SENTINEL line found)' }
        Write-Host "CONTENT_CHECK      : $rel -> $tag"
    } else {
        Write-Host "CONTENT_CHECK      : $rel -> (file not present - skipped)"
    }
}

# ---------------------------------------------------------------------------
# SECTION 6 – Git sparse-checkout introspection
# ---------------------------------------------------------------------------
Write-Section "GIT SPARSE-CHECKOUT INTROSPECTION"
Push-Location $sourcesDir
try {
    $sparseList = & git sparse-checkout list 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GIT_SPARSE_LIST    :"
        $sparseList | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "GIT_SPARSE_LIST    : (not in sparse-checkout mode or git < 2.26)"
    }

    $coneMode = & git config core.sparseCheckoutCone 2>&1
    Write-Host "GIT_CONE_MODE      : $coneMode"

    $sparseFlag = & git config core.sparseCheckout 2>&1
    Write-Host "GIT_SPARSE_FLAG    : $sparseFlag"
} catch {
    Write-Host "GIT_INTROSPECT_ERR : $_"
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# SECTION 7 – Evidence summary
# ---------------------------------------------------------------------------
Write-Section "EVIDENCE SUMMARY"
Write-Host "SUMMARY_MODE       : $sparseMode"
Write-Host "SUMMARY_PASS       : $passCount"
Write-Host "SUMMARY_FAIL       : $failCount"
Write-Host ""

switch ($sparseMode) {
    'FULL-CHECKOUT' {
        Write-Host "EXPECTED_BEHAVIOUR : All repository files should be present."
        Write-Host "EXPECTED_BEHAVIOUR : CDN/, FolderA/, FolderB/ all materialised."
        Write-Host "EXPECTED_BEHAVIOUR : All root-level files present."
        Write-Host "PROOF_POSITIVE     : All PASS rows, zero FAIL rows."
    }
    'SPARSE-DIRECTORIES' {
        Write-Host "EXPECTED_BEHAVIOUR : sparseCheckoutDirectories=CDN (cone mode)."
        Write-Host "EXPECTED_BEHAVIOUR : CDN/ materialised; FolderA/ and FolderB/ absent."
        Write-Host "EXPECTED_BEHAVIOUR : Root-level files PRESENT (cone-mode always includes root)."
        Write-Host "CONE_MODE_NOTE     : git cone mode materialises ALL root-level tracked files."
        Write-Host "PROOF_POSITIVE     : RootFile1.yml PRESENT + FolderA/a1.txt ABSENT."
    }
    'SPARSE-PATTERNS' {
        Write-Host "EXPECTED_BEHAVIOUR : sparseCheckoutPatterns=CDN/** (non-cone / pattern mode)."
        Write-Host "EXPECTED_BEHAVIOUR : Only paths matching CDN/** are materialised."
        Write-Host "EXPECTED_BEHAVIOUR : Root-level files ABSENT (pattern mode does not include root)."
        Write-Host "EXPECTED_BEHAVIOUR : FolderA/ and FolderB/ absent."
        Write-Host "PROOF_POSITIVE     : RootFile1.yml ABSENT + CDN/cdnfile1.txt PRESENT."
    }
    'SPARSE-BOTH-PATTERNS-WIN' {
        Write-Host "EXPECTED_BEHAVIOUR : BOTH sparseCheckoutDirectories=FolderA AND sparseCheckoutPatterns=CDN/** set."
        Write-Host "EXPECTED_BEHAVIOUR : Azure DevOps uses sparseCheckoutPatterns; directories ignored."
        Write-Host "EXPECTED_BEHAVIOUR : CDN/ materialised; FolderA/ ABSENT (proves directories ignored)."
        Write-Host "EXPECTED_BEHAVIOUR : Root-level files ABSENT (pattern mode)."
        Write-Host "PROOF_POSITIVE     : FolderA/a1.txt ABSENT + CDN/cdnfile1.txt PRESENT + RootFile1.yml ABSENT."
    }
    default {
        Write-Host "EXPECTED_BEHAVIOUR : Unknown mode - manual inspection required."
    }
}

Write-Host ""
Write-Host "##[section]Workspace inspection complete."
exit 0
