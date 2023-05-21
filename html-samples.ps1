function Get-ConfluencePageHtml {
    param (
        $pullRequests_testBranch,
        $jiraIDs,
        $MediaDiff
    )
    $baseHtml = Get-Content .\html\template.html -Raw
    $updatedObjects = @{
        PullRequestTable = New-PullRequestTable $pullRequests_testBranch
        jiraTestBranch   = New-JiraTestBranchMacro $jiraIDs
        MediaDiffTable   = New-MediaDiff $MediaDiff
    }
    $outHtml = $baseHtml
    foreach ($key in $updatedObjects.Keys) {
        $outHtml = $outHtml.replace("$(%$key%)", $updatedObjects[$key])
    }
    return $outHtml
}
function New-JiraTestBranchMacro {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string[]]
        $JiraIDs
    )
    $macroHtml = Get-Content .\html\jira-testbranch.html -Raw
    return $macroHtml.Replace("%jira-testbranchArray%", $JiraIDs -join ",")
}
    
function Get-PullRequestAttribute {
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
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]
        $pullRequests_testBranch
    )
    $i = 1
    $x = 1
    $pullrequest_rows = @()
    foreach ($pullRequest in $pullRequests_testBranch) {
        $x1 = $x + 1
        $pr = @{ #consider function to Get-PullRequestAttribute -Attribute Validation | Platform etc
            PR         = $pullRequest.id
            Validation = Get-PullRequestAttribute -pullRequest $pullRequest -Attribute Validation
            Platform   = Get-PullRequestPlatform -pullRequest $pullRequest -Attribute Platform
            jiraID     = $pullRequest.JiraID
            i          = $i
            x          = $x
            x1         = $x1
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

function New-MediaDiff {
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]
        $MediaDiff
    )
    $tableHtml = Get-Content .\html\media-diff.html
    $contentRows = Format-MediaDiff $MediaDiff
    foreach ($row in $contentRows) {
        $rowsHtml += New-MediaDiffRow $row
    }
    $outHtml = $tableHtml[0..$($tableHtml.Count - 2)] + $rowsHtml + $tableHtml[-1]
    return $outHtml
}
function New-MediaDiffRow {
    param (
        [Parameter()]
        [PsCustomObject]
        $row
    )
    $rowHtml = get-content .\html\media-diff-row.html -Raw
    $outHtml = $rowHtml
    foreach ($key in $row.Keys) {
        $outHtml = $outHtml.Replace("%$key%", $row["$key"])
    }
    return $outHtml
}
function Format-MediaDiff {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]
        $MediaDiff   
    )
    $output = @()
    $Locations += Split-Path $MediaDiff.removed
    $Locations += Split-Path $MediaDiff.added
    $Locations = $Locations | Sort-Object -Unique
    foreach ($Location in $Locations) {
        $output += @{
            Location = $Location
            Removed  = $MediaDiff.removed | Where-Object { Split-Path $_ -like $Location }
            Added    = $MediaDiff.added | Where-Object { Split-Path $_ -like $Location }
        }
    }
    return $output
}