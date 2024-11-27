# Azure Blob Storage Enumerator

A PowerShell script for enumerating and downloading files from Azure Blob Storage containers, with a focus on discovering versioned and potentially sensitive content.

## Features

- Enumerates Azure Blob Storage containers
- Detects and downloads previous versions of files
- Identifies non-static content separately from web assets
- Supports custom file pattern matching
- Exports findings to CSV with timestamps
- Provides formatted XML listings
- Shows MD5 hashes for downloaded files
- Tree-view container analysis

## Prerequisites

- PowerShell 5.1 or later
- xmllint (libxml2-utils package)
- Network access to Azure Blob Storage

### Installing xmllint

On Kali/Debian/Ubuntu:
```bash
sudo apt-get install libxml2-utils
```

## Usage

Basic usage:
```powershell
.\azure-blob-enum.ps1 -StorageAccountName "storageaccount" -ContainerName "container"
```

With custom patterns:
```powershell
.\azure-blob-enum.ps1 -StorageAccountName "storageaccount" -ContainerName "container" -FilePatterns @("\.pdf$", "\.docx$", "password")
```

List only mode (no downloads):
```powershell
.\azure-blob-enum.ps1 -StorageAccountName "storageaccount" -ContainerName "container" -ListOnly
```

Include all files:
```powershell
.\azure-blob-enum.ps1 -StorageAccountName "storageaccount" -ContainerName "container" -IncludeAllFiles
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| StorageAccountName | Yes | - | Azure Storage account name |
| ContainerName | Yes | - | Container name (use quotes for special containers like '$web') |
| OutputPath | No | .\blob_enum_results | Directory for saving results |
| FilePatterns | No | [predefined patterns] | Array of regex patterns for file matching |
| SkipDownload | No | False | List files without downloading |
| ListOnly | No | False | Only show container listing |
| IncludeAllFiles | No | False | Include all files regardless of patterns |

## Default File Patterns

The script looks for these file types by default:
- ZIP files (\.zip$)
- PowerShell scripts (\.ps1$)
- Backup files (\.bak$)
- Config files (\.config$)
- JSON files (\.json$)
- Environment files (\.env$)
- Files containing sensitive keywords (password, secret, key, token, cred)
- Old/backup files (\.old$, \.backup$)

## Output

The script creates the following files in the output directory:
- versions_listing.xml - Full version history
- container_listing.xml - Current container contents
- blob_findings_[timestamp].csv - Findings report
- Downloaded blob files
- Raw XML listings for reference

## Example Output

```
Starting Azure Blob Storage enumeration...
Storage Account: storageaccount
Container: container
Base URL: https://storageaccount.blob.core.windows.net/container

Container Analysis:
└── Total Entries: 16
    ├── Unique Files: 16
    │   ├── Static Files: 14
    │   └── Non-Static Files: 2
    └── Files with Versions: 1

Versioned Files Found:
- example.zip

File: example.zip
Version: 2024-01-01T00:00:00.0000000Z
Size: 1500 bytes
Last Modified: Mon, 01 Jan 2024 00:00:00 GMT
Current Version: False
MD5: hash==
```

## Contributing

Feel free to submit issues and enhancement requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This tool is for educational and authorized testing purposes only. Always ensure you have permission to access and enumerate Azure storage accounts.