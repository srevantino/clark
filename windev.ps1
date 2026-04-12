<#
.SYNOPSIS
    Bootstrap the latest pre-release build of A-SYS from GitHub.
.DESCRIPTION
    Developed & managed by Advance Systems 4042.
    Set $ASYSGitHubRepo to your GitHub "owner/repo", then run locally or host this script.
.NOTES
    Replace the placeholder repo before using in production.
#>

$ASYSGitHubRepo = "YOUR_GITHUB_USER/YOUR_REPO"

if ($ASYSGitHubRepo -eq "YOUR_GITHUB_USER/YOUR_REPO") {
    Write-Error "Edit windev.ps1 and set `$ASYSGitHubRepo to your GitHub repository (owner/repo)."
    exit 1
}

$latestTag = (Invoke-RestMethod "https://api.github.com/repos/$ASYSGitHubRepo/tags")[0].name
Invoke-RestMethod "https://github.com/$ASYSGitHubRepo/releases/download/$latestTag/asys.ps1" | Invoke-Expression
