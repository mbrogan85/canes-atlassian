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
    [Parameter()]
    [string]
    $TargetBranch = "dev",
    [Parameter()]
    [switch]
    $AddLinksToPullRequests
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
#function FakeAdd-LinkToPullRequest {
#    param(
#        [Parameter(ValueFromPipeline)]
#        [PSCustomObject]
#        $PullRequest
#    )
#    process {
#        if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
#        $TestBranchHeader = "## Test Branches:`n`n"
#        $confluenceMarkDown = "[$TestBranch]($conflueneUrl)"
#        $description = $PullRequest.description
#        if ($description -notmatch $TestBranchHeader) {
#            $newDescription = "$description`n`n$TestBranchHeader`n`n$confluenceMarkdown`n`n_____"
#        }
#        else {
#            $offset = $TestBranchHeader.ToCharArray().Count
#            $splicePoint = $description.IndexOf($TestBranchHeader) + $offset
#            $newDescBegin = $description.substring(0, $splicePoint)
#            $newDescEnd = $description.substring($splicePoint)
#            $newDescription = "$newDescBegin$confluenceMarkdown`n$newDescEnd"
#        }
#        $PullRequest.version++
#        $PullRequest.description = $newDescription
#        $body = @($PullRequest.version, $PullRequest.description) | ConvertTo-Json -Compress
#        Write-Host $body | ConvertFrom-Json
#        return @{StatusCode = 200 }
#    }
#}
function Add-LinkToPullRequest {
    param(
        [Parameter()]
        [PSCustomObject]
        $PullRequest,
        [Parameter()]
        [string]
        $confluencUrl,
        [Parameter()]
        [string]
        $TestBranch
        
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
        $TestBranch,
        $params
    )
    switch ($Repo) {
        "canes-ob2-2" { $version = "SW5"; break }
        "canes-ob2" { $version = "SW4"; break }
        Default { $version = "FixMe" }
    }
    $confluenceTitle = "$version $(Get-CurrentSprint) $TestBranch"
    $parentID = 519735762
    $html = Get-ConfluencePageHtml @params
    [PSCustomObject]$request = @{
        type      = "page"
        title     = "$ConfluenceTitle"
        ancestors = @(
            [PSCustomObject]@{
                id = $parentID 
            })
        space     = @{
            key = "CANES" 
        }
        body      = @{
            storage = [PSCustomObject]@{
                value          = $html
                representation = "storage"
            }
        }
    }
    $url = "https://services.csa.spawar.navy.mil/confluence/rest/api/content/"
    [PSCustomObject]$restMethod = @{
        Uri         = $url
        Method      = "POST"
        ContentType = "application/json"
        Headers     = $Headers
        Body        = $request | ConvertTo-Json -Compress
    }
    return Invoke-RestMethod @restMethod
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
                    return $tags[$($tags.latestCommit.indexOf($commitID))].displayID
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
function Get-OSAHeaders {
    #REST API Security protocols
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls, Ssl3"
    Add-Type -AssemblyName System.Security

    #Gather LDAP/SITC credentials
    $creds = Get-Credential -Message 'Enter LDAP/SITC Credentials'
    $pair = "$($creds.UserName):$($creds.GetNetworkCredential().password)"
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    $basicAuthValue = "Basic $encodedCreds"
    return @{
        Authorization = $basicAuthValue
    }    
}  
function Get-Deltas {
    <#
        .SYNOPSIS
            Parses the JSON object returned by the /bitbucket/rest/api/1.0/BitBucketRepo/diff API call

        .PARAMETER Deltas
           [PSCustomObject] The hashtable representation of the JSON return from the API

        .EXAMPLE
            $LocalDeltas = Get-Deltas -Deltas $Deltas

        .OUTPUTS
            [PSCustomObject]
    #>   
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]
        $Deltas
    )
    $output = @{
        Added   = [string[]]@()
        Removed = [string[]]@()
    }
    $XmlHeader = "<LocalLocation>"
    $Includes = ($Deltas.diffs.hunks.segments | 
        Where-Object { $_.type -like "*ADDED*" -and $_.lines.line -like "*$XmlHeader*CANES_Media\ISO*" }).lines.line
    $Excludes = ($Deltas.diffs.hunks.segments | 
        Where-Object { $_.type -like "*REMOVED*" -and $_.lines.line -like "*$XmlHeader*CANES_Media\ISO*" }).lines.line
    $output.Added = $Includes | Where-Object { $_ -like "*$XmlHeader*" } | ParseFilename
    $output.Removed = $Excludes | Where-Object { $_ -like "*$XmlHeader*" } | ParseFilename
    $output = Remove-DuplicateISOs $output
    return $output
}
function ParseFilename {
    <#
        .SYNOPSIS
            returns the Innertext of <LocalLocation /> and <CloudLocation /> nodes
     
        .PARAMETER str
            the string value of the xml node

        .EXAMPLE
            $LocalDeltas.include += ParseFileName "                 <LocalLocation>CANES_Media\ISO\DSL\APP01.iso</LocalLocation>"
                returns "CANES_Media\ISO\DSL\APP01.iso"

        .OUTPUTS
            [string]
            the JSON object as a hashtable
    #>
    param(
        [Parameter(ValueFromPipeline)]
        [string]
        $str
    )
    begin { $return = @() }
    process {
        $startPos = $str.IndexOf(">") + 1
        $endPos = $str.LastIndexOf("<")
        $return += $str.Substring($startPos, $endPos - $startPos)
    }
    end { return $return }
}
function Remove-DuplicateISOs {
    param (
        [PSCustomObject]$ht,
        [string[]]$excludeArray
    )
    <#
        .SYNOPSIS
            Identifies and removes duplicate items in include and exclude files
    #>
    if ($ht.Added[0].contains("\")) {
        #used for windows FileSystem Paths
        $includeArray = $ht.Added -replace "\\", "\\" #removes escape character for comparison (errors without)
        $excludeArray = $ht.Removed -replace "\\", "\\" #removes escape character for comparison (errors without)
        $tmpArray = $includeArray #saves original include array T
        $includeArray = $includeArray | Where-Object { $excludeArray -notcontains $_ } #removes common item in include and exclude
        $excludeArray = $excludeArray | Where-Object { $tmpArray -notcontains $_ }
        [string[]]$ht.Added = $includeArray -replace "\\\\", "\" #readjusts format before return
        [string[]]$ht.Removed = $excludeArray -replace "\\\\", "\" #readjusts format before return
    }
    elseif ($ht.Added[0].contains("/")) {
        #used for Linux FileSystem Paths (web)
        $includeArray = $ht.include
        $excludeArray = $ht.exclude
        $tmpArray = $includeArray #saves original include array 
        $includeArray = $includeArray | Where-Object { $excludeArray -notcontains $_ } #removes common item in include and exclude
        $excludeArray = $excludeArray | Where-Object { $tmpArray -notcontains $_ }
        [string[]]$ht.Added = $includeArray
        [string[]]$ht.Removed = $excludeArray   
    }
    return $ht
} 

function Get-TrackedMediaDiff {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $ReleaseBranch,
        [Parameter()]
        [string]
        $FilePath = "TrackedMedia.xml"
    )
    if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
    $url = "https://services.csa.spawar.navy.mil/bitbucket/rest/api/1.0/projects/CH/repos/${Repo}/diff/${FilePath}?since=${ReleaseBranch}&until=${TestBranch}"
    $params = @{
        Uri     = $url
        Headers = $Headers
    }

    try { $JsonDeltas = Invoke-WebRequest @params }
    catch {
        $e = $Error[0].Exception[0].Message
        Write-Host "Error received: ${e} Exiting..." -ForegroundColor Red
        return $null
    }
    $Deltas = $JsonDeltas | ConvertFrom-Json
    $LocalDeltas = Get-Deltas -Deltas $Deltas
    $includeTotal = $LocalDeltas.Added.Count
    $excludeTotal = $LocalDeltas.Removed.Count
    Write-Host "There were $includeTotal new files introduced in $TestBranch" -ForegroundColor Green
    Write-Host "There were $excludeTotal files updated or removed in $TestBranch" -ForegroundColor Magenta   
    return $LocalDeltas 
}
. .\html\htmlFunctions.ps1

#endregion Functions

#region Variables
if ($null -eq $Headers) { $Headers = Get-OSAHeaders }
#$1970TimeParams = @{
#    Type         = "DateTime"
#    ArgumentList = @(1970, 1, 1, 0, 0, 0, 0)
#}
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
Write-Host "There are $($pullRequests_testBranch.Count) pull requests being tested in $TestBranch, processing pull requests..." -ForegroundColor DarkCyan
foreach ($pullRequest in $pullRequests_testBranch) {
    Add-Member -InputObject $pullRequest -MemberType NoteProperty -Name "JiraID" -Value (Get-JiraTicket($pullRequest)) 
}
$TrackedMedia = Get-TrackedMediaDiff -ReleaseBranch (Get-RecentReleaseTag)
$params = @{
    pullrequest = $pullRequests_testBranch
    jiraIDs     = $pullRequests_testBranch.jiraID
    MediaDiff   = $TrackedMedia
}
$res = (New-ConfluenceTestPage -Repo $Repo -TestBranch $TestBranch -params $params)
$confluencUrl = "$res._links.base + $res._links.webui"
if ($AddLinksToPullRequests) {
    foreach ($pullRequest in $pullRequests_testBranch) {
        Add-LinkToPullRequest -PullRequest $pullRequest -confluenceUrl $confluencUrl -TestBranch $TestBranch
    }
}
Write-Host "Great Success.  Confluence page created: $confluenceUrl"