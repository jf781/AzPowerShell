function Import-AzTagsFromCsv {
  <#
    .SYNOPSIS
      This script will take a list resources and associated tags from the a CSV file.  It will do the following tasks:

        1. Read the data from the CSV file
        2. Determine the unique resources
        3. Determine all tags associated with the resource
        4. Add tags to the resource using the merge operation.

      If there are any existing thats tags that are not defined in the CSV file they will remaian as is.  


    .DESCRIPTION
      This script does not install or make any changes.   It does have the following requirements that if not met, will stop the script from running
      - Running in PowerShell 5.1 or newer context
      - The following modules need to be installed
          - Az.Resources

        
    .PARAMETTER filePath
      Specifies the path to the CSV file

    .OUTPUTS
      There is not output of this script. 

    .NOTES
        Version:        1.0
        Author:         Joe Fecht - AHEAD, llc.
        Creation Date:  Aprili 2021
        Purpose/Change: Initial deployment
    
    .EXAMPLE
        Create-AzTagReport
    #>
  [CmdletBinding()]
  param (
    [Parameter(
      Mandatory = $true,
      ValueFromPipeline = $true
    )]
    [string]
    $filePath
  )
  process {
    #----------------------------------------------------------------------------------------
    # Utility Functions 
    #----------------------------------------------------------------------------------------

    # Ensures minimum version of PowerShell is installed
    function Confirm-PSVersion {
      [CmdLetBinding()]
      param (
      )
      PROCESS {
        Write-Verbose "Testing to see if PowerShell v5.1 or later is installed"
        try { 
          Write-Verbose "Testing to see if PowerShell v5.1 or later is installed"
          If ($PSVersionTable.PSVersion.Major -ge "6") {
            Write-Verbose "PSVersion is 6 or newer"
            $compatible = $true
          }
          ElseIf ($PSVersionTable.PSVersion.Major -eq "5") {
            If ($PSVersionTable.PSVersion.Minor -ge "1") {
              Write-Verbose "PS Verion is 5.1 or newer"
              $compatible = $true
            }
            Else {
              Write-Verbose "PS Version is v5 but not 5.1 or newer"
              $compatible = $false
            }
          }
          Else {
            Write-Verbose "PS Version is 4 or later"
            $compatible = $false
          }
        }
        catch {
          Write-Verbose "In Catch block.  Error occurred determining PS Version"
          Write-Host "Error determining PowerShell version" -ForegroundColor Red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          break
        }
        return $compatible
      }   
    }

    # Ensures the necessary PowerShell modules are installed
    function Confirm-ModulesInstalled {
      [CmdLetBinding()]
      param (
        [Parameter(
          Mandatory = $false,
          ValueFromPipeline = $true
        )]
        [string[]]
        $modules
      )
      PROCESS {
        Write-Verbose "Testing if Modules are installed"
        $results = @()
        foreach ($module in $modules) {
          try {
            Write-Verbose "Testing for module $module"
            Import-Module -Name $module -ErrorAction SilentlyContinue
            if (Get-Module -Name $module) {
              Write-Verbose "Module $module is installed"
              $moduleTests = [PSCustomObject]@{
                ModuleName = $module
                Installed  = $true
              }
            }
            Else {
              Write-Verbose "Module $module is NOT installed"
              $moduleTests = [PSCustomObject]@{ 
                ModuleName = $module
                Installed  = $false
              }
            }
            $results += $moduleTests
                        
          }
          catch {
            Write-Verbose "Error checking for $module"
            Write-Host "Error checking for module - $module" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
          }
        }            
        return $results
      }
    }

    # Changes the AzContext
    function Update-AzContext {
      [CmdLetBinding()]
      param(
        [Parameter(
          Mandatory = $false,
          ValueFromPipeline = $true
        )]
        [string]
        $SubscriptionId,
        [Parameter(
          Mandatory = $false,
          ValueFromPipeline = $true
        )]
        [string]
        $SubscriptionName
      )
      process {
        if($subscriptionName){
          $currentSubName = (Get-AzContext).Subscription.Name
          if($currentSubName -eq $SubscriptionName){
            Write-Debug "Current Sub: $currentSubName is the same as $SubscriptionName.  Not changing context"
          }
          else{
            Write-debug "Current sub: $currentSubName is not the same as $subscriptionName.  Updating context to new $SubscriptiionName"
            Set-AzContext -SubscriptionName $SubscriptionName 
          }
        }
        elseif($SubscriptionId){
          $currentSubId = (Get-AzContext).Subscription.Id
          if ($currentSubId -eq $SubscriptionId) {
            Write-Debug "Current Sub: $currentSubId is the same as $SubscriptionId.  Not changing context"
          }
          else {
            Write-debug "Current sub: $currentSubId is not the same as $SubscriptionId.  Updating context to new $SubscriptiionName"
            Set-AzContext -SubscriptionId $SubscriptionId 
          }
        }
        else{
          Write-Debug "Neither SubscriptionId or $subscriptionName Defined.  No changes made."
        }
      }
    }

    # Module to import CSV File
    function Get-CsvFile {
      [CmdLetBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [string]
        $csvFilePath
      )
      process {
        try {
          if (Test-Path -Path $csvFilePath) {
            $csvFile = Import-Csv -Path $csvFilePath
            return $csvFile
          }
          Else {
            Write-Output "Failed to validate path to $csvFilePath"
          }
        }
        catch {
          Write-Verbose "Error getting CSV file"
          Write-Host "Error getting CSV file for path $csvFilePath" -ForegroundColor Red
          Write-Host "Error Msg: $_" -ForegroundColor Red
        }
      }
    }


    # Module to determine unique resources in CSV file
    function Group-ResourceIds {
      <#
        Returns a list of unique resource IDs that are provided
      #>
      [CmdLetBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [PSCustomObject]
        $list
      )
      process {
        $resourceIdList = New-Object System.Collections.Generic.List[System.Object]
        foreach ($resource in $list) {
          $resourceId = $resource.ResourceID
          if ($resourceIdList.Contains($resourceId)) {
            Write-Debug "`$resourceIds already contains $resourceId"
          }
          else{
            Write-Debug "Adding $resourceId to list"
            $resourceIdList.Add($resourceId)
          }
        }
        return $resourceIdList
      }
    }


    # Module to get all tags that are defined in the file for a given resource
    function Group-TagS {
      <#
        Groups tags associated with each resource record
      #>
      [CmdLetBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [string]
        $resource,
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [PSCustomObject]
        $list
      )
      process{
        $output = @{}
        $tags = $list | Where-Object -Property ResourceId -EQ $resource
        Write-Debug "Tags is set to $tags"

        foreach ($tag in $tags){
          $key = $tag.TagKey
          $value = $tag.TagValue
          Write-Debug "Key is set to $key.  Value is set to $value"

          $output.Add($key, $value)

        }
        return $output

      }
    }

    #----------------------------------------------------------------------------------------
    # Main Function
    #----------------------------------------------------------------------------------------


    Write-Debug "Ensure the proper version of PowerShell is installed"
    Write-Verbose "Ensure PowerShell 5.1 or later is installed"
    If (Confirm-PSVersion) {
      Write-Verbose "PowerShell 5.1 or later is installed"
    }
    Else {
      Write-Verbose "A later version of PowerShell is installed"
      Write-Host "The version of PowerShell is older then what is supported.  Please updated to a version 5.1 or newer of PowerShell" -ForegroundColor Yellow
      Write-Host "Please visit the site below for details on the current version of PowerShell (As of December 2019)" -ForegroundColor Yellow
      Write-Host "https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-6" -ForegroundColor Green
      Write-Host "Script is exiting" -ForegroundColor Yellow
      Exit
    }


    Write-Verbose "Ensuring the necessary PowerShell Modules are installed"
    $installedModules = Confirm-ModulesInstalled -modules Az.Resources
    $modulesNeeded = $False

    foreach ($installedModule in $installedModules) {
      $moduleName = $installedModule.ModuleName
      If ($installedModule.installed) {
        Write-Verbose "$moduleName is installed"
      }
      Else {
        Write-Verbose "$moduleName is not installed"
        Write-Host "The PowerShell Module: $moduleName is not installed.  Please run the command below to install the module" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "     Install-Module -Name $moduleName -Repository PSGallery" -ForegroundColor Green
        Write-Host ""
        $modulesNeeded = $true
      }
    }

    If ($modulesNeeded) {
      Write-Host "Please install the modules listed above and then run the script again" -ForegroundColor Yellow
      Exit
    }

    # Defining all variables
    $file = get-csvFile -csvFilePath $filePath

    $uniqueResources = Group-ResourceIds -list $file

    foreach ($resource in $uniqueResources) {
      $subId = ($resource).Split("/")[2]
      Update-AzContext -subscriptionID $subId
      $updatedTags = Group-TagS -resource $resource -list $file

      Update-AzTag -ResourceId $resource -Tag $updatedTags -Operation Merge
    }

  }
}