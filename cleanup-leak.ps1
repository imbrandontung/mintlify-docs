## cleanup-leak.ps1
## Purpose: Remove fix-git-author.{ps1,bat} from public repo and scrub from ALL git history.
## Standards: ASCII only, PascalCase, try/catch (KB-D02).

$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LeakFiles   = @("fix-git-author.bat", "fix-git-author.ps1")
$BranchName  = "main"

Write-Host "==> Working directory: $ScriptDir"
Set-Location -Path $ScriptDir

try {
    ## 1. Add to .gitignore so they never get re-committed
    Write-Host "==> Updating .gitignore"
    $GitIgnore = Join-Path $ScriptDir ".gitignore"
    if (Test-Path $GitIgnore) {
        $Content = Get-Content $GitIgnore -Raw
    } else {
        $Content = ""
    }
    foreach ($f in $LeakFiles) {
        if (-not ($Content -match [regex]::Escape($f))) {
            Add-Content -Path $GitIgnore -Value $f
            Write-Host "    + added $f to .gitignore"
        } else {
            Write-Host "    = $f already in .gitignore"
        }
    }

    ## 2. Stage current changes (about.mdx F5 historical certs + .gitignore)
    Write-Host "==> Staging current edits"
    git add .

    ## 3. Remove leak files from index (keep local copies)
    Write-Host "==> git rm --cached leak files"
    foreach ($f in $LeakFiles) {
        git rm --cached $f 2>$null
    }

    ## 4. Commit current edits
    Write-Host "==> Commit current edits"
    git commit -m "chore: add F5 historical certs and stop tracking one-time leak fix scripts"

    ## 5. Filter-branch: remove leak files from ALL history
    Write-Host "==> filter-branch: scrub leak files from full history"
    $Env:FILTER_BRANCH_SQUELCH_WARNING = "1"
    $LeakArgs = ($LeakFiles | ForEach-Object { "'$_'" }) -join " "
    $TreeFilter = "rm -f $LeakArgs"
    git filter-branch -f --tree-filter $TreeFilter --prune-empty -- --all

    ## 6. Cleanup refs
    Write-Host "==> Garbage-collect old refs"
    git for-each-ref --format="%(refname)" refs/original/ | ForEach-Object {
        git update-ref -d $_
    }
    git reflog expire --expire=now --all
    git gc --prune=now --aggressive

    ## 7. Force push (rewriting history)
    Write-Host "==> git push --force-with-lease origin $BranchName"
    git push --force-with-lease origin $BranchName

    Write-Host ""
    Write-Host "==> SUCCESS."
    Write-Host "    Leak files removed from index, .gitignore, and full history."
    Write-Host "    Verify on GitHub: any past .patch should now 404 or no longer reference leak."
}
catch {
    Write-Host ""
    Write-Host "==> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "==> Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
