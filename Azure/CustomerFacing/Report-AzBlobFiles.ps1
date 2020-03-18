<# 

To Do List
1. Determine how to lookup costs for the indivudal blobss

#>

######################################################
#----------------Define Parameters-------------------#
######################################################

Param(
    [Parameter(
        Mandatory = $false,
        HelpMessage = "If a Storage Account is not specified it will run against all Storage Accounts"
    )]
    [string]$storageAccountName,
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Resource Group of the Storage Account"
    )]
    [string]$resourceGroupName,
    [Parameter(
        Mandatory = $true,
        HelpMessage = "KeyVault that contains API and Client Secret"
    )]
    [string]$keyVaultName,
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Name of Secret for the Client in AAD"
    )]
    [string]$clientSecretName,
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Name of Secret for the API for SendGrid"
    )]
    [string]$APISecretName,
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Name of file Extension to search for"
    )]
    [string]$fileExtension,
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Minimum Age of the files to report on"
    )]
    [string]$minimumAge,
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Age at which files become eligable for deletion"
    )]
    [string]$maximumAge,
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Define the recipient of the message"
    )]
    [String]$recipient
)

######################################################
#----------------Define Variables--------------------#
######################################################

# Define Caluclated Variables
$minimumDate = (Get-Date).addMinutes(-$minimumAge)
$maximumDate = (Get-Date).addDays(-$maximumAge)

######################################################
#----------------Define Modules---------------------#
######################################################


# This will get the Blobs from the one or more storaage accounts
# If a storage account is not specified then it will run against all storage accounts in the subscription
function Get-AzBlobs {
    [CmdletBinding()]
    param (
        [Parameter(
            mandatory=$false,
             HelpMessage = "Pleases specific a storage account to run against (If none defined it will run against all in the subscription)."
        )]
        [string]$storageAccountName,
        [Parameter(
            mandatory=$false,
             HelpMessage = "Please specify the resource group of the Storage Account in the 'StorageAccountName' parameter."
        )]
        [string]$resourceGroupName,
        [Parameter(
            mandatory = $true,
            HelpMessage = "File extension of blobs to return."
        )]
        [string]$fileExt

    )

    process {
        try{
            if(!$storageAccountName){
                $storageAccounts = Get-AzStorageAccount
            }Else{
                $storageAccounts = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName
            }
        }
        catch{
            Write-Host "Error getting details about the storage accounts" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
        }
        try{
            foreach ($storageAccount in $storageAccounts) {
                $stgAcct = Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction SilentlyContinue
                if ($stgAcct -ne $null) {
                    if ($stgAcct[0].value) {
                        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction SilentlyContinue)[0].Value
                        $context = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey
                        $containers = Get-AzStorageContainer -Context $context -ErrorAction silentlycontinue
                        foreach ($container in $containers) {
                            $blobs = Get-AzStorageBlob -Container $container.Name -Context $context | Where-Object { $_.ICloudBlob.Properties.Created -lt $minimumDate -and $_.Name.EndsWith($fileExt) }
                            foreach ($blob in $blobs) {
                                $blobName = $blob.ICloudBlob.Name
                                $blobRgName = $storageAccount.ResourceGroupName
                                $blobLocation = $storageAccount.Location
                                $blobUri = $blob.IcloudBlob.Uri.AbsoluteUri
                                $blobTier = $blob.ICloudBlob.Properties.StandardBlobTier
                                $blobCreatedOn = $blob.ICloudBlob.Properties.Created
                                $blobLastModified = $blob.ICloudBlob.Properties.LastModified
                                $blobSize = [MATH]::floor([decimal]($blob.ICloudBlob.Properties.Length) / 1073741824)

                                $unmngDiskProps = [ordered]@{
                                    Name           = $blobName
                                    SizeInGB       = $blobSize
                                    Resource_Group = $blobRgName
                                    Location       = $blobLocation
                                    URI            = $blobUri
                                    Tier           = $blobTier
                                    Created        = $blobCreatedOn
                                    Last_Modified  = $blobLastModified
                                    StorageAccount = $storageAccount.StorageAccountName
                                }

                                New-Object -TypeName psobject -Property $unmngDiskProps
                            }
                        }
                    }
                }
                Else {
                    #Unable to access Storage Key
                }
            }
        }
        Catch{
            Write-Host "Error getting blob details from Storage Account $storageAccount" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
        }
    }
}

# This module will get the bearer token.  This is used to authenticate against Azure when pulling pricing data
function Get-AzBearerToken {
    [CmdletBinding()]
    param()
    process {
        try{
            $clientSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $clientSecretName | Select-Object -expand SecretValueText
            
            $token = Invoke-WebRequest -URI 'https://login.microsoftonline.com/3af1cd00-90be-4d09-bc8c-4fda26a55eac/oauth2/token' `
                -Method 'POST' `
                -Headers @{
                'Content-Type' = 'application/x-www-form-urlencoded'
            } `
                -Body @{
                'grant_type'    = 'client_credentials'
                'client_id'     = 'af8e86c6-75d7-45f2-b2e4-06b2aba207bc'
                'client_secret' = '$clientSecret'
                'resource'      = 'https://management.azure.com/'     
            }

            $accessToken = (($token.Content.Split(",") | Select-Object -Last 1).Split(":") | Select-Object -Last 1).Split("}") | Select-Object -First 1

            $props = 'Bearer ' + $accessToken -replace '"'
        
            return $props
        }catch{
            Write-Host "Error getting Bearer Token" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
        }
    }
}

# This module leverages the Bearer Token from module 'Get-AzBearerToken' for authentication
# It pulls the rate card for the United States Azure subscription.  
function Get-AzRateCard {
    [CmdletBinding()]
    param(
        [Parameter(
            mandatory=$true,
             HelpMessage = "Please specifiy the bearer token used for authentication.  Run the 'Get-AzBearerToken' module to get a bearer token"
        )]
        [string]$bearerToken
    )
    process {
        try{
            $props = Invoke-RestMethod -URI 'https://management.azure.com/subscriptions/ce6ec219-6d67-4ef2-a9e0-c89fe111c4e4/providers/Microsoft.Commerce/RateCard?api-version=2016-08-31-preview&$filter=OfferDurableId+eq+%27MS-AZR-0003p%27+and+Locale+eq+%27en-US%27+and+Regioninfo+eq+%27US%27+and+Currency+eq+%27USD%27' `
                -Method 'GET' `
                -Header @{'Authorization' = $bearerToken }
            
            return $props
        }
        catch{
            Write-Host "Error getting Blobs from Storage Account $storageAccount" -ForegroundColor Red
            Write-Host "Error msg $_" -ForegroundColor Red
        }
    }
}


# This module uses information provided by the rate card to determine estimated cost of various resources.
# It is not generalized and it specific to Azure Blob costs at this point.  
function Get-AzResourceCost {
    [CmdletBinding()]
    param(
        [Parameter(
            mandatory = $true,
            HelpMessage = "Provide a Blob Object to pull the approximate cost information for."
        )]
        [object[]]$blob
    )
    process {
        try{
            $stgAcct = Get-AzStorageAccount -Name $blob.storageAccount -ResourceGroupName $blob.Resource_Group
            $BlobRepl = ($stgAcct.Sku.Name).Split("_") | Select-Object -Last 1
            $BlobTier = $blob.Tier
            $rawLocation = $stgAcct.Location
            switch ($rawLocation) {
                northcentralus { $location = "US North Central" }
                centralus { $location = "US Central" }
                eastus { $location = "US East" }
                eastus2 { $location = "US East 2" }
                westus { $location = "US West" }
                westus2 { $location = "US West 2" }
            }
        }
        catch{
            Write-Host "Error getting details about the Blob - $Blob" -ForegroundColor Red
            Write-Host "Error msg $_" -ForegroundColor Red
        }

        $MeterName = $BlobTier.ToString() + " " + $BlobRepl + " Data Stored"

        $props = $RateCard.Meters | Where-Object {
            ($_.MeterSubCategory -eq "Tiered Block Blob") -and 
            ($_.MeterName -eq $Metername) -and 
            ($_.MeterRegion -eq $Location)
        }

        return $props
    }
}

#  Filler module to get the cost of the Azure Blobs.  Will leverage the 'Get-AzResourceCost' module 
function Get-AzBlobCost {
    [CmdletBinding()]
    param(
        [Parameter(
            mandatory=$true
        )]
        [object[]]$CostData,
        [Parameter(
            mandatory=$true
        )]
        [object[]]$Blob
    )
    process{
        
    }
}

# This module will leverage the SendGril email service. 
# It requires 
function Send-SendGridEmail {
    [CmdletBinding()]
    param(
        [Parameter(
            mandatory=$true,
            HelpMessage = "This is the API key provided by SendGrid"
        )]
        [string]$API,
        [Parameter(
            mandatory = $true,
            HelpMessage = "This is the list of recipients that will be receiving the email."
        )]
        [string]$Recipients,
        [Parameter(
            mandatory = $true,
            HelpMessage = "Please provide the Blob Objects to pass along"
        )]
        [object[]]$Blobs,
        [Parameter(
            mandatory = $true,
            HelpMessage = "If the blob objects are enough to be eligable for deletion then please set this flag to true.  Otherwise set to false"
        )]
        [boolean]$ElegiableForDeletion
    )
    process {

        # Authentication for SendGrid API
        $bearerToken = "Bearer " +$API

        # Details for Message
        $date = (Get-Date).ToShortDateString() -replace "/", "-"
        If($ElegiableForDeletion){
            $subject = "Azure Archive Storage files eligable for deletion - $date"
            $body = "The following files are were added to the Archive over 36 months ago.
                    $Blobs"
        }
        Else{
            $subject = "Azure Archive Storage Report - $date"
            $body = "The following files were added within the last 36 months to Azure Storage Report
                    $Blobs"
        }
        $senderAddress = "llubinski@alixpartners.com"
        $senderName = "Lawrence Lubinski"

        $messageBody = '{
            "personalizations":[
                {
                    "to":[
                        {
                            "email": $Recipients,
                        }
                    ],
                    "subject":"$Subject",
                }
            ],
            "content":[
                {
                    "type": "text/plain",
                    "value": "$Body"
                }
            ],
            "from":{
                "email":"$senderAddress",
                "name":"$senderName"
            },
            "reply_to":{
                "email":"$senderAddress",
                "name":"$senderName"
            }
        }'
        try{
            Invoke-WebRequest -URI https://api.sendgrid.com/v3/mail/send `
                -Method 'POST' `
                -Headers @{
                    'authorization'= $bearerToken
                    'content-type'='application/json'
                } `
                -Body $messageBody
         }
        catch{
            Write-Host "Error sending email via Sendgrid." -ForegroundColor Red
            Write-Host "Error msg $_" -ForegroundColor Red
        }
    }
}

######################################################
#------------------Main Function --------------------#
######################################################

# Login to Azure 

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave –Scope Process

$connection = Get-AutomationConnection -Name AzureRunAsConnection

# Wrap authentication in retry logic for transient network failures
$logonAttempt = 0
while (!($connectionResult) -And ($logonAttempt -le 10)) {
    $LogonAttempt++
    # Logging in to Azure...
    $connectionResult = Connect-AzAccount `
        -ServicePrincipal `
        -Tenant $connection.TenantID `
        -ApplicationId $connection.ApplicationID `
        -CertificateThumbprint $connection.CertificateThumbprint

    Start-Sleep -Seconds 30
}

$AzureContext = Get-AzSubscription -SubscriptionId $connection.SubscriptionID

# Getting the Azure Blobs.  If a Storage Account Name is specified then it will only check that storage account.  
# If none are specified it will check all storage accounts in the current context
# It will only return blobs that meet the are older the then $MinimumDate that have a file extension defined. 

$blobs = Get-AzBlobs -storageAccountName $storageAccountName -resourceGroupName $resourceGroupName -fileExt $fileExtension

# Checking each blob to see if it eligable for deletion

Foreach ($blob in $blobs) {
    if ($blob.Created -gt $maximumDate) {        
        # Blobs are older then defined age so eligable to be deleted 
        $blobsEligableForDeletion = [Array]$blobsEligableForDeletion + $blob
    }
    ElseIf ($blob.created -lt $minimumDate) {
        # Blobs are not old enough to be deleted
        $blobsToReport = [Array]$blobsToReport + $blob
    }
    Else{
        # Blob less then Minimum age to report on
    }
}

$SendGridAPI = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $apiSecretName | Select-Object -ExpandProperty SecretValueText

# Sending email reports on blobs.  Seperate emails are sent depending on if they 
If ($blobsEligableForDeletion){
    Send-SendGridEmail -Recipients $recipient -api $SendGridAPI -blobs $blobsEligableForDeletion -ElegiableForDeletion $true
}

If ($blobsToReport){
    Send-SendGridEmail -Recipients $recipient -api $SendGridAPI -blobs $blobsToReport -ElegiableForDeletion $false
}

write-output $blobsEligableForDeletion
write-output $blobsToReport