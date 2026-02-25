$ErrorActionPreference = 'Continue'
$base = "https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_apis"
$buildId = 108

# Full timeline with error/warning messages
Write-Host "=== Build $buildId – Full timeline with issues ==="
$tl = Invoke-RestMethod -Uri "$base/build/builds/$buildId/timeline?api-version=7.1" -UseDefaultCredentials
foreach ($rec in ($tl.records | Sort-Object order)) {
    if ($rec.issues -and $rec.issues.Count -gt 0) {
        Write-Host "RECORD           : [$($rec.type)] $($rec.name)"
        Write-Host "  result         : $($rec.result)  state: $($rec.state)"
        foreach ($issue in $rec.issues) {
            Write-Host "  ISSUE          : [$($issue.type)] $($issue.message)"
        }
        Write-Host ""
    }
}

# Also check the build itself for error details
Write-Host "=== Build $buildId – Build-level details ==="
$build = Invoke-RestMethod -Uri "$base/build/builds/$buildId`?api-version=7.1" -UseDefaultCredentials
Write-Host "STATUS           : $($build.status)"
Write-Host "RESULT           : $($build.result)"
Write-Host "REQUESTED_FOR    : $($build.requestedFor.displayName)"
Write-Host "SOURCE_BRANCH    : $($build.sourceBranch)"
Write-Host "SOURCE_VERSION   : $($build.sourceVersion)"
Write-Host "QUEUE_NAME       : $($build.queue.name)"
Write-Host "QUEUE_ID         : $($build.queue.id)"
Write-Host "START_TIME       : $($build.startTime)"
Write-Host "FINISH_TIME      : $($build.finishTime)"
