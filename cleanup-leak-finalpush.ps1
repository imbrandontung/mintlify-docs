## cleanup-leak-finalpush.ps1
## Purpose: Final push after filter-branch. Refresh remote refs, then force-push.
## Standards: ASCII only, PascalCase, try/catch (KB-D02), with proper exit-code checking.
## Note: Avoid the parameter name `$Args` because it collides with the PowerShell automatic variable.

$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BranchName = "main"

Write-Host "==> Working directory: $ScriptDir"
Set-Location -Path $ScriptDir

function Invoke-GitOrFail {
    param(
        [string]$Description,
        [string[]]$GitArgs
    )
    Write-Host "==> $Description"
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

try {
    ## 1. Show current local main HEAD
    Write-Host "==> Local main HEAD:"
    git log -1 --pretty=format:"    %h | %s" main

    ## 2. Fetch origin to refresh refs/remotes/origin/main
    Invoke-GitOrFail -Description "git fetch origin $BranchName" -GitArgs @("fetch", "origin", $BranchName)

    Write-Host "==> Remote (after fetch) origin/$BranchName HEAD:"
    git log -1 --pretty=format:"    %h | %s" "origin/$BranchName"

    ## 3. Force-push the rewritten history
    Invoke-GitOrFail -Description "git push --force origin $BranchName" -GitArgs @("push", "--force", "origin", $BranchName)

    ## 4. Verify
    Invoke-GitOrFail -Description "git fetch origin $BranchName (verify)" -GitArgs @("fetch", "origin", $BranchName)
    $LocalHead  = git rev-parse $BranchName
    $RemoteHead = git rev-parse "origin/$BranchName"
    Write-Host "==> Local  HEAD: $LocalHead"
    Write-Host "==> Remote HEAD: $RemoteHead"
    if ($LocalHead -ne $RemoteHead) {
        throw "HEAD mismatch after push (local=$LocalHead, remote=$RemoteHead)"
    }

    Write-Host ""
    Write-Host "==> SUCCESS. Remote main fully overwritten with cleaned history."
}
catch {
    Write-Host ""
    Write-Host "==> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "==> Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
