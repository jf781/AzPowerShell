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
    $resourceTypeList,
    [Parameter(
      Mandatory = $true)]
    [bool]
    $reportDependencies
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

    function Start-MigrationRequest {
      [CmdletBinding()]
      param(    
        [Parameter(
          Mandatory = $true)]
        [object]
        $resources,
        [Parameter(
          Mandatory = $true)]
        [string]
        $targetresourceGroup,
        [Parameter(
          Mandatory = $true)]
        [string]
        $targetSubscriptionID,
        [Parameter(
          Mandatory = $true)]
        [string]
        $sourceSubscriptionID,
        [Parameter(
          Mandatory = $true)]
        [string]
        $subscriptionName,
        [Parameter(
          Mandatory = $true)]
        [bool]
        $reportDependencies
      )
      process{
        foreach ($resource in $resources) {
          Write-Verbose "In Foreach loop with resource: $($resource.Name) "
          Write-Verbose "Clearing variables."
          $result = @()
          $resourceIds = @()
          $body = $null
          $request = $null
          $requestStatus = $null 

        
          Write-Host "Checking resource type: $($resource.ResourceType) with resource name: $($resource.Name)"

          $resourceIds += $resource.resourceId
          $resourceGroupName = $resource.resourceGroupName
          Write-Verbose "`$resourceIds = $resourceIds"
          $body = @{
            resources           = $resourceIds;
            targetResourceGroup = "/subscriptions/$targetSubscriptionID/resourceGroups/$targetresourceGroup"
          }
          Write-Verbose "Set the body variable to check if the resource can be moved:  `$body:"
          Write-Verbose $body.Values
        

          $request = New-MigrationRequest -sourceSubscriptionID $sourceSubscriptionID `
            -resourceGroupName $resourceGroupName `
            -body $body
          Write-Verbose "`$return: $return"
          
          $requestStatus = Get-MigrationRequestStatus -request $request `
            -resource $resource `
            -subscriptionName $subscriptionName `
            -reportDependencies $reportDependencies
          Write-Verbose "`$requestStatus: $requestStatus"


          Write-Verbose "`$result = $result"
          Write-Verbose "`$dependencies = $dependencies"
          $results += $requestStatus.results
          if ($requestStatus.dependencies -ne $null) {
            Write-Verbose "In If, `$dependencies is not null.  `Adding to $dependencyReport"
            $dependencyReport += $requestStatus.dependencies
          }
          else {
            Write-Verbose "In Else, `$dependencies is null."
          }
        
        }

      }

    }

    function New-MigrationRequest  {
      [CmdletBinding()]
      param(    
        [Parameter(
          Mandatory = $true)]
        [object]
        $body,
        [Parameter(
          Mandatory = $true)]
        [string]
        $sourceSubscriptionID,
        [Parameter(
          Mandatory = $true)]
        [string]
        $resourceGroupName

      )
      process {
        $token = Get-AzBearerToken
        [hashtable]$return = @{}

        Try {
          Write-Verbose "Invoking request to determine if resource be moved"
          $request = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$sourceSubscriptionID/resourceGroups/$resourceGroupName/validateMoveResources?api-version=2020-06-01" -method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers @{Authorization = $token }
          $returnStatusCode = $request.StatusCode
        }
        Catch {
          Write-Verbose "Error occurred invoking request"
          Write-Verbose "Error message: $_"
          $returnError = $_
          $returnErrorJson = $returnError -replace "Invoke-WebRequest: ", "" | ConvertFrom-Json
          $returnStatusCode = "400"
        }
        Write-Verbose "`$returnStatusCode = $returnStatusCode"
        
        $return.rawContent  = if($request){$request.rawContent}else{$null}
        $return.statusCode  = $returnStatusCode
        $return.error       = if($returnError){$returnStatusCode}else{$null}
        $return.jsonError   = if($returnErrorJson){$returnStatusCode}else{$null}

        return $return
      }
    }

    function Get-MigrationRequestStatus {
      [CmdletBinding()]
      param(    
        [Parameter(
          Mandatory = $true)]
        [object]
        $request,
        [Parameter(
          Mandatory = $true)]
        [object[]]
        $resource,
        [Parameter(
          Mandatory = $true)]
        [string]
        $subscriptionName,
        [Parameter(
          Mandatory = $true)]
        [bool]
        $reportDependencies
      )
      process{
        [hashtable]$return = @{}
        $dependencyCount  = $null
        $dependencies     = $null
        $result           = $null
        $errorMessage     = $null
        $dependencyCount  = $null
        $resultsError     = $null
        $resultsErrorJson = $null

        $token = Get-AzBearerToken

        if($resource.resourceType){
          Write-Verbose "`$resource is not a resource group"
          $resourceName       = $resource.name
          $resourceGroupName  = $resource.resourceGroupName
          $ResourceType       = $resource.ResourceType
          $ResourceId         = $resource.ResourceId
          Write-Verbose  "`$resourceName: $resourceName"
          Write-Verbose  "`$resourceGroupName: $resourceGroupName"
          Write-Verbose  "`$ResourceType: $ResourceType"
          Write-Verbose  "`$ResourceId: $ResourceId"
        }else{
          Write-Verbose "`$resource: $resource is a resource group"
          $resourceName       = $null
          $resourceGroupName  = $resource.resouceGroupName
          $ResourceType       = "Resource Group"
          $ResourceId         = $resource.ResourceId
          Write-Verbose  "`$resourceName: $resourceName"
          Write-Verbose  "`$resourceGroupName: $resourceGroupName"
          Write-Verbose  "`$ResourceType: $ResourceType"
          Write-Verbose  "`$ResourceId: $ResourceId"
        }

        if ($request.statusCode -eq "202") {
          Write-Verbose "Request to move resource successfully submitted."
          # [int]$retryTime = ($return.RawContent -split "Retry-After: ")[1].Substring(0, 2)
          [int]$retryTime = "5"
    
          do {
            Write-Verbose "In Do loop to get move request response. Will continue until StatusCode is not 202"
            $rawUrl = ($request.RawContent -split "Location: ")[-1]
            $validationUrl = $rawUrl.split("`n")[0]
            Write-Verbose "URL to validate get status code is $validationUrl"

            Try {
              Write-Verbose "Invoking request to get move request status "
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

            Write-Host "Waiting for status..."
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

                  if ($reportDependencies) {
                    Write-Verbose "`$reportDependencies set to $reportDependencies"
                    foreach ($dependency in $resultsErrorJson.error.details.details.message) {
                      Write-Verbose "Reporting dependencies for $resource.Name"
                      $props = [ordered]@{
                        resourceName = $resourceName
                        dependency   = $dependency
                      }
                      $dependencies = New-Object -TypeName psobject -Property $props 
                    }
                  }
                  else {
                    Write-Verbose "`$reportDependencies set to $reportDependencies"
                  }
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
              ResourceName    = $resourceName
              ResourceGroup   = $resourceGroupName
              Subscription    = $subscriptionName
              ResourceType    = $resourceType
              ResourceId      = $resourceId
              Notes           = $errorMessage
              DependencyCount = $dependencyCount
            }
            $result = New-Object -TypeName psobject -Property $props
          }
          elseif ($statusCode -eq 204) {
            Write-Verbose "In ElseIf for `$statusCode = 204. `$statusCode = $statusCode"
            Write-Verbose "Resource type $($resourceType) with resource name $($resourceName) can be moved to new subscrtipion" 
            $props = [ordered]@{
              AbleToMigrate   = "true"
              ResourceName    = $resourceName
              ResourceGroup   = $resourceGroupName
              Subscription    = $subscriptionName
              ResourceType    = $resourceType
              ResourceId      = $resourceId
              Notes           = $errorMessage
              DependencyCount = $dependencyCount
            }
            $result = New-Object -TypeName psobject -Property $props
          }
          else {
            Write-Verbose "In Else for `$statusCode. `$statusCode = $statusCode"
            Write-Verbose "Another problem occured for resource type $($resourceType) with resource name $($resourceName). Error: $Exc"
            $props = [ordered]@{
              AbleToMigrate   = "Error Occurred"
              ResourceName    = $resourceName
              ResourceGroup   = $resourceGroupName
              Subscription    = $subscriptionName
              ResourceType    = $resourceType
              ResourceId      = $resourceId
              Notes           = $errorMessage
              DependencyCount = $dependencyCount
            }
            $result = New-Object -TypeName psobject -Property $props
          }


        }
        else {
          Write-Verbose "Failed to determine if the resource: $resourceId can be migrated"
          Write-Verbose "Failed to determine if the resource: $resourceId can be migrated" 
          Write-Verbose "Error Msg: $returnError" 

          $props = [ordered]@{
            AbleToMigrate   = "Error Occurred"
            ResourceName    = $resourceName
            ResourceGroup   = $resourceGroupName
            Subscription    = $subscriptionName
            ResourceType    = $resourceType
            ResourceId      = $resourceId
            Notes           = $returnErrorJson.message
            DependencyCount = $dependencyCount
          }
          $result = New-Object -TypeName psobject -Property $props
        }

        $return.results       = $result
        $return.dependencies  = if($dependencies){$dependencies}else{$null}

        return $return
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
    $resources = @()
    $dependencyReport = @()
    
    # Getting list of resources Types
    if(Test-Path -Path $resourceTypeList){
      Write-Verbose "Validated $resourceTypeList is a valid path"
      $resourceTypes = Get-Content -Path $resourceTypeList
    }else{
      Write-Verbose "$resourceTypeList is not a valid path.  Exiting"
      Write-Host "$resourceTypeList is not a valid path" -ForegroundColor Red
      Write-Host "Please run run script with a valid path provided for the 'ResourceTypeList' parameter" -ForegroundColor Red
      Write-Host "Exiting.  No resources have been validated" -ForegroundColor Red
      break
    }


    $outputPath = Confirm-OutputPath -path $outputPath

    if($outputPath){
      Write-Verbose "Getting list of resources that match the resource types in the `$resourceTypeList"

      $resourceGroups = Get-AzResourceGroup
      foreach($resourceGroup in $resourceGroups){
        try {
          foreach ($resourceType in $resourceTypes) {
            $rtResources = Get-azresource -ResourceType $resourceType -ResourceGroupName $resourceGroup.ResourceGroupName
            $resources = $resources += $rtResources
          }


        }
        catch {
          Write-Verbose "Error getting list of resources"
          Write-Verbose "Error msg: $_"
        }
      }



    }else {
      Write-Verbose "Output path invalid.  Exiting"
      break
    }

    Write-Verbose "Exited Foreach statement for resource group"

    try{
      Write-Verbose "Attempting to write date to `$outputPath: $outputPath"
      $subscriptionName = ((Get-AzContext).Subscription.Name -replace ' ', '-' `
                                                            -replace '\\', '-' `
                                                            -replace '/', '-' ).ToLower()
      $ScanName = $outputPath + "MigrationPlanningScan_" + $subscriptionName + "_" + $date + ".csv"
      $dependencyReportName = $outputPath + "DependencyReports_" + $subscriptionName + "_" + $date + ".csv"
      $results | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $ScanName
      If($dependencyReport -ne $null){
        Write-Verbose "In If, `$dependencyReport is not null.  Writing contents to file"
        $dependencyReport | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $dependencyReportName
      }else{
        write-verbose "In else, $dependencyReport is null."
      }
    }
    catch{
      Write-Verbose "Error writting file to output path"
      Write-Verbose "Error msg: $_"
    }
    
  }
}
