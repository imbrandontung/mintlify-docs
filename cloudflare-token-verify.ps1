# cloudflare-token-verify.ps1
# Diagnose why daily_collector.py cannot fetch Cloudflare Web Analytics.
# Reads token from daily_collector.config.json. Token is NEVER printed.

$ErrorActionPreference = "Stop"
$ConfigPath = Join-Path $PSScriptRoot "daily_collector.config.json"

if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERR] Config not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$token = $cfg.cloudflare_api_token
$accountId = $cfg.cloudflare_account_id
$siteTag = $cfg.cloudflare_site_tag

if ([string]::IsNullOrEmpty($token)) {
    Write-Host "[ERR] cloudflare_api_token is empty in config." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Cloudflare Token Diagnostic ===" -ForegroundColor Cyan
Write-Host "Token length        : $($token.Length) chars"
Write-Host "Token prefix (first4): $($token.Substring(0, [Math]::Min(4, $token.Length)))..."
Write-Host "Account ID          : $accountId"
Write-Host "Site Tag            : $siteTag"
Write-Host ""

# Step 1 - verify token is active
Write-Host "[1/3] Calling /user/tokens/verify ..." -ForegroundColor Yellow
$headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }
try {
    $resp1 = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/user/tokens/verify" `
        -Method Get -Headers $headers -TimeoutSec 15
    if ($resp1.success) {
        Write-Host "  -> success=true, status=$($resp1.result.status), id=$($resp1.result.id)" -ForegroundColor Green
    } else {
        Write-Host "  -> success=false, errors=$($resp1.errors | ConvertTo-Json -Depth 5 -Compress)" -ForegroundColor Red
    }
} catch {
    Write-Host "  -> EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "  -> body: $($sr.ReadToEnd())" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Likely cause: token format is wrong (not an Account API Token)." -ForegroundColor Yellow
    Write-Host "Fix: dash.cloudflare.com -> Profile -> API Tokens -> Create Token" -ForegroundColor Yellow
    Write-Host "     -> 'Custom token' -> Permissions: Account / Account Analytics / Read" -ForegroundColor Yellow
    exit 2
}

# Step 2 - GraphQL Analytics test
Write-Host ""
Write-Host "[2/3] GraphQL Analytics test (rumPageloadEventsAdaptiveGroups) ..." -ForegroundColor Yellow
$today = (Get-Date).ToString("yyyy-MM-dd")
$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$query = @"
query(`$accountTag:String!, `$siteTag:String!, `$start:Date!, `$end:Date!) {
  viewer {
    accounts(filter:{accountTag:`$accountTag}) {
      total: rumPageloadEventsAdaptiveGroups(filter:{siteTag:`$siteTag, date_geq:`$start, date_leq:`$end} limit:1) {
        count
        sum { visits }
      }
    }
  }
}
"@
$body = @{
    query = $query
    variables = @{ accountTag = $accountId; siteTag = $siteTag; start = $yesterday; end = $yesterday }
} | ConvertTo-Json -Depth 10 -Compress

try {
    $resp2 = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/graphql" `
        -Method Post -Headers $headers -Body $body -TimeoutSec 20
    if ($resp2.errors) {
        Write-Host "  -> GraphQL errors: $($resp2.errors | ConvertTo-Json -Depth 5 -Compress)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Most common GraphQL errors:" -ForegroundColor Yellow
        Write-Host "  - 'unauthorized'             -> token missing Account Analytics:Read" -ForegroundColor Yellow
        Write-Host "  - 'no accounts in resp'      -> account_id wrong, or token not scoped to this account" -ForegroundColor Yellow
        Write-Host "  - 'siteTag is invalid'       -> site_tag wrong; copy from dash Analytics -> Web Analytics" -ForegroundColor Yellow
    } else {
        $totalNode = $resp2.data.viewer.accounts[0].total
        if ($null -eq $totalNode) {
            Write-Host "  -> connected, but 0 accounts matched (account_id may be wrong)" -ForegroundColor Yellow
        } else {
            $count = $totalNode[0].count
            $visits = $totalNode[0].sum.visits
            Write-Host "  -> SUCCESS. yesterday=$yesterday pageviews=$count visits=$visits" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  -> EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 3 - summary
Write-Host ""
Write-Host "[3/3] Done. If above shows SUCCESS, daily_collector.py will pick it up next run." -ForegroundColor Cyan
