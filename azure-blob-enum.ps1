#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\blob_enum_results",
    
    [Parameter(Mandatory=$false)]
    [string[]]$FilePatterns = @(
        '\.zip$', '\.ps1$', '\.bak$', '\.config$', '\.json$', '\.env$',
        'password', 'secret', 'key', 'token', 'cred', '\.old$', '\.backup$'
    ),
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDownload,
    
    [Parameter(Mandatory=$false)]
    [switch]$ListOnly,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeAllFiles
)

# Check for xmllint
try {
    $null = & xmllint --version 2>$null
}
catch {
    Write-Error "xmllint is required for this script. Please install libxml2-utils package."
    exit 1
}

function Format-XmlContent {
    param(
        [string]$XmlContent,
        [string]$OutputFile
    )
    
    try {
        # Remove BOM and any leading whitespace
        $cleanXml = $XmlContent -replace "^([^<]*)", ""
        
        # Save raw XML for backup without temp file
        $cleanXml | Set-Content -Path "$OutputFile.raw" -Encoding UTF8 -NoNewline > $null
        
        # Format with xmllint directly
        $cleanXml | & xmllint --format - > $OutputFile 2>$null
    }
    catch {
        Write-Error "Failed to format XML: $_"
    }
}

function Find-InterestingBlobs {
    param(
        [xml]$BlobsXml,
        [string[]]$Patterns
    )
    
    $foundBlobs = @()
    $blobs = $BlobsXml.EnumerationResults.Blobs.Blob
    
    # Group blobs by Name to count unique files and versions
    $allFiles = $blobs | Group-Object Name
    $staticFiles = $allFiles | Where-Object { $_.Group[0].Name -like "static/*" }
    $nonStaticFiles = $allFiles | Where-Object { $_.Group[0].Name -notlike "static/*" }
    
    # Count files with versions
    $versionedFiles = @()
    foreach($fileGroup in $allFiles) {
        $versions = $fileGroup.Group | Select-Object -Property @{
            Name = 'Name'
            Expression = { $_.Name }
        }, @{
            Name = 'Version'
            Expression = { $_.VersionId }
        }, @{
            Name = 'IsCurrent'
            Expression = { $_.IsCurrentVersion }
        }
        
        if ($versions.Count -gt 1 -or ($versions | Where-Object { -not $_.IsCurrent })) {
            $versionedFiles += $fileGroup.Name
        }
    }
    
    Write-Host "`nContainer Analysis:"
    Write-Host "└── Total Entries: $($blobs.Count)"
    Write-Host "    ├── Unique Files: $($allFiles.Count)"
    Write-Host "    │   ├── Static Files: $($staticFiles.Count)"
    Write-Host "    │   └── Non-Static Files: $($nonStaticFiles.Count)"
    Write-Host "    └── Files with Versions: $($versionedFiles.Count)`n"
    
    if ($versionedFiles.Count -gt 0) {
        Write-Host "Versioned Files Found:"
        foreach($file in $versionedFiles) {
            Write-Host "- $file"
        }
        Write-Host ""
    }
    
    # Only process non-static files
    $nonStaticBlobs = $blobs | Where-Object { $_.Name -notlike "static/*" }
    
    foreach ($blob in $nonStaticBlobs) {
        $isInteresting = $IncludeAllFiles
        $matchedPattern = ""
        
        if (-not $IncludeAllFiles) {
            foreach ($pattern in $Patterns) {
                if ($blob.Name -match $pattern) {
                    $isInteresting = $true
                    $matchedPattern = $pattern
                    break
                }
            }
        } else {
            $isInteresting = $true
        }
        
        if ($isInteresting) {
            $foundBlobs += @{
                Name = $blob.Name
                Version = $blob.VersionId
                Size = $blob.Properties.'Content-Length'
                LastModified = $blob.Properties.'Last-Modified'
                IsCurrentVersion = $blob.IsCurrentVersion -eq "true"
                ContentType = $blob.Properties.'Content-Type'
                MD5 = $blob.Properties.'Content-MD5'
                Pattern = $matchedPattern
            }
        }
    }
    
    # Remove duplicates and sort
    $uniqueBlobs = $foundBlobs | Sort-Object { $_.Name }, { -not $_.IsCurrentVersion }, { $_.LastModified } -Descending |
        Group-Object Name | ForEach-Object { $_.Group | Select-Object -First 1 }
    
    return $uniqueBlobs
}

function Save-BlobContent {
    param(
        [string]$BaseUrl,
        [string]$BlobName,
        [string]$OutputFile,
        [string]$VersionId
    )
    try {
        $downloadUrl = "$BaseUrl/$BlobName"
        if ($VersionId) {
            $downloadUrl += "?versionId=$VersionId"
        }
        
        Write-Host "Downloading: $downloadUrl"
        
        $response = Invoke-WebRequest -Uri $downloadUrl -Headers @{
            "x-ms-version" = "2019-12-12"
        } -ErrorAction Stop
        
        [System.IO.File]::WriteAllBytes($OutputFile, $response.Content)
        Write-Host "Saved to: $OutputFile"
    }
    catch {
        Write-Error "Failed to download $BlobName : $($_.Exception.Message)"
    }
}

# Prepare output directory
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

# Build URLs
$baseUrl = "https://$StorageAccountName.blob.core.windows.net"
$containerUrl = "$baseUrl/$ContainerName"

Write-Host "Starting Azure Blob Storage enumeration..."
Write-Host "Storage Account: $StorageAccountName"
Write-Host "Container: $ContainerName"
Write-Host "Base URL: $containerUrl"

try {
    # Get versions listing
    Write-Host "`nQuerying versions..."
    
    $response = Invoke-WebRequest -Uri "$containerUrl`?restype=container&comp=list&include=versions" -Headers @{
        "x-ms-version" = "2019-12-12"
    } -ErrorAction Stop
    
    Format-XmlContent -XmlContent $response.Content -OutputFile "$OutputPath\versions_listing.xml"
    
    if (-not $ListOnly) {
        Write-Host "Getting container listing..."
        $listResponse = Invoke-WebRequest -Uri "$containerUrl`?restype=container&comp=list" -Headers @{
            "x-ms-version" = "2019-12-12"
        } -ErrorAction Stop
        
        Format-XmlContent -XmlContent $listResponse.Content -OutputFile "$OutputPath\container_listing.xml"
    }
    
    # Process blobs
    $versionsXml = [xml]($response.Content -replace "^([^<]*)", "")
    $interestingBlobs = Find-InterestingBlobs -BlobsXml $versionsXml -Patterns $FilePatterns
    
    if ($interestingBlobs.Count -gt 0) {
        foreach ($blob in $interestingBlobs) {
            Write-Host "`nFile: $($blob.Name)"
            Write-Host "Version: $($blob.Version)"
            Write-Host "Size: $($blob.Size) bytes"
            Write-Host "Last Modified: $($blob.LastModified)"
            Write-Host "Current Version: $($blob.IsCurrentVersion)"
            if ($blob.MD5) { Write-Host "MD5: $($blob.MD5)" }
            
            if (-not ($SkipDownload -or $ListOnly)) {
                $outputFile = Join-Path $OutputPath $blob.Name
                Save-BlobContent -BaseUrl $containerUrl -BlobName $blob.Name -OutputFile $outputFile -VersionId $blob.Version
            }
        }
        
        # Export findings to CSV with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $interestingBlobs | 
            Select-Object Name, Version, Size, LastModified, IsCurrentVersion, ContentType, MD5, Pattern |
            Export-Csv -Path "$OutputPath\blob_findings_$timestamp.csv" -NoTypeInformation
    }
    else {
        Write-Host "`nNo files found."
    }
}
catch {
    Write-Error "Failed to enumerate blob storage: $_"
    exit 1
}

Write-Host "`nEnumeration complete. Results in: $OutputPath"
Write-Host "Files created:"
Get-ChildItem $OutputPath | Select-Object Name | ForEach-Object {
    Write-Host "- $($_.Name)"
}