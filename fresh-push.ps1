## fresh-push.ps1
## Purpose: After deleting and recreating GitHub repo, push current local state as fresh history.
## Pre-req: New empty repo at https://github.com/imbrandontung/mintlify-docs
## Standards: ASCII only, PascalCase, try/catch (KB-D02).

$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoUrl    = "https://github.com/imbrandontung/mintlify-docs.git"
$BranchName = "main"
$CommitMsg  = "Initial commit: bilingual personal-brand site (post-B2 fresh push)"

Write-Host "==> Working directory: $ScriptDir"
Set-Location -Path $ScriptDir

function Invoke-GitOrFail {
    param([string]$Description, [string[]]$GitArgs)
    Write-Host "==> $Description"
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

try {
    ## 1. Wipe local .git to drop all old history
    Write-Host "==> Removing local .git directory (drop old history)"
    if (Test-Path ".git") {
        Remove-Item -Recurse -Force ".git"
    }

    ## 2. Fresh init
    Invoke-GitOrFail -Description "git init" -GitArgs @("init")
    Invoke-GitOrFail -Description "git branch -M $BranchName" -GitArgs @("branch", "-M", $BranchName)

    ## 3. Stage everything (respects .gitignore)
    Invoke-GitOrFail -Description "git add ." -GitArgs @("add", ".")

    ## 4. Single fresh commit
    Invoke-GitOrFail -Description "git commit" -GitArgs @("commit", "-m", $CommitMsg)

    ## 5. Add remote and push
    Invoke-GitOrFail -Description "git remote add origin $RepoUrl" -GitArgs @("remote", "add", "origin", $RepoUrl)
    Invoke-GitOrFail -Description "git push -u origin $BranchName" -GitArgs @("push", "-u", "origin", $BranchName)

    ## 6. Verify
    $LocalHead  = git rev-parse $BranchName
    Write-Host "==> Local HEAD: $LocalHead"
    Write-Host "==> Verify commit count = 1"
    git log --oneline

    Write-Host ""
    Write-Host "==> SUCCESS. Fresh repo pushed with single commit. Old orphan SHAs are gone forever."
}
catch {
    Write-Host ""
    Write-Host "==> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "==> Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
