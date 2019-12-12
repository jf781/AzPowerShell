#
#   AHEAD LLC - November 2019
#   This will run through all Azure Subscriptions that you have permissions to on the current tenant and will `
#   get all role assignments associated with the Subscription, Resource Groups, and Management Groups. `
#   It will save the output to a CSV file on your desktop
#

function Confirm-PSVersion {
    [CmdLetBinding()]
    param (
    )
    PROCESS {
        Write-Verbose "Testing to see if PowerShell v5.1 or later is installed"
        try { 
            Write-Verbose "Testing to see if PowerShell v5.1 or later is installed"
            If ($PSVersionTable.PSVersion.Major -ge "6") {
                Write-Verbose "PSVersion is 6 or newer"
                $compatible = $true
            }
            ElseIf ($PSVersionTable.PSVersion.Major -eq "5") {
                If ($PSVersionTable.PSVersion.Minor -ge "1") {
                    Write-Verbose "PS Verion is 5.1 or newer"
                    $compatible = $true
                }
                Else {
                    Write-Verbose "PS Version is v5 but not 5.1 or newer"
                    $compatible = $false
                }
            }
            Else {
                Write-Verbose "PS Version is 4 or later"
                $compatible = $false
            }
        }
        catch {
            Write-Verbose "In Catch block.  Error occurred determining PS Version"
            Write-Host "Error determining PowerShell version" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
            break
        }
        return $compatible
    }   
}

function Confirm-ModulesInstalled {
    [CmdLetBinding()]
    param (
        [Parameter(
            Mandatory = $false,
            ValueFromPipeline = $true
        )]
        [string[]]
        $modules
    )
    PROCESS {
        Write-Verbose "Testing if Modules are installed"
        $results = @()
        foreach ($module in $modules) {
            try {
                Write-Verbose "Testing for module $module"
                Import-Module -Name $module -ErrorAction SilentlyContinue
                if (Get-Module -Name $module) {
                    Write-Verbose "Module $module is installed"
                    $moduleTests = [PSCustomObject]@{
                        ModuleName = $module
                        Installed  = $true
                    }
                }
                Else {
                    Write-Verbose "Module $module is NOT installed"
                    $moduleTests = [PSCustomObject]@{ 
                        ModuleName = $module
                        Installed  = $false
                    }
                }
                $results += $moduleTests
                
            }
            catch {
                Write-Verbose "Error checking for $module"
                Write-Host "Error checking for module - $module" -ForegroundColor Red
                Write-Host "Error Msg: $_" -ForegroundColor Red
            }
        }            
        return $results
    }
}

Function Export-RBACRoles { 
    [CmdletBinding()]
    Param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [object[]]
        $role,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [string]
        $roleScope,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]
        $azSubName
    )
    PROCESS { 
        #Defining variables for the object
        $roleDisplayName = $role.DisplayName
        $roleSignInName = $role.SignInName
        $roleDefinitionName = $role.RoleDefinitionName
        $roleDefinitionId = $role.RoleDefinitionId
        $roleObjectType = $role.objectType

        $roleProps = [ordered]@{
            Subscription    = $azSubName
            Scope           = $roleScope
            AssignedTo      = $roleDisplayName
            SignInName      = $roleSignInName
            ObjectType      = $roleObjectType 
            RolePermissions = $roleDefinitionName
            RoleID          = $roleDefinitionId
        }

        New-Object -TypeName psobject -Property $roleProps
    }
}

Function Get-AzSubPermissions { 
    [CmdletBinding()]
    Param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [string]
        $subscriptionID,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromRemainingArguments = $true
        )]
        [string]
        $tenantID,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]
        $azSubName
    )
    PROCESS {
        Write-Verbose "Attempting to connect to the subscription with SubID = $subscriptionID"
        try { 

            $azSub = Set-AzContext -SubscriptionId $subscriptionID -TenantId $tenantId -ErrorAction Stop
            Write-Verbose "Successfully connected to $azSubName"
    
            #Defining Subscription level variables
            $azSubScope = "/subscriptions/" + $azSub.Subscription
            $subRBACRoles = @()
        }
        Catch {

            Write-Verbose "Failed to connect to subscription with SudID = $subscriptionID, TenantID = $tenantID"
            Write-Host "Unable to Connect to SubscriptionID $subscriptionID" -ForegroundColor red 
            Write-Host "Error Msg: $_" -ForegroundColor Red
            exit
        }

        Write-Verbose "Getting the resource groups from $azSubName" 
        $resGroups = Get-AzResourceGroup

        try {
    
            Write-Host "Getting RBAC roles for subscription - $azSubName" -ForegroundColor Green
            Write-Verbose "Running through each resource group to check permissions"
    
            Foreach ($resGroup in $resGroups) {

                Write-Verbose "Getting RBAC Roles assigned to ResourceGroup - $resGroup.ResourceGroupName"
                $resGroupRoles = Get-AzRoleAssignment -ResourceGroupName $resGroup.ResourceGroupName -ErrorAction Stop

                foreach ($role in $resGroupRoles) {
            
                    #Defining variables to test role scope
                    $roleScope = $role.Scope
                    $roleName = $role.name
                    Write-Verbose "Getting Details of role - $roleName in resouce group -$resGroup"

                    switch -Wildcard ($roleScope) {
                        $azSubScope {
                            Write-Verbose "$roleScope matched the `$subScope"
                            # Not documenting role for resource groups
                        }
                        "/providers/Microsoft.Management/managementGroups/*" {
                            Write-Verbose "$roleScope matched the as a Management group"
                            # Not documenting role for resource groups
                        }
                        "/" { 
                            Write-Verbose "$roleScope matched the as a root assignment"
                            # Not documenting role for resource groups
                        }
                        Default { 
                            Write-Verbose "$rolescope is not defined at a subscription or management group level"
                            $roleRBAC = Export-RBACRoles -role $role -roleScope $roleScope -azSubName $azSubName
                            $subRBACRoles += $roleRBAC
                        }
                    }
                }
            }
        }
        Catch { 

            Write-Verbose "Error occurred obtaining role assigned to resource group $resGroup"
            Write-Host "Error getting roles from the resouce group - $resGroup" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
        }
        

        try {

            Write-Verbose "Logging roles for root assignments"
            $azRoles = Get-AzRoleAssignment -ErrorAction Stop
    
            Foreach ($rootRole in $azRoles) {
                $rootRoleName = $rootRole.name

                if ($rootRole.scope -eq "/") {
                    Write-Verbose "Logging $rootRoleName for the root assignments"
                    $RootRBAC = Export-RBACRoles -role $rootRole -roleScope "/" -azSubName $azSubName
                    $subRBACRoles += $RootRBAC
                }
                Else {
                    Write-Verbose "$rootRoleName is not assigned to the root"
                }
            }
        }
        Catch {

            Write-Verbose "Error obtaining roles for root assignement"
            Write-Host "Error logging roles for root assignments" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
        }

        try {
    
            Write-Verbose "Logging roles for Mgmt assignments"
    
            Foreach ($mgmtRole in $azRoles) {

                $mgmtRoleName = $mgmtRole.Name
                Write-Verbose "Checking to see if $mgmtRoleName is for a maangement group"
                if ($mgmtRole.Scope -like "/providers/Microsoft.Management/managementGroups/*") {

                    Write-Verbose "$mgmtRoleName is part of a mgmt group"
                    $mgmtRoleScope = $mgmtRole.Scope
                    Write-Verbose "Logging $mgmtRoleName for the root assignments"
                    $mgmtRBAC = Export-RBACRoles -role $mgmtRole -roleScope $mgmtRoleScope -azSubName $azSubName
                    $subRBACRoles += $mgmtRBAC
                }
                Else { 

                    Write-Verbose "$mgmtRoleName is not for a management group"
                }
            }
        }
        Catch {

            Write-Verbose "Error obtaining roles for Subscription assignement"
            Write-Verbose "Error Msg: $_"
            Write-Host "Error logging roles for Management assignments" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
        }
        
        try {

            Write-Verbose "Logging roles for Subscription assignments"
            $azSubRoles = Get-AzRoleAssignment -Scope "$azSubScope" -ErrorAction Stop
    
            Foreach ($azSubRole in $azSubRoles) {

                $azSubRoleName = $azSubRole.name
                Write-Verbose "Logging $azSubRoleName for the root assignments"
                $azSubRBAC = Export-RBACRoles -role $azSubRole -roleScope $azSubScope -azSubName $azSubName
                $subRBACRoles += $azSubRBAC
            }
        }
        Catch {

            Write-Verbose "Error obtaining roles for Subscription assignement"
            Write-Host "Error logging roles for Subscription assignments:" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
        }

        return $subRBACRoles
    }
}

Function Get-AzSubsFromTenant {
    [CmdletBinding()]
    param (
    )
    PROCESS {
        Write-Verbose "Testing to see if connected to Azure"
        $Context = Get-AzContext
        try {
            if ($Context) {
                Write-Verbose "Connected to Azure"
            }
            Else {
                Write-Verbose "Need to connect to Azure"
                Write-Host "Connecting to Azure.  Please check for a browser window asking for you to login" -ForegroundColor Yellow
                Login-AzAccount -ErrorAction Stop
            }
        }
        catch {
            Write-Verbose "Error validating connection to Azure."
            Write-Host "Error validating connection to Azure" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
            break
        }

        Write-Verbose "Getting list of Azure Subscriptions"
        $azSubs = Get-AzSubscription
        $tenantProps = @()

        foreach ($azSub in $azSubs) {
            Write-Verbose "Getting information about $Azsub"
            $subName = $azSub.Name
            $subId = $azSub.SubscriptionID
            $subTenantId = $azSub.TenantID
            $subProps = [pscustomobject]@{
                subName = $subName
                subID   = $subId
                subTenantId = $subTenantId
             }
            $tenantProps += $subProps
        }
        return $tenantProps
    }
}

 
Write-Verbose "Ensure PowerShell 5.1 or later is installed"
If (Confirm-PSVersion) {
    Write-Verbose "PowerShell 5.1 or later is installed"
}
Else {
    Write-Verbose "A later version of PowerShell is installed"
    Write-Host "The version of PowerShell is older then what is supported.  Please updated to a version 5.1 or newer of PowerShell" -ForegroundColor Yellow
    Write-Host "Please visit the site below for details on the current version of PowerShell (As of December 2019)" -ForegroundColor Yellow
    Write-Host "https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-6" -ForegroundColor Green
    Write-Host "Script is exiting" -ForegroundColor Yellow
    Exit
}

Write-Verbose "Ensuring the proper PowerShell Modules are installed"
$installedModules = Confirm-ModulesInstalled -modules az.accounts, az.resources

foreach ($installedModule in $installedModules) {
    $moduleName = $installedModule.ModuleName
    If ($installedModule.installed) {
        Write-Verbose "$moduleName is installed"
    }
    Else {
        Write-Verbose "$moduleName is not installed"
        Write-Host "The PowerShell Module: $moduleName is not installed.  Please run the command below to install the module" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "     Install-Module -Name $moduleName -Repository PSGallery" -ForegroundColor Green
        Write-Host ""
    }
}

If ($installedModules.installed -contains $false) {
    Write-Verbose "There are PowerShell modules that need to be installed"
    Write-Host ""
    Write-Host "Existing script.  Please run the necessary commands listed in GREEN above to install the needed modules" -ForegroundColor Yellow
    exit
}
Else {
    Write-Verbose "Needed modules are installed.  Proceeding with script"
}

$Date = ((Get-Date).ToShortDateString()).Replace("/", "-")
$tenantRBAC = @()

Write-Verbose "Getting subs associated with Tenant"
$tenantSubs = Get-AzSubsFromTenant

Write-verbose "Getting RBAC permissions for each subscription"
foreach ($tenantSub in $tenantSubs) {
    $tenantSubRBAC = Get-AzSubPermissions -subscriptionID $tenantSub.subID -tenantID $tenantSub.SubTenantId -azSubName $tenantSub.subName
    $tenantRBAC += $tenantSubRBAC
}

If ($env:HOME) {
    Write-Verbose "Running on a non Windows.  Saving file to /users/%USERNAME%/Desktop"
    $tenantRBAC | ConvertTo-Csv -NoTypeInformation | Out-File $env:HOME/Desktop/Azure-RBAC-Output-$Date.csv
}
else {
    Write-Verbose "Running a Windows PC. Saving file to C:\users\%USERNAME%\Desktop"
    $tenantRBAC | ConvertTo-Csv -NoTypeInformation | Out-File $env:HOMEPATH\Desktop\Azure-RBAC-Output-$Date.csv
}