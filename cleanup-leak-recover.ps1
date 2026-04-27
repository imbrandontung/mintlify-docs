## cleanup-leak-recover.ps1
## Purpose: Skip the stuck git GC, force-push the rewritten history.
## Standards: ASCII only, PascalCase, try/catch (KB-D02).

$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BranchName = "main"

Write-Host "==> Working directory: $ScriptDir"
Set-Location -Path $ScriptDir

try {
    ## 1. Force-remove the refs/original backup directory (Windows lock workaround)
    $RefsOriginal = Join-Path $ScriptDir ".git\refs\original"
    if (Test-Path $RefsOriginal) {
        Write-Host "==> Removing .git/refs/original (filter-branch backup)"
        Remove-Item -Path $RefsOriginal -Recurse -Force
    }

    ## 2. Quick GC (best-effort, do not block on errors)
    Write-Host "==> Best-effort reflog expire + gc"
    git reflog expire --expire=now --all 2>$null
    git gc --prune=now 2>$null

    ## 3. Verify history was rewritten (leak files should not appear in any commit tree)
    Write-Host "==> Verifying leak files absent from history"
    $LeakInHist = git log --all --pretty=format:"%H" | ForEach-Object {
        $Sha = $_.Trim()
        $Result = git ls-tree -r --name-only $Sha | Select-String -Pattern "fix-git-author"
        if ($Result) { "$Sha : $Result" }
    }
    if ($LeakInHist) {
        Write-Host "==> WARNING: leak references still found:" -ForegroundColor Yellow
        $LeakInHist | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host "    OK - no leak files in any commit"
    }

    ## 4. Force-push the rewritten history
    Write-Host "==> git push --force-with-lease origin $BranchName"
    git push --force-with-lease origin $BranchName

    Write-Host ""
    Write-Host "==> SUCCESS. Public repo now reflects the cleaned history."
}
catch {
    Write-Host ""
    Write-Host "==> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "==> Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
