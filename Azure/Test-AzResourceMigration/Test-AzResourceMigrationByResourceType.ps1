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
    $resources = @()
    
    # Getting list of resources Types
    if(Test-Path -Path $resourceTypeList){
      Write-Verbose "Validated $resourceTypeList is a valid path"
      $resourceTypes = Get-Content -Path $resourceTypeList
    }else{
      Write-Verbose "$resourceTypeList is not a valid path.  Exiting"
      Write-Host "$resourceTypeList is not a valid path" -ForegroundColor Red
      Write-Host "Please run run script with a valid path provided for the 'ResourceTypeList' parameter" -ForegroundColor Red
      Write-Host "Exiting.  No resources have been validated" -ForegroundColor Red
      Exit
    }


    $outputPath = Confirm-OutputPath -path $outputPath

    if($outputPath){
      Write-Verbose "Getting list of resources that match the resource types in the `$resourceTypeList"
      try{
        foreach ($resourceType in $resourceTypes){
          $rtResources = Get-azresource -ResourceType $resourceType
          $resources = $resources += $rtResources
        }
      }
      catch{
        Write-Verbose "Error getting list of resources"
        Write-Verbose "Error msg: $_"
      }
      
      foreach ($resource in $resources) {
        $result = @()
        $body = $null
        $token = $null
        $return = $null
        $curlResponse = $null
        $errorMesssage = $null

        $token = Get-AzBearerToken
        Write-Verbose "In Foreach loop with resource: $($resource.Name) "
        Write-Host "Checking resource type: $($resource.ResourceType) with resource name: $($resource.Name)"

    
        $resourceID = @()
        $resourceID += $resource.resourceId
        $resourceGroupName = $resource.resourceGroupName
        Write-Verbose "`$resourceId = $resourceID"
        $body = @{
          resources           = $resourceID;
          targetResourceGroup = "/subscriptions/$targetSubscriptionID/resourceGroups/$targetresourceGroup"
        }
        Write-Verbose "Set the body variable to check if the resource can be moved:  `$body:"
        Write-Verbose $body.Values
        
        #add try catch
        Try {
          Write-Verbose "Invoking request to determine if resource be moved"
            $return = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$sourceSubscriptionID/resourceGroups/$resourceGroupName/validateMoveResources?api-version=2020-06-01" -method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers @{Authorization = $token }
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
              $Exc = $_.Exception
            }

            Write-Host Waiting for status...
            Start-Sleep -Seconds $retryTime
          }
          while ($statusCode -eq 202)
    
          if ($statusCode -eq 205) {
            Write-Verbose "In If for `$statusCode = 205. `$statusCode = $statusCode"
            Write-Verbose "Resource type $($resource.ResourceType) with resource name $($resource.Name)can not be moved. Error: $Exc"
            $curlResponse = curl --silent --request GET $validationUrl --header "Authorization: $token" --header "Content-Type: application/json" 
            Write-Verbose "`$curlResponse = $curlResponse"
            $errorMesssage = $curlResponse -replace "\\", "" `
              -replace '"{', '{' `
              -replace '}"', '}' | jq .error.details[].message | ConvertFrom-Json 
            if ($errorMesssage -eq $null) {
              Write-Verbose "In If,  Getting just the Error.Message"
              $errorMesssage = $curlResponse -replace "\\", "" `
              -replace '"{', '{' `
              -replace '}"', '}' | jq .error.message | ConvertFrom-Json 
            }elseIf($errorMessage.message){
              write-verbose "In ElseIf of `$errorMesssage.message.  $errorMessage is is still an object"
              $errorMesssage = $errorMesssage.message.Message
            }
            else {
              write-verbose "In Else of `$errorMesssage.message.  $errorMessage is valid string"
            }
            $props = [ordered]@{
              AbleToMigrate = "false"
              ResourceName  = $resource.Name
              ResourceGroup = $resource.ResourceGroupName
              Subscription  = $subscriptionName
              ResourceType  = $resource.ResourceType
              ResourceId    = $resource.ResourceId
              Notes         = $errorMesssage
            }
            $result = New-Object -TypeName psobject -Property $props
          }
          elseif ($statusCode -eq 204) {
            Write-Verbose "In ElseIf for `$statusCode = 204. `$statusCode = $statusCode"
            Write-Verbose "Resource type $($resource.ResourceType) with resource name $($resource.Name) can be moved to new subscrtipion" 
            $props = [ordered]@{
              AbleToMigrate = "true"
              ResourceName  = $resource.Name
              ResourceGroup = $resource.ResourceGroupName
              Subscription  = $subscriptionName
              ResourceType  = $resource.ResourceType
              ResourceId    = $resource.ResourceId
              Notes         = $errorMesssage
            }
            $result = New-Object -TypeName psobject -Property $props
          }
          else {
            Write-Verbose "In Else for `$statusCode. `$statusCode = $statusCode"
            Write-Verbose "Another problem occured for resource type $($resource.ResourceType) with resource name $($resource.Name). Error: $Exc"
            $props = [ordered]@{
              AbleToMigrate = "Error Occurred"
              ResourceName  = $resource.Name
              ResourceGroup = $resource.ResourceGroupName
              Subscription  = $subscriptionName
              ResourceType  = $resource.ResourceType
              ResourceId    = $resource.ResourceId
              Notes         = $errorMesssage
            }
            $result = New-Object -TypeName psobject -Property $props
          }


        }
        else {
          Write-Verbose "Failed to determine if the resource: $resourceId can be migrated"
          Write-Verbose "Failed to determine if the resource: $resourceId can be migrated" 
          Write-Verbose "Error Msg: $_" 

          $props = [ordered]@{
            AbleToMigrate = "Error Occurred"
            ResourceName  = $resource.Name
            ResourceGroup = $resource.ResourceGroupName
            Subscription  = $subscriptionName
            ResourceType  = $resource.ResourceType
            ResourceId    = $resource.ResourceId
            Notes         = $errorMesssage
          }
          $result = New-Object -TypeName psobject -Property $props
        }
        $results = $results += $result
      }

    }else {
      Write-Verbose "Output path invalid.  Exiting"
      break
    }

    Write-Verbose "Exited Foreach statement for resource group"

    try{
      Write-Verbose "Attempting to write date to `$outputPath: $outputPath"
      $fileName = $outputPath + "MigrationPlanningScan-" + $date + ".csv"
      $results | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $fileName
    }
    catch{
      Write-Verbose "Error writting file to output path"
      Write-Verbose "Error msg: $_"
    }
    
  }
}
