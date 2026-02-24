param(
    # -------------------------------------------------------------------------
    # Authentication
    # -------------------------------------------------------------------------
    [Parameter(Mandatory = $true)]
    [string]$Token,

    # -------------------------------------------------------------------------
    # Single-log debug mode: dump one raw log and exit
    # -------------------------------------------------------------------------
    [int]$SampleBuild = 0,
    [int]$SampleLog   = 0,

    # -------------------------------------------------------------------------
    # Build ID overrides.
    # Defaults are the authoritative evidence runs from the initial demo session.
    # Pass 0 for any pipeline to trigger auto-discovery of its latest run.
    # Pass -AutoDiscover to resolve ALL four pipelines automatically.
    # -------------------------------------------------------------------------
    [int]$FullBuildId      = 705,
    [int]$DirsBuildId      = 709,
    [int]$PatternsBuildId  = 710,
    [int]$BothBuildId      = 712,

    # -------------------------------------------------------------------------
    # When set, ignores all *BuildId parameters and resolves the latest
    # completed successful build for each pipeline definition automatically.
    # Pipeline definition IDs: 71 (full), 72 (dirs), 73 (patterns), 74 (both)
    # -------------------------------------------------------------------------
    [switch]$AutoDiscover
)

$h    = @{ Authorization = "Bearer $Token" }
$BASE = "https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_apis/build/builds"
$DEFS = "https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_apis/build/builds?definitions={0}&statusFilter=completed&resultFilter=succeeded&`$top=1&api-version=7.1"

function Resolve-LatestBuild([int]$definitionId, [string]$label) {
    try {
        $url    = $DEFS -f $definitionId
        $result = Invoke-RestMethod $url -Headers $h
        if ($result.count -gt 0) {
            $id = $result.value[0].id
            Write-Host "  [AutoDiscover] $label → Build $id (definition $definitionId)"
            return $id
        }
    } catch { }
    Write-Host "  [AutoDiscover] WARNING: no successful build found for definition $definitionId ($label)"
    return 0
}

if ($SampleBuild -gt 0) {
    $c = Invoke-RestMethod "$BASE/$SampleBuild/logs/$SampleLog`?api-version=7.1" -Headers $h
    ($c -split "`n") | ForEach-Object { Write-Host $_ }
    return
}

if ($AutoDiscover) {
    Write-Host "Auto-discovering latest successful builds..."
    $FullBuildId     = Resolve-LatestBuild 71 "01-Full-Checkout"
    $DirsBuildId     = Resolve-LatestBuild 72 "02-Sparse-Directories"
    $PatternsBuildId = Resolve-LatestBuild 73 "03-Sparse-Patterns"
    $BothBuildId     = Resolve-LatestBuild 74 "04-Sparse-Both"
}

$builds = [ordered]@{
    $FullBuildId     = "01-Full-Checkout"
    $DirsBuildId     = "02-Sparse-Directories"
    $PatternsBuildId = "03-Sparse-Patterns"
    $BothBuildId     = "04-Sparse-Both"
}

$PATTERN = "DIR_PRESENT|ROOT_FILE_PRESENT|ROOT_FILE_COUNT|DIR_COUNT|CONTENT_CHECK|SENTINEL FILE CHECKS|GIT_CONE_MODE|GIT_SPARSE_FLAG|SUMMARY_MODE|SUMMARY_PASS|SUMMARY_FAIL|PROOF_POSITIVE|EXPECTED_BEHAVIOUR|CONE_MODE_NOTE"

foreach ($id in $builds.Keys) {
    Write-Host ""
    Write-Host ("=" * 70)
    Write-Host "  BUILD $id -- $($builds[$id])"
    Write-Host ("=" * 70)

    try {
        $logList = (Invoke-RestMethod "$BASE/$id/logs?api-version=7.1" -Headers $h).value
        # Search all logs (skip the template expansion log < 50 lines is too small,
        # skip very large ones > 500 which are env/template logs)
        $inspectLog = $null
        foreach ($log in ($logList | Sort-Object lineCount -Descending)) {
            if ($log.lineCount -lt 30) { continue }
            $candidate = Invoke-RestMethod $log.url -Headers $h
            if ($candidate -match 'INSPECTION_MODE\s+:') {
                $inspectLog = $candidate
                Write-Host "  [log id=$($log.id), lines=$($log.lineCount)]"
                break
            }
        }
        if (-not $inspectLog) {
            Write-Host "  WARNING: inspection log not found – dumping all log ids/sizes:"
            $logList | Sort-Object lineCount -Descending | ForEach-Object { Write-Host "    id=$($_.id) lines=$($_.lineCount)" }
            # Fall back: dump the 2nd largest log raw
            $fallback = ($logList | Sort-Object lineCount -Descending | Select-Object -Skip 1 -First 1)
            $inspectLog = Invoke-RestMethod $fallback.url -Headers $h
        }
        $lines = $inspectLog -split "`n"
        $lines | Where-Object { $_ -match $PATTERN } | ForEach-Object {
            ($_ -replace '^\d{4}-\d{2}-\d{2}T[\d:\.Z]+ ', '').Trim()
        }
    } catch {
        Write-Host "ERROR fetching logs: $_"
    }
}
