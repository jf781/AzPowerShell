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