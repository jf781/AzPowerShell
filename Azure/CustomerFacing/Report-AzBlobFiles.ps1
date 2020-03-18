
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
    [string]$minimumAgeInDays,
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Age at which files become eligable for deletion"
    )]
    [string]$maximumAgeInDays,
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
$minimumDate = (Get-Date).addDays(-$minimumAgeInDays)
$maximumDate = (Get-Date).addDays(-$maximumAgeInDays)

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
                                    Name            = $blobName
                                    SizeInGB        = $blobSize
                                    Resource_Group  = $blobRgName
                                    Location        = $blobLocation
                                    URI             = $blobUri
                                    Tier            = $blobTier
                                    Created         = $blobCreatedOn
                                    Last_Modified   = $blobLastModified
                                    Storage_Account = $storageAccount.StorageAccountName
                                    Container_Name  = $container.Name
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
# It uses the API parameter to authenticate with the SendGrid service. 
function Send-SendGridEmail {
    [CmdletBinding()]
    param(
        [Parameter(
            mandatory=$true,
            HelpMessage = "This is the API key provided by SendGrid"
        )]
        [string]$api,
        [Parameter(
            mandatory = $true,
            HelpMessage = "This is the list of recipients that will be receiving the email."
        )]
        [string]$recipients,
        [Parameter(
            mandatory = $true,
            HelpMessage = "Please provide the Blob Objects to pass along"
        )]
        [object[]]$blobs,
        [Parameter(
            mandatory = $true,
            HelpMessage = "If the blob objects are enough to be eligable for deletion then please set this flag to true.  Otherwise set to false"
        )]
        [boolean]$elegiableForDeletion
    )
    process {

        # Authentication for SendGrid API
        $bearerToken = "Bearer " + $API

        # Format Blob output

        $Header = @"
<style>TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
</style>
"@

        $formattedBlobs = $blobs | 
            ConvertTo-Html -Property Name,Container_Name,Storage_Account,SizeInGB,Resource_Group,Location,Tier,Created,Last_Modified -Head $Header

        # Details for Message
        $date = (Get-Date).ToShortDateString() -replace "/", "-"

    
        If($ElegiableForDeletion){
            $subject = "Azure Archive Storage files eligable for deletion - $date"
            $body = "The following files are were added to the Archive over 36 months ago: 
                    <br>
                    --
                    <br>
                    $formattedBlobs"
        }
        Else{
            $subject = "Azure Archive Storage Report - $date"
            $body = "The following files were added within the last 36 months to Azure Storage Report:
                    <br>
                    --
                    <br>
                    $formattedBlobs"
        }
        $senderAddress = "azstoragereports@alixpartners.com"
        $senderName = "Azure Archive Storage Report"

        $messageBody = [ordered]@{
                            personalizations= @(@{to = @(@{email =  "$recipients"})
                                subject = "$subject" })
                                from = @{
                                    email = "$senderAddress"
                                    name  = "$senderName"
                                }
                                content = @( @{ type = "text/html"
                                            value = "$body" }
                                )} | ConvertTo-Json -Depth 10
        try{
            Invoke-RestMethod -URI "https://api.sendgrid.com/v3/mail/send" `
                -Method POST `
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

# Logs into Azure 

# Ensures you do not inherit a AzContext in your runbook
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
    if ($blob.created -lt $maximumDate) {        
        # Blobs are older then defined age so eligable to be deleted 
        $blobsEligableForDeletion = [Array]$blobsEligableForDeletion + $blob
    }
    Elseif ($blob.created -lt $minimumDate){
        # Blobs are not old enough to be deleted
        $blobsToReport = [Array]$blobsToReport + $blob
    }
    Else{
        # Blob less then Minimum age to report on
    }
}

$sendGridAPI = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $apiSecretName | Select-Object -ExpandProperty SecretValueText

# Sending email reports on blobs.  Seperate emails are sent depending on if they 
If ($blobsEligableForDeletion){
    Send-SendGridEmail -recipients $recipient -api $sendGridAPI -blobs $blobsEligableForDeletion -elegiableForDeletion $true
}

If ($blobsToReport){
    Send-SendGridEmail -recipients $recipient -api $sendGridAPI -blobs $blobsToReport -ElegiableForDeletion $false
}

Write-Output "These blobs are have not been modified since at least $maximumDate and are eligible for deletion."
Write-Output $blobsEligableForDeletion
Write-Output "--"
Write-Output "These blobs have been created/modified before $maximumDate"
Write-Output $blobsToReport