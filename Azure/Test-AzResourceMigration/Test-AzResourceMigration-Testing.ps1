
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

$targetResourceGroup = "AMA-CE-Test-Int-VNets-RG"

$sourceResourceGroup = "AMA-CE-Prod-Int-ADC-RG"

$sourceSubscriptionID = "70a4d0a4-2e34-4bdc-8f66-d757ae1a053b"

$targetSubscriptionID = "a96d073d-2c1d-49f4-8975-2788b9945a45"

$currentContext = (Get-AzContext | Select-Object Subscription).Subscription.Id

if (!$currentContext) {
  Write-Verbose "Current session does not have an Azure context"
  Login-AzAccount -SubscriptionId $sourceSubscriptionID
}
if ($currentContext -ne $sourceSubscriptionID) {
  Write-Verbose "Updating current session context to match the value of the `$sourceSubscriptionId variable"
  Select-AzSubscription -SubscriptionId $sourceSubscriptionID
}

$result = @()
$body = $null
$token = $null
$return = $null

$token = Get-AzBearerToken
# $resource  = Get-AzResource -ResourceGroupName $sourceresourceGroup | select-object -first 1

$resourceIDs = @()
# $resourceID += $resource.resourceId
$resourceIds += "/subscriptions/70a4d0a4-2e34-4bdc-8f66-d757ae1a053b/resourceGroups/AMA-CE-Prod-Int-ADC-RG/providers/Microsoft.Network/networkInterfaces/CH01WADC01-net"
$body = @{
  resources           = $resourceIds ;
  targetResourceGroup = "/subscriptions/$targetSubscriptionID/resourceGroups/$targetresourceGroup"  ###### Fix me Fix me Fix me Fix me Fix me Fix me Fix me
}


$return = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$sourceSubscriptionID/resourceGroups/$sourceresourceGroup/validateMoveResources?api-version=2020-06-01" -method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers @{Authorization = $token }

$rawUrl = ($return.RawContent -split "Location: ")[-1]
$validationUrl = $rawUrl.split("`n")[0]


do {
  try{
    $resourceDetails = Invoke-WebRequest -Uri $validationUrl -method Get -ContentType "application/json" -Headers @{Authorization = $token }
    $statusCode = $resourceDetails.StatusCode
  }catch{
    $resultsError = $_
    $resultsErrorJson = $resultsError -replace "Invoke-WebRequest: ", "" | ConvertFrom-Json
    $statusCode = "205"
  }
  Write-Host "Waiting for status..."
  Write-Host "$statusCode"
  Start-Sleep -Seconds 5
}while ($statusCode -eq "202")

$errorMessage = $null
$dependencyCount = $null
$dependencyReport = @()
if ($resultsErrorJson.error.details.message){
  switch -Wildcard ($resultsErrorJson.error.details.message) {
    "The move resources request does not contain all the dependent resources.*" {
      $errorMessage = $resultsErrorJson.error.details.message | Select-Object -First 1
      $dependencyCount = $resultsErrorJson.error.details.details | Measure-Object | Select-Object -ExpandProperty Count
      if($reportDependencies){
        foreach($dependency in $resultsErrorJson.error.details.details.message){
          $props = [ordered]@{
            resourceName = $resource.Name
            dependency   = $dependency
          }
          $dependencies = New-Object -TypeName psobject -Property $props 
          $dependencyReport += $dependencies
        }
        $dependencyReport | ConvertTo-Csv -notypeinformation | Out-File -path ~/Desktop/junk-folder/ama-dependencyReport.csv
      }else{
        $dependencyReport = $null
      }
    }
    "Cannot move one or more resources in the request. Please check details for information about each resource."{
      $errorMessage = $resultsErrorJson.error.details.details.message
    }
    default {
      $errorMessage = $resultsErrorJson.error.details.message | Select-Object -First 1
    }
  }
}else{
  $errorMessage = $resultsErrorJson.error.message | Select-Object -First 1
}

Write-Host "$errorMessage"
Write-Host "$dependencyCount"
Write-Host "$dependencyReport"



Try {
  Write-Verbose "Invoking request to determine if resource be moved"
  $return = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$sourceSubscriptionID/resourceGroups/$resourceGroupName/validateMoveResources?api-version=2020-06-01" -method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers @{Authorization = $token }
  $returnStatusCode = $return.StatusCode
}
Catch {
  Write-Verbose "Error occurred invoking request"
  Write-Verbose "Error message: $_"
  $returnError = $_
  $returnErrorJson = $returnError -replace "Invoke-WebRequest: ", "" | ConvertFrom-Json
  $returnStatusCode = "400"
}