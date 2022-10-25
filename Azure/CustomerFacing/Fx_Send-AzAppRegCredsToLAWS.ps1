using namespace System.Net

# # Input bindings are passed in via param block.
# param($Request, $TriggerMetadata)

# Input bindings are passed in via param block.
param($Timer)

# # Get the current universal time in the default string format
# $currentUTCtime = (Get-Date).ToUniversalTime()

# # The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
# if ($Timer.IsPastDue) {
#     Write-Host "PowerShell timer is running late!"
# }

# # Write an information log with the current time.
# Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

# Create two records with the same set of properties to create
Function Get-AppRegistrationWithCredentials {
    $apps = Get-AzADApplication
    if($null -eq $apps){
        Write-Host "No App Registrations found"
    } else {
        foreach($app in $apps) {
            # Write-Host "`$app is $app"
            $creds = Get-AzADAppCredential -ApplicationId $app.AppId -ErrorAction SilentlyContinue
            
            if($creds){
                $newestCred = $creds | Sort-Object EndDateTime | Select-Object -Last 1
                # Write-host "`$newestCred is $newestCred"
                if($newestCred.endDateTime -lt (Get-Date)){
                    $credExpired = $true
                }else {
                    $credExpired = $false
                }

                if ($newestCred.type -eq "AsymmetricX509Cert") {
                    $credType = "Certificate"
                } else { 
                    $credType = "Secret"
                }
        
                $props = [ordered]@{
                    ServicePrincipalName            = $app.displayName 
                    SerivcePrinipalObjectId         = $app.id
                    ServicePrincipalAppId           = $app.appId
                    NewestCredKeyId                 = $newestCred.keyId
                    NewestCredDisplayName           = $newestCred.displayName
                    NewestCredType                  = $credType
                    NewestCredExpirationDate        = $newestCred.endDateTime
                    NewestCredExpired               = $credExpired
                }
                    
                New-Object -TypeName psobject -Property $props
            }
        }
    }
}
  
  # Create the function to create the authorization signature
  Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource) {
      $xHeaders = "x-ms-date:" + $date
      $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
  
      $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
      $keyBytes = [Convert]::FromBase64String($sharedKey)
  
      $sha256 = New-Object System.Security.Cryptography.HMACSHA256
      $sha256.Key = $keyBytes
      $calculatedHash = $sha256.ComputeHash($bytesToHash)
      $encodedHash = [Convert]::ToBase64String($calculatedHash)
      $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
      return $authorization
  }
  
  # Create the function to create and post the request
  Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType) {
      $method = "POST"
      $contentType = "application/json"
      $resource = "/api/logs"
      $rfc1123date = [DateTime]::UtcNow.ToString("r")
      $contentLength = $body.Length
      $signature = Build-Signature `
          -customerId $customerId `
          -sharedKey $sharedKey `
          -date $rfc1123date `
          -contentLength $contentLength `
          -method $method `
          -contentType $contentType `
          -resource $resource
      $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
  
      $headers = @{
          "Authorization" = $signature;
          "Log-Type" = $logType;
          "x-ms-date" = $rfc1123date;
          "time-generated-field" = $TimeStampField;
      }
  
      $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
      return $response.StatusCode
  
  }
  
  # Get secrets from Vault for Log Analytics Workspace ID and Shared Key
  Function Get-VaultSecret ($secretName, $vaultName) {
    $value = Get-AzKeyVaultSecret `
      -VaultName $vaultName `
      -Name $secretName `
      -AsPlainText
  
    return $value
  }
  
  $workspaceId = Get-VaultSecret -secretName "workspaceId" -vaultName "dfin-demo-vault-001"
  $workspaceKey = Get-VaultSecret -secretName "workspaceSharedKey" -vaultName "dfin-demo-vault-001"
  
  $logType = "AppRegistrationsCreds"
  $timeStampField = ""
  
  try {
    $body = Get-AppRegistrationWithCredentials | ConvertTo-Json
  } catch {
    Write-Error "$($_.Exception)"
    throw "$($_.Exception)" 
  }
  
  # Submit the data to the API endpoint
  try {
    $results = Post-LogAnalyticsData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($body)) -logType $logType
  } catch {
    Write-Error "$($_.Exception)"
    throw "$($_.Exception)" 
  }

  if($results -eq "200") {
    Write-Host "Successfully updated Log Analytics workspace with App Registrations"
  } else {
    Write-Host "Error writing to Log Analytics worksapce. Results = $results"
  }