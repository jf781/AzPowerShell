# ----------------------------------
# Add permissions
# ----------------------------------

# Replace with your managed identity object ID
$miObjectID = "b17b7306-1b86-4dcb-b2bb-a79c162d818e"

# The app ID of the API where you want to assign the permissions
$appId = "00000003-0000-0000-c000-000000000000"

# The app IDs of the Microsoft APIs are the same in all tenants:
# Microsoft Graph: 00000003-0000-0000-c000-000000000000
# SharePoint Online: 00000003-0000-0ff1-ce00-000000000000

# Replace with the API permissions required by your app
$permissionsToAdd = "Application.Read.All"

Connect-AzureAD

$app = Get-AzureADServicePrincipal -Filter "AppId eq '$appId'"

foreach ($permission in $permissionsToAdd)
{
   $role = $app.AppRoles | where Value -Like $permission | Select-Object -First 1
   New-AzureADServiceAppRoleAssignment -Id $role.Id -ObjectId $miObjectID -PrincipalId $miObjectID -ResourceId $app.ObjectId
}

# ----------------------------------
# Validate/check permissions
# ----------------------------------

# Replace with your managed identity object ID
$miObjectID = "b17b7306-1b86-4dcb-b2bb-a79c162d818e"

# The app ID of the API where you want to assign the permissions
$appId = "00000003-0000-0000-c000-000000000000"

# The app IDs of the Microsoft APIs are the same in all tenants:
# Microsoft Graph: 00000003-0000-0000-c000-000000000000
# SharePoint Online: 00000003-0000-0ff1-ce00-000000000000

Connect-AzureAD

$app = Get-AzureADServicePrincipal -Filter "AppId eq '$appId'"

$appRoles = Get-AzureADServiceAppRoleAssignment -ObjectId $app.ObjectId | where PrincipalId -eq $miObjectID

foreach ($appRole in $appRoles) {
    $role = $app.AppRoles | where Id -eq $appRole.Id | Select-Object -First 1
    write-host $role.Value
}

# ----------------------------------
# Remove permissions
# ----------------------------------
a
# Replace with your managed identity object ID
$miObjectID = "b17b7306-1b86-4dcb-b2bb-a79c162d818e"

# The app ID of the API where you want to assign the permissions
$appId = "00000003-0000-0000-c000-000000000000"

# The app IDs of the Microsoft APIs are the same in all tenants:
# Microsoft Graph: 00000003-0000-0000-c000-000000000000
# SharePoint Online: 00000003-0000-0ff1-ce00-000000000000

# Replace with the permissions to remove
$permissionsToRemove = "Application.Read.All", "User.Read.All"

Connect-AzureAD

$app = Get-AzureADServicePrincipal -Filter "AppId eq '$appId'"

$appRoles = Get-AzureADServiceAppRoleAssignment -ObjectId $app.ObjectId | where PrincipalId -eq $miObjectID

foreach ($appRole in $appRoles) {
    $role = $app.AppRoles | where Id -eq $appRole.Id | Select-Object -First 1
    if ($permissionsToRemove.Contains($role.Value)) {
        Remove-AzureADServiceAppRoleAssignment -ObjectId $app.ObjectId -AppRoleAssignmentId $appRole.ObjectId
    }    
}