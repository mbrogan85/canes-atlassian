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
    [Parameter]
    [string]
    $TargetBranch = "dev"
)
#region Functions
function Get-OSAHeaders {
    #Gather LDAP/SITC credentials
    $creds = Get-Credential -Message 'Enter LDAP/SITC Credentials'
    $pair = "$($creds.UserName):$($creds.GetNetworkCredential().password)"
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    $basicAuthValue = "Basic $encodedCreds"
    return @{
        Authorization = $basicAuthValue
    }    
}
function Get-CurrentSprint {
    $boardId = 998 #CANES Board
    $start = 0
    $sprints = @()
    do {
        $url = "https://services.csa.spawar.navy.mil/jira/rest/agile/1.0/board/$boardId/sprint/?startAt=$start"
        $params = @{
            Uri     = $url
            Headers = $Headers
        }
        $res = try { Invoke-WebRequest @params | ConvertFrom-Json } catch { $false }
        $sprints += $res.values
        $start += $res.maxResults
    } until ($res.isLast -or !$res)
    return ($sprints | Where-Object { $_.state -eq "active" -and $_.name -like "AIR*" })[0].name
}
function FakeAdd-LinkToPullRequest {
    param(
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]
        $PullRequest
    )
    process {
        if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
        $TestBranchHeader = "## Test Branches:`n`n"
        $confluenceMarkDown = "[$TestBranch]($conflueneUrl)"
        $description = $PullRequest.description
        if ($description -notmatch $TestBranchHeader) {
            $newDescription = "$description`n`n$TestBranchHeader`n`n$confluenceMarkdown`n`n_____"
        }
        else {
            $offset = $TestBranchHeader.ToCharArray().Count
            $splicePoint = $description.IndexOf($TestBranchHeader) + $offset
            $newDescBegin = $description.substring(0, $splicePoint)
            $newDescEnd = $description.substring($splicePoint)
            $newDescription = "$newDescBegin$confluenceMarkdown`n$newDescEnd"
        }
        $PullRequest.version++
        $PullRequest.description = $newDescription
        $body = @($PullRequest.version, $PullRequest.description) | ConvertTo-Json -Compress
        Write-Host $body | ConvertFrom-Json
        return @{StatusCode = 200 }
    }
}
function Add-LinkToPullRequest {
    param(
        [Parameter()]
        [PSCustomObject]
        $PullRequest
    )
    process {
        if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
        $TestBranchHeader = "## Test Branches:`n`n"
        $confluenceMarkDown = "[$TestBranch]($conflueneUrl)"
        $description = $PullRequest.description
        if ($description -notmatch $TestBranchHeader) {
            $newDescription = "$description`n`n$TestBranchHeader`n`n$confluenceMarkdown`n`n_____"
        }
        else {
            $offset = $TestBranchHeader.ToCharArray().Count
            $splicePoint = $description.IndexOf($TestBranchHeader) + $offset
            $newDescBegin = $description.substring(0, $splicePoint)
            $newDescEnd = $description.substring($splicePoint)
            $newDescription = "$newDescBegin$confluenceMarkdown`n$newDescEnd"
        }
        $PullRequest.version++
        $PullRequest.description = $newDescription
        $body = @($PullRequest.version, $PullRequest.description) | ConvertTo-Json -Compress
        $body = @($PullRequest.version, $PullRequest.description) | ConvertTo-Json -Compress
        $url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/pull-request/$($PullRequest.id)"
        $params = @{
            Uri         = $url
            Headers     = $Headers
            Body        = $body
            Method      = "PUT"
            ContentType = "application/json"
        }
        return Invoke-RestMethod @params
    }
}
function New-ConfluenceTestPage {
    param(
        $Repo,
        $TestBranch
    )
    switch ($Repo) {
        "canes-ob2-2" { $version = "SW5"; break }
        "canes-ob2" { $version = "SW4"; break }
        Default { $version = "FixMe" }
    }
    $confluenceTitle = "$version $(Get-CurrentSprint) $TestBranch"
    $confluenceTitle
}
function Get-JiraTicket {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]
        $pullRequest
    )
    process {
        $tmp = ($pullRequest.fromRef.displayId).Substring($pullRequest.fromRef.displayId.IndexOf("/") + 1) -split "-" 
        return $tmp[0..1] -join "-"
    }
}
function Get-RecentReleaseTag {
    $start = 0
    $tags = @()
    do {
        $url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/tags?start=$start"
        $params = @{
            Uri     = $url
            Headers = $Headers
        }
        $res = try { Invoke-WebRequest @params | ConvertFrom-Json } catch { $false }
        $start = $res.nextPageStart
        $tags += $res.values
    } until ($res.isLastPage - !$res)
    if (!($res)) { Write-Host "Unable to retrieve $Repo tags, verify password information and portal access" -ForegroundColor Magenta; return $null }
    $start = 0
    do {
        $url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/commits?at=refs%2Fheads%2F$TargetBranch&start=$start"
        $params = @{
            Uri     = $url
            Headers = $Headers
        }
        $res = Invoke-WebRequest @params | ConvertFrom-Json
        $start = $res.nextPageStart
        $commitIds = $res.values.id
        foreach ($commitId in $commitIds) {
            if ($tags.latestCommit.Contains($commitId)) {
                if ($tags[$($tags.latestCommit.indexOf($commitID))].displayID -match "[A-z]R[0-9]\Z") {
                    $displayID = $tags[$($tags.latestCommit.indexOf($commitID))].displayID
                    return $displayID.substring($displayID.LastIndexOf("_") + 1)
                }
            }
        }
    } until ($res.isLastPage)
    return $null
}
function Get-Subsystem {
    param (
        [Parameter(ValueFromPipeline)]
        [string]
        $JiraID
    )
    process {
        $url = "https://services.csa.spawar.navy.mil/jira/rest/api/2/issue/$JiraID"
        $params = @{
            Uri     = $url
            Headers = $Headers
        }
        $res = try { (Invoke-WebRequest @params | ConvertFrom-Json) }
        catch { $false }
        if (!($res)) {
            Write-Host "Unable to retrieve JIRA issue, verify password information and portal access" -ForegroundColor Magenta
            return $null
        }
        else {
            return $res.fields.components.name
        }
    }
}

#endregion Functions
#region Variables
if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
$1970TimeParams = @{
    Type         = "DateTime"
    ArgumentList = @(1970, 1, 1, 0, 0, 0, 0)
}
#REST API Security protocols
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" #"Ssl3"
Add-Type -AssemblyName System.Security
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
$i = 0
Write-Host "There are $($pullRequests_testBranch.Count) pull requests being tested in $TestBranch, processing pull requests..." -ForegroundColor DarkCyan
foreach ($pullRequest in $pullRequests_testBranch) {
    Add-Member -InputObject $pullRequest -MemberType NoteProperty -Name "JiraID" -Value (Get-JiraTicket($pullRequest)) 
}
$CreatedDate = (New-Object @1970TimeParams).AddMilliseconds($pullRequest.CreatedDate)
$UpdatedDate = (New-Object @1970TimeParams).AddMilliseconds($pullRequest.UpdatedDate)
$ReviewersApproved = $pullRequest.reviewers | Where-Object { $pullRequest.approved -match 'True' }
$ReviewersNeedsWork = $pullRequest.reviewers | Where-Object { $pullRequest.status -match 'NEEDS_WORK' }
$BitBucketPullRequests = @{
    'Title'              = $pullRequest.title
    'CreatedDate'        = $CreatedDate.ToString($dateFormat)
    'UpdatedDate'        = $UpdatedDate.ToString($dateFormat)
    'BranchName'         = $pullRequest.fromRef.displayID
    'MergeTarget'        = $pullRequest.toRef.displayID
    'Author'             = $pullRequest.author.user.displayName
    'ReviewersApproved'  = $ReviewersApproved.user.displayName -join ", "
    'ReviewersNeedsWork' = $ReviewersNeedsWork.user.displayName -join ", "
    'Description'        = $pullRequest.description
}
$BitBucketPullRequests
if ((FakeAdd-LinkToPullRequest($pullRequest)).statusCode -eq 200) {
    Write-Host "$($pullRequest.title) description successfully updated"
}
else {
    Write-Host "$($pullRequest.title) description failed to update"
}
$i++
Write-Progress -Activity "Writing PR $($pullRequest.title) information and updating description..." -PercentComplete ($i * 100 / $pullRequests_testBranch.Count)
#}
#endregion TestBranchCommits