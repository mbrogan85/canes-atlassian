function Get-ConfluencePageHtml {
    <#
        .SYNOPSIS
        Get the modified html needed to pass to New-ConfluenceTestPage

        .DESCRIPTION 
        Uses the template.html and substitutes values obtained from pullrequests, jiraID's and the differences in tracked media

        .PARAMETER pullRequests
        Dictionary of the BitBucket api return object

        .PARAMETER jiraIDs
        String array of the jira issues with pull requests in the test branch

        .PARAMETER MediaDiff
        Dictionary object containing ISO files which were .added or .removed between release and test branch

        .OUTPUTS
        String - RAW html which is the confluence page content
    #>
    param (
        [Parameter()]
        [PSCustomObject]
        $pullRequests,
        [Parameter()]
        [string[]]
        $jiraIDs,
        [Parameter()]
        [PSCustomObject]        
        $MediaDiff
    )
    $baseHtml = Get-Content .\html\template.html -Raw
    $updatedObjects = @{
        PullRequestTable = New-PullRequestTable $pullRequests
        jiraTestBranch   = New-JiraTestBranchMacro -JiraIDs $jiraIDs
        MediaDiffTable   = New-MediaDiffTable $MediaDiff
        TOCID            = Get-UUID
        ExpandID         = Get-UUID
        BugsID           = Get-UUID
    }
    $outHtml = $baseHtml
    foreach ($key in $updatedObjects.Keys) {
        $outHtml = $outHtml.Replace("%$key%", $updatedObjects["$key"])
    }
    return $outHtml
}
function Get-UUID {
    <#
        .SYNOPSIS
        Returns a randomized GUID to ensure uniqueness when posting to confluence
    #>
    return [System.Guid]::NewGuid().Guid
}
function New-JiraTestBranchMacro {
    <#
        .SYNOPSIS
        creates a Confluence Jira Issue macro object from input JiraIDs

        .PARAMETER JiraIDs
        String array of jira tickets in the test branch

        .OUTPUTS
        String HTML of macro
    #>
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string[]]
        $JiraIDs
    )
    $macroHtml = Get-Content .\html\jira-testbranch.html -Raw
    $UUID = Get-UUID
    $macroHtml = $macroHtml.Replace("%jira-testbranchArray%", $JiraIDs -join ",")
    $macroHtml = $macroHtml.Replace("%UUID%", $UUID)
    return $macroHtml
}
    
function Get-PullRequestAttribute {
    <#
        .SYNOPSIS
        Parses the pull request 'description' for Validation and Platform specifications needed for testing

        .PARAMETER pullRequest
        Dictionary of the BitBucket api return object

        .PARAMETER Attribute
        Desired return value
    #>
    param (
        $pullRequest,
        [Parameter()]
        [ValidateSet("Validation", "Platform")]
        $Attribute
    )
    $description = $pullRequest.description
    switch ($Attribute) {
        "Validation" {
            $searchStr = "**Validation Instructions:**"
            break
        }
        "Platform" {
            $searchStr = "**Applicable Platforms/Enclaves:**"
            break
        }
    }
    $start = $description.indexOf($searchStr) + $searchStr.Length
    $length = ($description.substring($start)).indexOf("`n")
    return $description.substring($start, $length)
}

function New-PullRequestTable {
    <#
        .SYNOPSIS
        Builds the pull request table in html    

        .DESCRIPTION
        Breaks down pull request into table attributes.  Using value substitution, creates the table in html row by row and inserts <table>...</table> to the template

        .PARAMETER pullRequests_testBranch
        Dictionary of the BitBucket api return object.  Modified to include 'JiraID' as a key.

        .OUTPUTS
        string html of pull request table
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]
        $pullRequests_testBranch
    )
    $i = 1 #used in row numbering
    $x = 1 #used as ID of Merge checkbox
    $pullrequest_rows = @()
    foreach ($pullRequest in $pullRequests_testBranch) {
        $y = $x + 1 #used as ID of Defer checkbox
        $pr = @{ 
            PR         = $pullRequest.id
            PRurl      = $pullRequest.links.self.href
            Validation = Get-PullRequestAttribute -pullRequest $pullRequest -Attribute Validation
            Platform   = Get-PullRequestAttribute -pullRequest $pullRequest -Attribute Platform
            jiraID     = $pullRequest.JiraID
            UUID       = Get-UUID
            i          = $i
            x          = $x
            y          = $y
        }
        $pullrequest_rows += "$(New-PullRequestRow $pr)`n"
        $x = $x + 2
        $i++
    }
    $tableHtml = Get-Content .\html\pullrequest-table.html
    $outHtml = $tableHtml[0..$($tableHtml.Count - 2)] + $pullrequest_rows + $tableHtml[-1]
    return $outHtml    
}
function New-PullRequestRow {
    <#
        .SYNOPSIS
        Returns html of an individual table row. <tr>...</tr>

        .PARAMETER PullRequest
        The pull request dictionary object modified to include the JiraID key

        .OUTPUTS
        String html for a table row
    #>
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [PSCustomObject]
        $PullRequest
    )
    begin {
        $rowHtml = Get-Content .\html\pullrequest-table-row.html -Raw
        $outHtml = $rowHtml
    }
    process {
        foreach ($key in $PullRequest.Keys) {
            $outHtml = $outHtml.Replace("%$key%", $PullRequest["$key"])
        }
        return $outHtml
    }
}

function New-MediaDiffTable {
    <#
        .SYNOPSIS
        Returns the html from <table>...</table> for the table accounting for the different isos between release and test branches

        .PARAMETER MediaDiff
        Dictionary object with added and removed isos (as string arrays)

        .NOTES
        Helper function of Get-ConfluencePageHtml
    #>
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]
        $MediaDiff
    )
    $tableHtml = Get-Content .\html\media-diff.html
    $rowsHtml = New-MediaDiffRow $MediaDiff
    $outHtml = $tableHtml[0..$($tableHtml.Count - 2)] + $rowsHtml + $tableHtml[-1]
    return $outHtml
}
function New-MediaDiffRow {
    <#
        .SYNOPSIS
        Returns the html from <tr>..</tr> to indicate which media files have been updated since most recent release
        
        .NOTES
        Helper function of New-MediaDiffTable
    #>
    param (
        [Parameter()]
        [PsCustomObject]
        $row
    )
    $rowHtml = get-content .\html\media-diff-row.html -Raw
    $outHtml = $rowHtml
    $content = @{}
    foreach ($key in $row.Keys) {
        $value = ($row["$key"] -join "<br />")
        $content.Add($key, $value)
    }
    foreach ($key in $content.Keys) {
        $outHtml = $outHtml.Replace("%$key%", $content["$key"])
    }
    return $outHtml
}