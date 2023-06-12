function Get-CurrentSprint {
    <#
        .SYNOPSIS
        Returns the Name of the current (active) sprint with "AIR" in the name

        .OUTPUTS
        String - sprint name
    #>
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
function Get-JiraIssue {
    <#
        .SYNOPSIS
        Returns the Jira Issue Api Object

        .OUTPUTS
        PSCustomObject - JiraIssue
    #>
    param(
        [Parameter()]
        [string]
        $issueId
    )
    $rtn = @{}
    $url = "https://services.csa.spawar.navy.mil/jira/rest/agile/1.0/issue/$issueId"
    $params = @{
        Uri     = $url
        Headers = $Headers
    }
    $rtn = try { Invoke-WebRequest @params | ConvertFrom-Json } 
    catch { $null }
    return $rtn
} 
function Get-ConfluencePageID {
    param(
        [Parameter()]
        [string]
        $Title
    )
    if ([Net.WebUtility]::UrlDecode($Title) -eq $Title){
        $Title = [Net.WebUtility]::UrlEncode($Title)
    }
    $url = "https://services.csa.spawar.navy.mil/confluence/rest/api/content/?title=$Title"
    $params = @{
        Uri     = $url
        Headers = $Headers
    }
    $res = Invoke-WebRequest @params | ConvertFrom-Json
    return [int]$res.results.id    
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
    <#
        .SYNOPSIS
        If needed, adds a "Test Branches" section to a pull request description and includes a link to the page.

        .PARAMETER PullRequest
        The dictionary object returned from Bitbucket Pullrequest API

        .PARAMETER confluenceUrl
        The string path of the created Confluence Page

        .PARAMETER TestBranch
        The string name of the Test Branch

        .OUTPUTS
        Dictionary object of API Json Return

        .LINK
        https://developer.atlassian.com/server/bitbucket/rest/v810/api-group-pull-requests/#api-api-latest-projects-projectkey-repos-repositoryslug-pull-requests-pullrequestid-put
    #>
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
        return Invoke-RestMethod @params | ConvertFrom-Json
    }
}
function New-ConfluenceTestPage {
    <#
        .SYNOPSIS
        Creates a child Confluence Page of Test Reports. Filled in with TestBranch information

        .PARAMETER Repo
        Name of the repo.  Used in creating page name

        .PARAMETER TestBranch
        Name of the test branch.  Used in creating the page name

        .PARAMETER Params
        Dictorany object with pullrequests, jiraID's and mediadiff associated with test branch

        .OUTPUTS
        Dictionary object of Confluence return 

        .LINK
        https://docs.atlassian.com/atlassian-confluence/REST/5.7.1/#d3e764 description of return output
    #>
    param(
        [Parameter()]
        [string]
        $Repo,
        [Parameter()]
        [string]
        $TestBranch,
        [Parameter()]
        [PSCustomObject]
        $params
    )
    switch ($Repo) {
        "canes-ob2-2" { $version = "SW5"; break }
        "canes-ob2" { $version = "SW4"; break }
        Default { $version = "FixMe" } #used as default for non-standard repo
    }
    $Sprint = Get-CurrentSprint
    $ReleaseSprint = Get-RecentReleaseTag
    $ReleaseSprint = $ReleaseSprint.Substring($ReleaseSprint.LastIndexOf("_") + 1)
    $Phase = ($Sprint -split " ")[1]
    $ParentPageTitle = "$Phase+Phase+Test+Reports"
    $confluenceTitle = "$version - $ReleaseSprint - $TestBranch"
    if (Get-ConfluencePageID -Title $confluenceTitle) {
        #adds timestamp if page already exists
        $confluenceTitle = "$confluenceTitle-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
    $parentID = Get-ConfluencePageID -Title $ParentPageTitle
    $html = Get-ConfluencePageHtml @params
    $request = @{
        type      = "page"
        title     = "$ConfluenceTitle"
        ancestors = @(
            @{
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
        Body        = ($request | ConvertTo-Json -Compress)
    }
    return Invoke-RestMethod @restMethod
}
function Get-JiraIssueID {
    <#
        .SYNOPSIS
        Parses the title of the pull request to return the Jira ID

        .PARAMETER PullRequest
        The pullrequest dictionary object

        .OUTPUTS
        String - JiraID
    #>
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
    <#
        .SYNOPSIS
        Returns the bitbucket tag of the most recent release

        .DESCRIPTION
        Function starts at the branch head and steps backwards through commits to return the most recent commit ending with a phase/sprint indication.

        .PARAMETER Repo
        Name of the repo to obtain latest release commit from

        .OUTPUTS
        String - Release tag name
    #>
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
    <#
        .SYNOPSIS
        Returns the 'component' property of a given Jira issue

        .PARAMETER JiraID
        the Jira unique ID.  i.e. CANES-12345

        .OUTPUTS 
        String - the component i.e. AIR, OE, NI etc.
    #>
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
    <#
        .SYNOPSIS
        Removes duplicates in added and removed arrays.

        .PARAMETER ht
        Dictionary object with the added and removed media.

        .NOTES
        Helper Function of Get-Deltas
    #>
    param (
        [Parameter()]
        [PSCustomObject]
        $ht
    )
    <#
        .SYNOPSIS
            Identifies and removes duplicate items in include and exclude files
    #>
    $includeArray = $ht.Added -replace "\\", "\\" #removes escape character for comparison (errors without)
    $excludeArray = $ht.Removed -replace "\\", "\\" #removes escape character for comparison (errors without)
    $tmpArray = $includeArray #saves original include array T
    $includeArray = $includeArray | Where-Object { $excludeArray -notcontains $_ } #removes common item in include and exclude
    $excludeArray = $excludeArray | Where-Object { $tmpArray -notcontains $_ }
    [string[]]$ht.Added = $includeArray -replace "\\\\", "\" #readjusts format before return
    [string[]]$ht.Removed = $excludeArray -replace "\\\\", "\" #readjusts format before return
    return $ht
} 

function Get-TrackedMediaDiff {
    <#
        .SYNOPSIS
        Return trackedmedia.xml iso's which have been added and/or removed between the ReleaseBranch and the Test Branch

        .PARAMETER ReleaseBranch
        Name of the Release Branch.  Accepts tag names.

        .PARAMETER TestBranch
        Name of the Test Branch i.e. Testing-YYYYMMDD

        .PARAMETER FilePath
        Defaults to TrackedMedia.xml

        .OUTPUTS
        HashTable - returns dictionary object with string array for added, and string array for removed isos      
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $ReleaseBranch,
        [Parameter(Mandatory = $true)]
        [string]
        $TestBranch,
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