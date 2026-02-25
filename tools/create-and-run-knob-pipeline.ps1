$ErrorActionPreference = 'Continue'
$base = "https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_apis"

# ── 1. Pipeline ID is already 16 (created in previous run) ──────────────────
$pipelineId = 16
Write-Host "=== Step 1: Confirm pipeline exists ==="
$existingResp = Invoke-RestMethod -Uri "$base/pipelines?api-version=7.1" -UseDefaultCredentials
$existing = $existingResp.value | Where-Object { $_.id -eq $pipelineId }
if ($existing) {
    Write-Host "PIPELINE_ID      : $($existing.id)"
    Write-Host "PIPELINE_NAME    : $($existing.name)"
} else {
    Write-Host "ERROR: Pipeline $pipelineId not found. Run aborted."
    exit 0
}

# ── 2. Queue a run with agentPoolName variable override ─────────────────────
Write-Host ""
Write-Host "=== Step 2: Queue run ==="
$runBody = @{
    variables = @{
        agentPoolName = @{ value = "Default"; isSecret = $false }
    }
} | ConvertTo-Json -Depth 5

$runResp = Invoke-RestMethod -Uri "$base/pipelines/$pipelineId/runs?api-version=7.1" `
    -Method Post -UseDefaultCredentials -ContentType "application/json" -Body $runBody
Write-Host "RUN_ID           : $($runResp.id)"
Write-Host "RUN_STATE        : $($runResp.state)"
Write-Host "RUN_NAME         : $($runResp.name)"
$runId = $runResp.id

if (-not $runId) {
    Write-Host "ERROR: Queue run failed — no run ID returned."
    exit 0
}

# ── 3. Poll until completed ──────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Step 3: Polling (15-second intervals) ==="
$maxWait = 60   # iterations = 15 minutes max
$i = 0
do {
    Start-Sleep -Seconds 15
    $status = Invoke-RestMethod -Uri "$base/pipelines/$pipelineId/runs/$runId`?api-version=7.1" -UseDefaultCredentials
    $i++
    Write-Host "POLL_$($i.ToString('00'))           : state=$($status.state)  result=$($status.result)"
} until ($status.state -eq "completed" -or $i -ge $maxWait)

Write-Host ""
Write-Host "=== Step 4: Final result ==="
Write-Host "FINAL_STATE      : $($status.state)"
Write-Host "FINAL_RESULT     : $($status.result)"
Write-Host "BUILD_URL        : https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_build/results?buildId=$runId"
