# Import required modules
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\blob_enum_results"
)

function Test-BlobAccess {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -ErrorAction Stop
        return $response.StatusCode -eq 200
    }
    catch {
        Write-Warning "Unable to access: $Url"
        return $false
    }
}

function Get-BlobContainerContents {
    param(
        [string]$BaseUrl,
        [string]$ApiVersion = "2019-12-12"
    )
    
    try {
        $listUrl = "$BaseUrl`?restype=container&comp=list"
        $response = Invoke-WebRequest -Uri $listUrl -Headers @{"x-ms-version" = $ApiVersion} -ErrorAction Stop
        
        # Create output directory if it doesn't exist
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath | Out-Null
        }
        
        # Save raw XML response
        $response.Content | Out-File "$OutputPath\container_listing.xml"
        
        # Parse XML for better analysis
        $xml = [xml]$response.Content
        $blobs = $xml.EnumerationResults.Blobs.Blob
        
        Write-Host "Found $($blobs.Count) objects in container"
        return $blobs
    }
    catch {
        Write-Error "Failed to enumerate container: $_"
        return $null
    }
}

function Get-BlobVersions {
    param(
        [string]$BaseUrl,
        [string]$ApiVersion = "2019-12-12"
    )
    
    try {
        $versionsUrl = "$BaseUrl`?restype=container&comp=list&include=versions"
        $response = Invoke-WebRequest -Uri $versionsUrl -Headers @{"x-ms-version" = $ApiVersion} -ErrorAction Stop
        
        # Save versions listing
        $response.Content | Out-File "$OutputPath\versions_listing.xml"
        
        # Parse versions
        $xml = [xml]$response.Content
        $versions = $xml.EnumerationResults.Blobs.Blob | Where-Object { $_.VersionId }
        
        Write-Host "Found $($versions.Count) versioned objects"
        return $versions
    }
    catch {
        Write-Error "Failed to enumerate versions: $_"
        return $null
    }
}

function Save-BlobContent {
    param(
        [string]$Url,
        [string]$OutputFile,
        [string]$VersionId,
        [string]$ApiVersion = "2019-12-12"
    )
    
    try {
        $downloadUrl = $Url
        if ($VersionId) {
            $downloadUrl += "?versionId=$VersionId"
        }
        
        $headers = @{
            "x-ms-version" = $ApiVersion
        }
        
        Invoke-WebRequest -Uri $downloadUrl -Headers $headers -OutFile $OutputFile -ErrorAction Stop
        Write-Host "Successfully downloaded: $OutputFile"
    }
    catch {
        Write-Error "Failed to download $Url : $_"
    }
}

# Main execution
$baseUrl = "https://$StorageAccountName.blob.core.windows.net/$ContainerName"

# Test access
if (!(Test-BlobAccess $baseUrl)) {
    Write-Error "Cannot access blob container. Check permissions and container name."
    exit
}

# Get current contents
$currentContents = Get-BlobContainerContents -BaseUrl $baseUrl
if ($currentContents) {
    $currentContents | Format-Table Name, Length, @{
        Label="Last Modified"
        Expression={$_.Properties."Last-Modified"}
    } | Out-File "$OutputPath\current_contents.txt"
}

# Get versions
$versions = Get-BlobVersions -BaseUrl $baseUrl
if ($versions) {
    $versions | Format-Table Name, VersionId, Length | Out-File "$OutputPath\versions.txt"
}

# Look for interesting files
$interestingExtensions = @(".zip", ".ps1", ".json", ".config", ".xml")
$suspiciousFiles = $currentContents + $versions | Where-Object {
    $ext = [System.IO.Path]::GetExtension($_.Name)
    $interestingExtensions -contains $ext
}

if ($suspiciousFiles) {
    Write-Host "Found potentially interesting files:"
    $suspiciousFiles | ForEach-Object {
        $fileName = $_.Name
        $version = $_.VersionId
        Write-Host "- $fileName (Version: $version)"
        
        # Download file
        $outputFile = Join-Path $OutputPath ([System.IO.Path]::GetFileName($fileName))
        if ($version) {
            $outputFile = $outputFile.Replace(".", "_v${version}.")
        }
        Save-BlobContent -Url "$baseUrl/$fileName" -OutputFile $outputFile -VersionId $version
    }
}

Write-Host "Enumeration complete. Results saved to: $OutputPath"