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
    $TestBranch
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
function Add-LinkToPullRequest {
    param(
        [Parameter()]
        [PSCustomObject]
        $PullRequest
    )
    if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
    $BookEnd = "**Test Branches:**"
    $confluenceMarkDown = "[$conflueneUrl]($TestBranch)"
    $description = $PullRequest.description
    $firstTest = ($description -notcontains $BookEnd)
    $splicePoint = $description.LastIndexOf("\n\n")
    $newDescBegin = $description.substring(0, $splicePoint)
    $newDescEnd = $description.substring($splicePoint + 1, $description.length - $splicePoint)
    if ($firstTest) { 
        $newDescription = "$newDescBegin\n\n$BookEnd $confluenceMarkdown$newDescEnd"
    }
    else {
        $newDescription = "$newDescBegin\n\n, $confluenceMarkdown$newDescEnd"
    }
    $PullRequest.version++
    $PullRequest.description = $newDescription
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
function New-ConfluenceTestPage {
    param(
        $Repo,
        $TestBranch
    )
    switch ($Repo){
        "canes-ob2-2"{$version = "SW5"; break }
        "canes-ob2" { $version = "SW4"; break }
        Default { $version = "FixMe"}
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
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls, Ssl3"
Add-Type -AssemblyName System.Security
#endregion Variables
#region AllPullRequestCommits
$allPullRequestCommits = @()
$url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/pull-requests/"
$params = @{
    Uri     = $url
    Headers = $Headers
}
$allPullRequestCommits = (Invoke-WebRequest @params | ConvertFrom-Json).values.fromRef.latestCommit
#endregion AllPullRequestCommits
#region TestBranchCommits
$start = 0
$commitHashes = @()
do {
    $params = @{
        Uri     = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/commits/?since=dev&until=$TestBranch&limit=50&start=$start"
        Headers = $Headers    
    }
    $commitpage = Invoke-WebRequest @params | ConvertFrom-Json
    if (!$commitpage.isLastPage) {
        $start = $commitPage.nextPageStart
    }
    $commitHashes += $commitpage.values.id
} until ($commitpage.isLastPage)
$testBranchPullRequests = @()
$testBranchPullRequests +=
$allPullRequestCommits | 
Where-Object { $commitHashes.Contains($_) } |
ForEach-Object {
    $url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/$Repo/commits/$($_)/pull-requests"
    $params = @{
        Uri     = $url
        Headers = $Headers
    }  
    Invoke-WebRequest @params
}
$testBranchPullRequests | ForEach-Object {
    Write-Host "Writing PR $($_.title) information and updating description..."
    $CreatedDate = (New-Object @1970TimeParams).AddMilliseconds($_.CreatedDate)
    $UpdatedDate = (New-Object @1970TimeParams).AddMilliseconds($_.UpdatedDate)
    $ReviewersApproved = $_.reviewers | Where-Object { $_.approved -match 'True' }
    $ReviewersNeedsWork = $_.reviewers | Where-Object { $_.status -match 'NEEDS_WORK' }
    $BitBucketPullRequests[$_.id.ToString()] = @{
        'Title'              = $_.title
        'CreatedDate'        = $CreatedDate.ToString($dateFormat)
        'UpdatedDate'        = $UpdatedDate.ToString($dateFormat)
        'BranchName'         = $_.fromRef.displayID
        'MergeTarget'        = $_.toRef.displayID
        'Author'             = $_.author.user.displayName
        'ReviewersApproved'  = $ReviewersApproved.user.displayName -join ", "
        'ReviewersNeedsWork' = $ReviewersNeedsWork.user.displayName -join ", "
        'Description'        = $_.description
    }
    if (Add-LinkToPullRequest($_).statusCode -eq 200) {
        Write-Host "$($_.title) description successfully updated"
    }
    else {
        Write-Host "$($_.title) description failed to update"
    }
}
    #endregion TestBranchCommits