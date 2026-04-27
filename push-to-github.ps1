## push-to-github.ps1
## Purpose: Initialize local git repo and push to imbrandontung/mintlify-docs.
## Standards: ASCII only, PascalCase variables, try/catch error handling (KB-D02).

$ErrorActionPreference = "Stop"

$RepoUrl    = "https://github.com/imbrandontung/mintlify-docs.git"
$BranchName = "main"
$CommitMsg  = "revert: remove unsupported integrations.cloudflare key"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Working directory: $ScriptDir"
Set-Location -Path $ScriptDir

try {
    ## 1. git: confirm available
    $GitVersion = git --version
    Write-Host "==> $GitVersion"

    ## 2. git init (idempotent)
    if (-not (Test-Path ".git")) {
        Write-Host "==> git init"
        git init | Out-Null
    } else {
        Write-Host "==> .git already exists, skip init"
    }

    ## 3. ensure default branch is main
    Write-Host "==> git branch -M $BranchName"
    git branch -M $BranchName 2>$null

    ## 4. stage everything
    Write-Host "==> git add ."
    git add .

    ## 5. commit (only if there is something staged)
    $StagedDiff = git diff --cached --name-only
    if ([string]::IsNullOrWhiteSpace($StagedDiff)) {
        Write-Host "==> nothing to commit"
    } else {
        Write-Host "==> git commit"
        git commit -m $CommitMsg
    }

    ## 6. set remote (replace if exists)
    $RemoteList = git remote
    if ($RemoteList -contains "origin") {
        Write-Host "==> git remote set-url origin $RepoUrl"
        git remote set-url origin $RepoUrl
    } else {
        Write-Host "==> git remote add origin $RepoUrl"
        git remote add origin $RepoUrl
    }

    ## 7. push
    Write-Host "==> git push -u origin $BranchName"
    git push -u origin $BranchName

    Write-Host ""
    Write-Host "==> SUCCESS. Repo URL: $RepoUrl"
}
catch {
    Write-Host ""
    Write-Host "==> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "==> Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
