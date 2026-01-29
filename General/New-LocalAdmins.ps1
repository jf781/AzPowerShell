# Get the hostname of the computer
$hostname = $env:COMPUTERNAME

# Define account names based on the hostname
$accountName1 = "$hostname`_admin1"
$accountName2 = "$hostname`_admin2"
$accountName3 = "app_specific_admin"

$accountDescription1 = "Admin account 1 for $hostname"
$accountDescription2 = "Admin account 2 for $hostname"
$accountDescription3 = "Application-specific admin account for $hostname"

# Define the default password for the accounts (change this to a secure password)
$adminPassword = ConvertTo-SecureString "value" -AsPlainText -Force
$appSpecificPassword = ConvertTo-SecureString "value" -AsPlainText -Force


# User creation function
function New-LocalAdmin {
    param (
        [string]$userName,
        [System.Security.SecureString]$password,
        [string]$description
    )
    # Check if the user already exists
    if (-not (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
        # Create the new local user
        New-LocalUser -Name $userName -Password $password -Description $description
        Write-Host "User $userName created."
    } else {
        Write-Host "User $userName already exists."
    }
}

# Group addition function
function Add-ToGroup {
    param (
        [string]$userName,
        [string]$groupName
    )
    # Check if the user is already a member of the group
    if (-not (Get-LocalGroupMember -Group $groupName -Member $userName -ErrorAction SilentlyContinue)) {
        # Add the user to the group
        Add-LocalGroupMember -Group $groupName -Member $userName
        Write-Host "User $userName added to $groupName."
    } else {
        Write-Host "User $userName is already a member of $groupName."
    }
}

# Create the users
New-LocalAdmin -userName $accountName1 -password $adminPassword -description $accountDescription1
New-LocalAdmin -userName $accountName2 -password $adminPassword -description $accountDescription2
New-LocalAdmin -userName $accountName3 -password $appSpecificPassword -description $accountDescription3

# Groups to add the users to
$groups = @("Administrators", "Remote Desktop Users")

# Add users to the specified groups
foreach ($group in $groups) {
    Add-ToGroup -userName $accountName1 -groupName $group
    Add-ToGroup -userName $accountName2 -groupName $group
    Add-ToGroup -userName $accountName3 -groupName $group
}
