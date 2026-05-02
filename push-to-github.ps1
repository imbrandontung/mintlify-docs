## push-to-github.ps1
## Purpose: Initialize local git repo and push to imbrandontung/mintlify-docs.
## Standards: ASCII only, PascalCase variables, try/catch error handling (KB-D02).

$ErrorActionPreference = "Stop"

$RepoUrl    = "https://github.com/imbrandontung/mintlify-docs.git"
$BranchName = "main"
$CommitMsg  = "post: gcnext26-mcp-trust-chain"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Working directory: $ScriptDir"
Set-Location -Path $ScriptDir

try {
    ## 0. Clean up stale lock files (left over from interrupted git ops)
    $LockFiles = @(
        ".git\index.lock",
        ".git\HEAD.lock",
        ".git\refs\heads\main.lock",
        ".git\packed-refs.lock"
    )
    foreach ($Rel in $LockFiles) {
        $Lock = Join-Path $ScriptDir $Rel
        if (Test-Path $Lock) {
            Write-Host "==> removing stale $Rel"
            Remove-Item -Force $Lock
        }
    }

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

    ## 4. stage everything (with exit code check)
    Write-Host "==> git add ."
    git add .
    if ($LASTEXITCODE -ne 0) {
        throw "git add failed with exit code $LASTEXITCODE"
    }

    ## 5. commit (only if there is something staged)
    $StagedDiff = git diff --cached --name-only
    if ([string]::IsNullOrWhiteSpace($StagedDiff)) {
        Write-Host "==> nothing to commit"
    } else {
        Write-Host "==> git commit"
        git commit -m $CommitMsg
        if ($LASTEXITCODE -ne 0) {
            throw "git commit failed with exit code $LASTEXITCODE"
        }
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
    if ($LASTEXITCODE -ne 0) {
        throw "git push failed with exit code $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "==> SUCCESS. Repo URL: $RepoUrl"
}
catch {
    Write-Host ""
    Write-Host "==> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "==> Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
