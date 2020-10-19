#####
# Need to review 
# 1. Data returned.   Some may not be needed (Resource ID, type, DependencyCount, etc..)
# 2. How this can be incorporated with the Test-AzResourceMigration.   This is started in Test-AzResourceMigration_WIP.ps1.
#     - This includes logic so that we will scan a resource group, if it cannot be migrated, then we need run the can against the individual resources within the group
#### 
Function Test-AzResourceMigration {

  [CmdletBinding()]
  Param(
    [Parameter(
      Mandatory = $true)]
    [string]
    $sourceSubscriptionID,
    [Parameter(
      Mandatory = $true)]
    [string]
    $targetSubscriptionID,
    [Parameter(
      Mandatory = $true)]
    [string]
    $targetResourceGroup,
    [Parameter(
      Mandatory = $true)]
    [string]
    $outputPath,
    [Parameter(
      Mandatory = $true)]
    [string]
    $resourceTypeList
  )
  
  process {
    #------------------------------------------------------
    # Define Utility Functions
    #------------------------------------------------------
    function Get-AzCachedAccessToken() {
      $azureContext = Get-AzContext
      $currentAzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
      $currentAzureProfileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($currentAzureProfile);
      $azureAccessToken = $currentAzureProfileClient.AcquireAccessToken($azureContext.Tenant.Id).AccessToken;
      $azureAccessToken
    
    }
    
    function Get-AzBearerToken() {
      $ErrorActionPreference = 'Stop'
      ('Bearer {0}' -f (Get-AzCachedAccessToken))
    }

    function Confirm-OutputPath {
      <#
  .SYNOPSIS
      This will check to see what OS the script is being ran from and ensure that output path is formatted properly and that
      the path will have a trailing slash (either forward or backward depending on the OS)   
  .DESCRIPTION
      This script does not install or make any changes.  It checks to ensure that the path is valid and is formatted properly
      for the OS
  .INPUTS
      path
  .OUTPUTS
      It will output a validated OutputPath variable formatted properly for the OS it is running on

  .NOTES
      Version:        1.0
      Author:         Joe Fecht - AHEAD, llc.
      Creation Date:  December 2019
      Purpose/Change: Initial deployment

  .EXAMPLE
      Confirm-OutputPath -path ~/Documents

      If running on Linux/MacOS it will output a value that shows the current users home directly.   

      /Users/joe/Documents/

      .EXAMPLE
      Confirm-OutputPath -path ~\Documents

      If running on Linux/MacOS it will output a value that shows the current users home directly.   

      C:\Users\joe\Documents\

  #>
      [CmdletBinding()]
      Param(
        [Parameter(
          Mandatory = $true)]
        [string]
        $path
      )

      process {
        # Confirm output path is valid
        try {
          if (Test-Path $path) {
            Write-Verbose "Output path is valid"
          }
          else {
            write-verbose "Output path is invalid"
            Write-Host "Output Path is not valid" -ForegroundColor red
            Write-Host "Output Path set to: $path" -ForegroundColor Red
            Write-Host "Please run execute command again with a valid output path"
            return "invalidPath"
          }          
        }
        catch {
          Write-Verbose "Failed to validate Output Path"
          Write-Host "Unable to validate Output Path: $path" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }

        # Ensure output path has a trailing path separator
        try {
          if ($env:HOME) {
            Write-Verbose "Running in a non-windows environment.  Path seperator is '/'"
            if ($path.endsWith("/")) {
              Write-Verbose "Output path ends with a trailing path separator"
              return $path
            }
            else {
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $path + "/"
              return $updatedOutputPath
            }
          }
          else {
            Write-Verbose "Running in a Windows environment.  Path seperator is '\'"
            if ($path.endsWith("\")) {
              Write-Verbose "Output path ends with a trailing path separator"
              return $path
            }
            else {
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $path + "\"
              return $updatedOutputPath
            }
          }
        }
        catch {
          Write-Verbose "Failed to determine if the output path had a trailing path seperator"
          Write-Host "Unable to validate trailing path seperator for Output Path: $path" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }
      }
    }

    #------------------------------------------------------
    # Main Function
    #------------------------------------------------------
    
    $currentContext = (Get-AzContext | Select-Object Subscription).Subscription.Id
    
    if (!$currentContext) {
      Write-Verbose "Current session does not have an Azure context"
      Login-AzAccount -SubscriptionId $sourceSubscriptionID
    }
    if ($currentContext -ne $sourceSubscriptionID) {
      Write-Verbose "Updating current session context to match the value of the `$sourceSubscriptionId variable"
      Select-AzSubscription -SubscriptionId $sourceSubscriptionID
    }

    # Setting variable values
    $subscriptionName = (Get-AzContext).Subscription.Name
    $date = (get-date).ToShortDateString().replace("/","-")
    $results = @()

    # Getting list of resources Types
    if (Test-Path -Path $resourceTypeList) {
      Write-Verbose "Validated $resourceTypeList is a valid path"
      $resourceTypes = Get-Content -Path $resourceTypeList
    }
    else {
      Write-Verbose "$resourceTypeList is not a valid path.  Exiting"
      Write-Host "$resourceTypeList is not a valid path" -ForegroundColor Red
      Write-Host "Please run run script with a valid path provided for the 'ResourceTypeList' parameter" -ForegroundColor Red
      Write-Host "Exiting.  No resources have been validated" -ForegroundColor Red
      break
    }



    $outputPath = Confirm-OutputPath -path $outputPath

    if($outputPath){
      Write-Verbose "Validated output path.  `$outputPath = $outputPath"
      $resourceGroups = Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName
      Write-Verbose "Resource groups: $resourceGroups"
      
      foreach ($resourceGroup in $resourceGroups){
        $resources = @()
        $resourceIds = @()
        $result = @()
        $resourceId = $null
        $body = $null
        $token = $null
        $return = $null
        $errorMesssage = $null



        Write-Host "Reviewing resources in resource group: $resourceGroup"
        Write-Verbose "In Foreach loop for resource group: $resourceGroup"
        foreach ($resourceType in $resourceTypes){
          Write-Verbose "Getting resources from resource group: $resourceGroup with resource type: $resourceType"
          $rtResources = Get-AzResource -ResourceGroupName "$resourceGroup" -ResourceType "$resourceType"
          $resources += $rtResources
        }
        write-verbose "$resources.name"
        foreach ($resource in $resources) {
          $resourceId = $resource.resourceId
          $resourceIds += $resourceId
        }

        if ($resourceIds -ne $null) {
          write-verbose "Resource group has resources that can be migrated. Proceeding. "
          $token = Get-AzBearerToken
          Write-Verbose "List of resource Ids that we are checking for?"
          Write-Verbose "$resourceIds"
          Write-Host "Checking resource group $resourceGroup"
          $body = @{
            resources           = $resourceIds;
            targetResourceGroup = "/subscriptions/$targetSubscriptionID/resourceGroups/$targetresourceGroup"
          }
          Write-Verbose "Set the body variable to check if the resource can be moved:  `$body:"
          Write-Verbose $body.Values

          Try {
            Write-Verbose "Invoking request to determine if resource be moved"
            $return = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$sourceSubscriptionID/resourceGroups/$resourceGroup/validateMoveResources?api-version=2020-06-01" -method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers @{Authorization = $token }
          }
          Catch {
            Write-Verbose "Error occurred invoking request"
            Write-Verbose "Error message: $_"
            $return = $null
            $return = $_.Exception.Message
          }
          Write-Verbose "`$return = $return.rawcontent"
          if ($return) {
            Write-Verbose "Checking status code.  `$return: $return"
            [int]$retryTime = ($return.RawContent -split "Retry-After: ")[1].Substring(0, 2)
            #$retryTime = $retryTime + 5
      
            do {
              Write-Verbose "In Do loop"
              $rawUrl = ($return.RawContent -split "Location: ")[-1]
              $validationUrl = $rawUrl.split("`n")[0]
              Write-Verbose "URL to validate get status code is $validationUrl"

              Try {
                Write-Verbose "Invoking request to get migration status for"
                $resourceDetails = Invoke-WebRequest -Uri $validationUrl -method Get -ContentType "application/json" -Headers @{Authorization = $token }
                $statusCode = $resourceDetails.StatusCode
              }
              Catch {
                Write-Verbose "Error occurred invoking request"
                Write-Verbose "Error message: $_"
                $statusCode = 205
                $resultsError = $_
                $resultsErrorJson = $resultsError -replace "Invoke-WebRequest: ", "" | ConvertFrom-Json
              }

              Write-Host Waiting for status...
              Start-Sleep -Seconds $retryTime
            }
            while ($statusCode -eq 202)
      
            if ($statusCode -eq 205) {
              Write-Verbose "In If. `$statusCode = $statusCode"
              Write-Verbose "Resource type $($resource.ResourceType) with resource name $($resource.Name)can not be moved."

              if ($resultsErrorJson.error.details.message) {
                Write-verbose "In If.  The move request error has details.message"
                switch -Wildcard ($resultsErrorJson.error.details.message) {
                  "The move resources request does not contain all the dependent resources.*" {
                    Write-Verbose "The resource has dependecies."
                    $errorMessage = $resultsErrorJson.error.details.message | Select-Object -First 1
                    $dependencyCount = $resultsErrorJson.error.details.details | Measure-Object | Select-Object -ExpandProperty Count
                    $ableToMigrate = "Pending Dependencies"
                  }
                  "Cannot move one or more resources in the request. Please check details for information about each resource." {
                    Write-Verbose "The move request message is under details.details"
                    $errorMessage = $resultsErrorJson.error.details.details.message
                    $ableToMigrate = $false
                  }
                  default {
                    Write-Verbose "The move request message is has a standard message"
                    $errorMessage = $resultsErrorJson.error.details.message | Select-Object -First 1
                    $ableToMigrate = $false
                  }
                }
              }
              else {
                Write-Verbose "In Else.  The move request error just has a message."
                $errorMessage = $resultsErrorJson.error.message | Select-Object -First 1
                $ableToMigrate = $false
              }

              $props = [ordered]@{
                AbleToMigrate   = $ableToMigrate
                ResourceName    = $null
                ResourceGroup   = $resourceGroup
                Subscription    = $subscriptionName
                ResourceType    = $null
                ResourceId      = $resourceId
                Notes           = $errorMessage
                DependencyCount = $dependencyCount
              }
              $result = New-Object -TypeName psobject -Property $props
            }
            elseif ($statusCode -eq 204) {
              Write-Verbose "In ElseIf for `$statusCode = 204. `$statusCode = $statusCode"
              Write-Verbose "Resource type $($resource.ResourceType) with resource name $($resource.Name) can be moved to new subscrtipion" 
              $props = [ordered]@{
                AbleToMigrate   = $true
                ResourceName    = $null
                ResourceGroup   = $resourceGroup
                Subscription    = $subscriptionName
                ResourceType    = $null
                ResourceId      = $resourceId
                Notes           = $errorMessage
                DependencyCount = $dependencyCount
              }
              $result = New-Object -TypeName psobject -Property $props
            }
            else {
              Write-Verbose "In Else for `$statusCode. `$statusCode = $statusCode"
              Write-Verbose "Another problem occured for resource type $($resource.ResourceType) with resource name $($resource.Name). Error: $Exc"
              $props = [ordered]@{
                AbleToMigrate = "Error Occurred"
                ResourceName    = $null
                ResourceGroup   = $resourceGroup
                Subscription    = $subscriptionName
                ResourceType    = $null
                ResourceId      = $resourceId
                Notes           = $errorMessage
                DependencyCount = $dependencyCount
              }
              $result = New-Object -TypeName psobject -Property $props
            }
          }else{
            Write-Verbose "Failed to determine if the resource: $resourceId can be migrated"
            Write-Verbose "Failed to determine if the resource: $resourceId can be migrated" 
            Write-Verbose "Error Msg: $_" 

            $props = [ordered]@{
              AbleToMigrate = "Error Occurred"
                ResourceName    = $null
                ResourceGroup   = $resourceGroup
                Subscription    = $subscriptionName
                ResourceType    = $null
                ResourceId      = $resourceId
                Notes           = $errorMessage
                DependencyCount = $dependencyCount
            }
            $result = New-Object -TypeName psobject -Property $props
          }

        }
        else {
          Write-Verbose "`$resouceIds was null.  No resources in the resource group that match the type.  Skipping Resource Group"
          $props = [ordered]@{
              AbleToMigrate = "Empty Resoure Group"
              ResourceName    = $null
              ResourceGroup   = $resourceGroup
              Subscription    = $subscriptionName
              ResourceType    = $null
              ResourceId      = $resourceId
              Notes           = $null
              DependencyCount = $null
          }
          $result = New-Object -TypeName psobject -Property $props
        }
        $results = $results += $result

      }
    }
    else {
      Write-Verbose "Output path invalid.  Exiting"
      break
    }

    Write-Verbose "Exited Foreach statement for resource group"

    try{
      Write-Verbose "Attempting to write date to `$outputPath: $outputPath"
      $subscriptionName = ((Get-AzContext).Subscription.Name -replace ' ', '-' `
          -replace '\\', '-' `
          -replace '/', '-' ).ToLower()
      $fileName = $outputPath + "MigrationPlanningScan-ResourceGroups-" + $subscriptionName + "_" + $date + ".csv"
      $results | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $fileName
    }
    catch{
      Write-Verbose "Error writting file to output path"
      Write-Verbose "Error msg: $_"
    }
    
  }
}