<#
    .DESCRIPTION
        Script creates a confluence page based on repo (ob2 = SW4, ob2-2 = SW5), current Jira Sprint ("Oscar Sprint 4"='OR4') and Test Branch Name
        Processes commits included in test branches to find active pull requests.  Pull Request info used to create table with prefilled attributes
            Jira-ID
            PullRequest Author
            PullRequest ID
        Add link to Confluence test page to each Pull Request

    .PARAMETER Repo
        name of the Repository

    .PARAMETER TestBranch
        Name of the testbranch

    .PARAMETER AddLinksToPullRequest
        Switch.  $true will add links to the confluence page to pull requests

    .EXAMPLE
        New-TestRelease.ps1 -Repo "ob2-2" -TestBranch "Testing-20230424"

    .NOTES
        Script: New-TestRelease.ps1
        CANES Subsystem: AIR
        -------------------------------------------------
        DEPENDENCIES
            N/A
        CALLED BY
            Stand Alone
        -------------------------------------------------
        History:
        Ver	Date	Modifications
        -------------------------------------------------
        0.0.0.1	05/02/2025	MCB: CANES-12345	Minimum Viable Product
    ===================================================================
#>
param(
    [Parameter(Mandatory)]
    [string]
    $Repo,
    [Parameter(Mandatory)]
    [string]
    $TestBranch,
    [Parameter()]
    [string]
    $TargetBranch = "dev",
    [Parameter()]
    [switch]
    $AddLinksToPullRequests
)
#region Functions
. .\src\osaFunctions.ps1
. .\src\htmlFunctions.ps1
#endregion Functions

#region Variables
if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
#$1970TimeParams = @{
#    Type         = "DateTime"
#    ArgumentList = @(1970, 1, 1, 0, 0, 0, 0)
#}
#endregion Variables
#region AllPullRequest

Write-Host "Retrieving pull requests from https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/pull-requests/?at=refs%2Fheads%2F$TargetBranch" -ForegroundColor DarkCyan
$start = 0
$pullRequests = @()
do {
    $url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/pull-requests/?at=refs%2Fheads%2F$TargetBranch&start=$start"
    $params = @{
        Uri     = $url
        Headers = $Headers
    }
    $res = try { (Invoke-WebRequest @params | ConvertFrom-Json) }
    catch { $false } 
    $start = $res.nextPageStart
    $pullRequests += $res.values
} until ($res.isLastPage -or !$res)
if (!$res) {
    Write-Host "Unable to retrieve pull requests, verify password information and portal access" -ForegroundColor Magenta
    exit
}
#endregion AllPullRequests

#region TestBranchCommits
Write-Host "Retrieving $TestBranch commits from https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/commits/?since=$TargetBranch&until=$TestBranch" -ForegroundColor DarkCyan
$start = 0
$commits_testbranch = @()
do {
    $params = @{
        Uri     = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/commits/?since=$TargetBranch&until=$TestBranch&limit=50&start=$start"
        Headers = $Headers    
    }
    $res = try { Invoke-WebRequest @params | ConvertFrom-Json }
    catch { $false }       
    $start = $res.nextPageStart
    $commits_testbranch += $res.values
} until ($res.isLastPage -or !$res)
if (!$res) { 
    Write-Host "Unable to retrieve $TestBranch commits, verify password information and portal access" -ForegroundColor Magenta 
    exit
}
#endregion TestBranchCommits

#region TBPR
#Compare commit hashes in test branch to the commit hash of the pullrequests to determine pull requests are in the TestBranch
$pullRequests_testBranch = @()
$pullRequestCommits = $pullRequests.fromRef.latestCommit | Where-Object { ($commits_testbranch.id).Contains($_) }
$commit = "<commitHash>"
Write-Host "Retrieving pull requests tested in $TestBranch from https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/commits/$commit/pull-requests" -ForegroundColor DarkCyan
ForEach ($commit in $pullRequestCommits) {
    $url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/commits/$commit/pull-requests"
    $params = @{
        Uri     = $url
        Headers = $Headers
    }  
    try { $pullRequests_testBranch += (Invoke-WebRequest @params | ConvertFrom-Json).values }
    catch {
        Write-Host "Unable to retrieve the pull requests tested in $TestBranch, verify password information and portal access" -ForegroundColor Magenta
        exit
    }
}
Write-Host "There are $($pullRequests_testBranch.Count) pull requests being tested in $TestBranch, processing pull requests..." -ForegroundColor DarkCyan
#endregion TBPR

#Add JiraIDs as PR member
foreach ($pullRequest in $pullRequests_testBranch) {
    Add-Member -InputObject $pullRequest -MemberType NoteProperty -Name "JiraID" -Value (Get-JiraIssueID($pullRequest))
    Add-Member -InputObject $pullRequest -MemberType NoteProperty -Name "JiraIssue" -Value  (Get-JiraIssue -issueId $pullRequest.JiraID)
}

#region Create Confluence Page
$ReleaseTag = Get-RecentReleaseTag
$TrackedMedia = Get-TrackedMediaDiff -ReleaseBranch $ReleaseTag -TestBranch $TestBranch
$params = @{
    pullrequest = $pullRequests_testBranch
    jiraIDs     = $pullRequests_testBranch.jiraID
    MediaDiff   = $TrackedMedia
}
$res = (New-ConfluenceTestPage -Repo $Repo -TestBranch $TestBranch -params $params)
#endregion Create Confluence Page

#region Add links to PR's
$confluenceUrl = "$($res._links.base)$($res._links.webui)"
if ($AddLinksToPullRequests) {
    foreach ($pullRequest in $pullRequests_testBranch) {
        Add-LinkToPullRequest -PullRequest $pullRequest -confluenceUrl $confluencUrl -TestBranch $TestBranch
    }
}
#endregion Add links to PR's
Write-Host "Great Success.  Confluence page created: $confluenceUrl"