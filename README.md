# azure-blob-enum


```powershell
# Example usage
.\azure-blob-enum.ps1 -StorageAccountName "mbtwebsite" -ContainerName "$web"
```

The script:
1. Tests container accessibility
2. Enumerates current container contents
3. Checks for versioned content
4. Identifies and downloads potentially sensitive files
5. Saves all results to a specified output directory

https://learn.microsoft.com/en-us/rest/api/storageservices/list-blobs?tabs=microsoft-entra-id#uri-parameters
