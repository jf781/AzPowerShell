#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Combines multiple RVTools .xlsx export files into a single Excel file.

.DESCRIPTION
    This script reads all RVTools .xlsx files from a specified directory,
    combines data from matching sheets, and outputs a single consolidated Excel file.

.PARAMETER SourcePath
    Path to the directory containing RVTools .xlsx files. Defaults to current directory.

.PARAMETER OutputFile
    Name of the output file. Defaults to "Combined_RVTools_Export.xlsx"

.PARAMETER Pattern
    File pattern to match. Defaults to "*.xlsx"

.EXAMPLE
    ./Combine-RVTools.ps1
    
.EXAMPLE
    ./Combine-RVTools.ps1 -SourcePath "./exports" -OutputFile "Consolidated.xlsx"
#>

param(
    [string]$SourcePath = ".",
    [string]$OutputFile = "Combined_RVTools_Export.xlsx",
    [string]$Pattern = "*.xlsx"
)

# Check if ImportExcel module is installed
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "ImportExcel module not found. Installing..." -ForegroundColor Yellow
    try {
        Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
        Write-Host "ImportExcel module installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install ImportExcel module. Please install manually: Install-Module -Name ImportExcel -Scope CurrentUser"
        exit 1
    }
}

Import-Module ImportExcel

# Get all Excel files
$excelFiles = Get-ChildItem -Path $SourcePath -Filter $Pattern | Where-Object { $_.Name -ne $OutputFile }

if ($excelFiles.Count -eq 0) {
    Write-Error "No Excel files found in '$SourcePath' matching pattern '$Pattern'"
    exit 1
}

Write-Host "Found $($excelFiles.Count) Excel file(s) to process" -ForegroundColor Cyan
$excelFiles | ForEach-Object { Write-Host "  - $($_.Name)" }

# Create a hashtable to store combined data by sheet name
$combinedData = @{}

# Process each Excel file
foreach ($file in $excelFiles) {
    Write-Host "`nProcessing: $($file.Name)" -ForegroundColor Yellow
    
    try {
        # Get all sheet names in the workbook
        $excel = Open-ExcelPackage -Path $file.FullName
        $sheetNames = $excel.Workbook.Worksheets | Select-Object -ExpandProperty Name
        Close-ExcelPackage $excel
        
        # Process each sheet
        foreach ($sheetName in $sheetNames) {
            Write-Host "  Reading sheet: $sheetName" -ForegroundColor Gray
            
            # Import data from the sheet
            $data = Import-Excel -Path $file.FullName -WorksheetName $sheetName
            
            if ($data) {
                # Initialize array for this sheet if it doesn't exist
                if (-not $combinedData.ContainsKey($sheetName)) {
                    $combinedData[$sheetName] = @()
                }
                
                # Add data to combined collection
                $combinedData[$sheetName] += $data
                Write-Host "    Added $($data.Count) rows" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Warning "Error processing file '$($file.Name)': $($_.Exception.Message)"
    }
}

# Check if output file already exists and remove it
if (Test-Path $OutputFile) {
    Write-Host "`nRemoving existing output file: $OutputFile" -ForegroundColor Yellow
    Remove-Item $OutputFile -Force
}

# Export combined data to a single Excel file
Write-Host "`nCreating combined Excel file: $OutputFile" -ForegroundColor Cyan

$firstSheet = $true
foreach ($sheetName in $combinedData.Keys | Sort-Object) {
    $rowCount = $combinedData[$sheetName].Count
    Write-Host "  Writing sheet: $sheetName ($rowCount rows)" -ForegroundColor Gray
    
    if ($firstSheet) {
        # First sheet - create new file
        $combinedData[$sheetName] | Export-Excel -Path $OutputFile -WorksheetName $sheetName -AutoSize -FreezeTopRow -BoldTopRow
        $firstSheet = $false
    }
    else {
        # Subsequent sheets - append to existing file
        $combinedData[$sheetName] | Export-Excel -Path $OutputFile -WorksheetName $sheetName -AutoSize -FreezeTopRow -BoldTopRow -Append
    }
}

Write-Host "`nSuccess! Combined file created: $OutputFile" -ForegroundColor Green
Write-Host "Total sheets: $($combinedData.Keys.Count)" -ForegroundColor Green
Write-Host "Total rows across all sheets: $(($combinedData.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum)" -ForegroundColor Green