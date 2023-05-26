function Get-PeopleURLs {
    <#
        .SYNOPSIS
            Converts machine friendly https://canes-media.s3-us-gov-west-1.amazonaws.com/path/to/bucket/and/file
            using API tokens to URLs accessible by people authenticating through https://console.amazonaws-us-gov.com
     
        .PARAMETER MachineURL
           [string[]] The array of URL(s) to be converted
            Accepts Pipeline inputs

        .EXAMPLE
            $HumanURLsArray = $MachineURLsArray | Get-PeopleURLs

        .OUTPUTS
            [string]
            the converted URL
    #>   
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $MachineURL
    )
    process {
        $MachinePortal = "https://canes-media.s3-us-gov-west-1.amazonaws.com/"
        $PeoplePortal = "https://console.amazonaws-us-gov.com/s3/object/canes-media?region=us-gov-west-1&prefix="
        $PeoplePrefix = $MachineURL.Replace("$MachinePortal", "")
        return $PeoplePortal + $PeoplePrefix
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
        Added = [string[]]@()
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
    if ($ht.include[0].contains("\")) {
        #used for windows FileSystem Paths
        $includeArray = $ht.include -replace "\\", "\\" #removes escape character for comparison (errors without)
        $excludeArray = $ht.exclude -replace "\\", "\\" #removes escape character for comparison (errors without)
        $tmpArray = $includeArray #saves original include array T
        $includeArray = $includeArray | Where-Object { $excludeArray -notcontains $_ } #removes common item in include and exclude
        $excludeArray = $excludeArray | Where-Object { $tmpArray -notcontains $_ }
        [string[]]$ht.include = $includeArray -replace "\\\\", "\" #readjusts format before return
        [string[]]$ht.exclude = $excludeArray -replace "\\\\", "\" #readjusts format before return
    }
    elseif ($ht.include[0].contains("/")) {
        #used for Linux FileSystem Paths (web)
        $includeArray = $ht.include
        $excludeArray = $ht.exclude
        $tmpArray = $includeArray #saves original include array 
        $includeArray = $includeArray | Where-Object { $excludeArray -notcontains $_ } #removes common item in include and exclude
        $excludeArray = $excludeArray | Where-Object { $tmpArray -notcontains $_ }
        [string[]]$ht.include = $includeArray
        [string[]]$ht.exclude = $excludeArray   
    }
    return $ht
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
function Get-TrackedMediaDiff {
    param(
    [Parameter(Mandatory = $true)]
    [string]
    $TestBranch,
    [Parameter(Mandatory = $true)]
    [string]
    $ReleaseBranch,
    [Parameter(Mandatory)]
    [string]
    $Repo,
    [Parameter()]
    [string]
    $FilePath = "TrackedMedia.xml",
    [HashTable]
    $Headers
    <#[Parameter()]
    [switch]
    $OmitFMC = $false#>
)

    #REST API Security protocols
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls, Ssl3"
    Add-Type -AssemblyName System.Security

    if ($Headers -eq $null) { $Headers = Get-OSAHeaders }
    #endregion init
    #region initialize variables
    $Local = ($Location -eq "Local")
    $Cloud = ($Location -eq "Cloud")
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
        #region omits (Currently Inactive)
        <#
        Certain ISO files are periodically updated and uploaded to AWS S3.  
        However, the filenames remain unchanged as they are updated.
        Thus, changes made to the binary are not reflected in the TrackedMedia.xml
        Switched inputs to force the omission of such files in the output can be leveraged
        If not ommitted in error, they can simply be removed from the output 
    
    if (!$OmitFMC) {
        #items like FMC are added after duplicates are removed, and will be duplicated for testbranch 
        $LocalDeltas.include += "CANES_Media\ISO\OVF\FMC.ISO"
        $LocalDeltas.exclude += "CANES_Media\ISO\OVF\FMC.ISO"
    }
    #>
        #endregion omits
        $includeTotal = $LocalDeltas.include.Count
        $excludeTotal = $LocalDeltas.exclude.Count
        Write-Host "There were $includeTotal new files introduced in $TestBranch" -ForegroundColor Green
        Write-Host "There were $excludeTotal files updated or removed in $TestBranch" -ForegroundColor Magenta   
        return $LocalDeltas 
}
