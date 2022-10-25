function Get-AzRbacReport {
    <#
    .SYNOPSIS
        This script is will return a list of resources within one or more Azure subscriptions

    .DESCRIPTION
        This script does not install or make any changes.   It does have the following requirements that if not met, will stop the script from running
        - Running in PowerShell 5.1 or newer context
        - The following modules need to be installed
            - Az.*
            - ImportExcel
        
    .INPUTS
        No input is needed to run the script.  If you are not connected to Azure it will prompt you to login. 

    .OUTPUTS
        

    .NOTES
        Version:        1.0
        Author:         Joe Fecht - AHEAD, llc.
        Creation Date:  February 2022
        Purpose/Change: Initial deployment
    
    .EXAMPLE
        Get-AzResourceList 
    #>
    [CmdletBinding()]
    param (
        
    )
    process {

        #----------------------------------------------------------------------------------------
        # Confirm PS Version and Az module is installed
        #----------------------------------------------------------------------------------------
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

        #----------------------------------------------------------------------------------------
        # Module to get the RBAC Report
        #----------------------------------------------------------------------------------------
        
        function Get-AzResourcesWithinRG {
            [CmdLetBinding()]
            param (
                [Parameter(
                    Mandatory = $true,
                    ValueFromPipeline = $true
                )]
                [string]
                $resourceGroupName
            )
            PROCESS {
                try {
                    $subName = (Get-AzContext | Select-Object -ExpandProperty Name).Split('(')[0]
                    $resources = Get-AzResource -ResourceGroupName $resourceGroupName
                }catch{
                    Write-Verbose "In Catch block.  Error occurred determining resources within $resourceGroupName"
                    Write-Host " Error occurred determining resources within $resourceGroupName" -ForegroundColor Red
                    Write-Host "Error Msg: $_" -ForegroundColor Red
                    break
                }

                if ($resources -ne $null){
                    foreach ($resource in $resources){

                        $props = [ordered]@{
                            Subscription                = $subName
                            ResourceGroupName           = $resourceGroupName
                            ResourceName                = $resource.Name
                            ResourceType                = $resource.ResourceType
                            Location                    = $resource.Location
                        }
                        
                        New-Object -TypeName psobject -Property $props

                    }
                }else{
                    $rgLocation = Get-AzResourceGroup -Name $resourceGroupName | Select-Object -ExpandProperty Location

                    $props = [ordered]@{
                        Subscription                = $subName
                        ResourceGroupName           = $resourceGroupName
                        ResourceName                = "Empty resource group"
                        ResourceType                = "Empty resource group"
                        Location                    = $rgLocation
                    }
                    
                    New-Object -TypeName psobject -Property $props
                }
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
        
                $props = [ordered]@{
                    Subscription    = $azSubName
                    Scope           = $roleScope
                    AssignedTo      = $roleDisplayName
                    SignInName      = $roleSignInName
                    ObjectType      = $roleObjectType 
                    RolePermissions = $roleDefinitionName
                    RoleID          = $roleDefinitionId
                }

                New-Object -TypeName psobject -Property $props
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
                    break
                }

                Write-Verbose "Getting the resource groups from $azSubName" 
                $resGroups = Get-AzResourceGroup
            
                Write-Host "Getting RBAC roles for subscription - $azSubName" -ForegroundColor Green
                Write-Verbose "Running through each resource group to check permissions"
            
                Foreach ($resGroup in $resGroups) {

                    try {

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
                    Catch { 

                        Write-Verbose "Error occurred obtaining role assigned to resource group $resGroup"
                        Write-Host "Error getting roles from the resouce group - $resGroup" -ForegroundColor Red
                        Write-Host "Error Msg: $_" -ForegroundColor Red
                    }
                }
        
                try {

                    Write-Verbose "Logging roles for root assignments"
                    $rootRoles = Get-AzRoleAssignment -ErrorAction Stop
            
                    Foreach ($rootRole in $rootRoles) {
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

                    Write-Verbose "Logging roles for Subscription assignments"
                    $azSubRoles = Get-AzRoleAssignment -Scope "$azSubScope" -ErrorAction Stop
            
                    Foreach ($azSubRole in $azSubRoles) {
                      $roleScope = $azSubRole.Scope
                      if($roleScope -eq $azSubScope){
                        Write-Verbose "Logging $azSubRoleName for the subscription"
                        $azSubRBAC = Export-RBACRoles -role $azSubRole -roleScope $azSubScope -azSubName $azSubName
                        $subRBACRoles += $azSubRBAC
                      }else{
                        Write-Verbose "Role is not scoped to subscription"
                      }
                    }
                }
                Catch {

                    Write-Verbose "Error obtaining roles for Subscription assignement"
                    Write-Host "Error logging roles for Subscription assignments:" -ForegroundColor Red
                    Write-Host "Error Msg: $_" -ForegroundColor Red
                }

                try {
            
                    Write-Verbose "Logging roles for Mgmt assignments"
                    $MgmtRoles = Get-AzRoleAssignment -ErrorAction Stop
            
                    Foreach ($mgmtRole in $MgmtRoles) {

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
                    Write-Host "Error logging roles for Management assignments" -ForegroundColor Red
                    Write-Host "Error Msg: $_" -ForegroundColor Red
                }

                return $subRBACRoles
            }
        }

        #----------------------------------------------------------------------------------------
        # Modules to determine path to save Excel file
        #----------------------------------------------------------------------------------------
        function Get-DesktopPath {
            [CmdletBinding()]
            Param(
                [Parameter(
                    ValueFromPipeline = $true
                )]
                [string]
                $date
            )

            process { 
                If ($env:HOME) {
                    Write-Verbose "Running on a non Windows computer.  Saving file to /users/%USERNAME%/Desktop"
                    $path = "$env:HOME/Desktop/AzRbacReport-$date.xlsx"
                    $desktopPath = "$env:HOME/Desktop"
                }
                elseif($env:HOMEPATH) {
                    Write-Verbose "Running a Windows PC. Saving file to C:\users\%USERNAME%\Desktop"
                    $path = "$env:HOMEPATH\Desktop\AzRbacReport-$date.xlsx"
                    $desktopPath = "$env:HOMEPATH\Desktop\"
                }

                If (Test-Path -Path $desktopPath){
                    Write-Verbose "Desktop path is valid"
                }
                Else{
                    Write-Verbose "Path is not valid.  Setting output to current working directory"
                    $folderPath = Get-Location | Select-Object -ExpandProperty Path
                    if($env:HOME){
                        Write-Verbose "Running on a non Windows computer."
                        $path = $folderPath + "/AzRbacReport-$date.xlsx"
                    }else{
                        Write-Verbose "Running on a Windows computer."
                        $path = $folderPath + "\AzRbacReport-$date.xlsx"
                    }
                }

                return $path
            }
        }


        #----------------------------------------------------------------------------------------
        # Module to get subs from the Tenant
        #----------------------------------------------------------------------------------------
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
                        $null = Login-AzAccount -ErrorAction Stop
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
                $i = 0

                foreach ($azSub in $azSubs) {
                    Write-Verbose "Getting information about $Azsub"
                    $subName = $azSub.Name
                    $subId = $azSub.SubscriptionID
                    $subTenantId = $azSub.TenantID
                    $subProps = [pscustomobject]@{
                        index       = $i
                        subName     = $subName
                        subID       = $subId
                        subTenantId = $subTenantId
                    }
                    $tenantProps += $subProps
                    $i++
                }
                return $tenantProps
            }
        }

        function Read-AzSubsToRunAgainst() {
            $input_subs = @()
            $user_input = Read-Host "Select Subscriptions (example: 0,2)"
            $input_subs = $user_input.Split(',') | ForEach-Object { [int]$_ }
            return $input_subs
        }

        #----------------------------------------------------------------------------------------
        # Modules to validate user input
        #----------------------------------------------------------------------------------------
        function Confirm-Numeric ($Value) {
            return $Value -match "^[\d\.]+$"
        }

        function Confirm-ValidSelectedIds($ids, $subs) {
            if ($ids.Length -gt $subs.Length) {
                Write-Host -fore red "Too many subscription indexes selected." -Verbose
                return 1
            }
            for ($i = 0; $i -le $ids.Length - 1; $i++) {
                $index = [int]$ids[$i]
                $is_numeric = Confirm-Numeric $index
                if (!$is_numeric) {
                    Write-Host -fore red "Invalid subscription selection, enter only numbers." -Verbose
                    return 1
                }
                if ($index -gt $subs.Length - 1) {
                    Write-Host -fore red "Invalid subscription selection, only select valid indexes." -Verbose
                    return 1
                }
            }
            return 0
        }

        #----------------------------------------------------------------------------------------
        # Main Function
        #----------------------------------------------------------------------------------------
                
        #Validate necessary modules are installed
        Write-Verbose "Ensuring the proper PowerShell Modules are installed"
        $installedModules = Confirm-ModulesInstalled -modules az,  ImportExcel
        $modulesNeeded = $False

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
                $modulesNeeded = $true
            }
        }

        If ($modulesNeeded) {
            Write-Host "Please install the modules listed above and then run the script again" -ForegroundColor Yellow
            Exit
        }

        # Defining all variables
        $date = (Get-Date).ToShortDateString().Replace("/", "-")
        $rbacReport = @()
        $selectedAzSubs = @()

        #Gathering and determine which subs to run against. 
        $azSubs = Get-AzSubsFromTenant 
        Write-Output $azSubs | Format-Table -AutoSize

        $selectedSubIds = Read-AzSubsToRunAgainst

        $selectedSubsValid = Confirm-ValidSelectedIds $selectedSubIds $azSubs
        if ($selectedSubsValid -ne 0) {
            exit
        }
        Else {
            #Sub selection valid
        }

        ForEach ($selectedSubId in $selectedSubIds) {
            $sub = $azSubs | Where-Object { $_.Index -eq $selectedSubId }
            $selectedAzSubs += $sub
        }
                
        ## Gathering security score in each sub
        foreach ($azSub in $selectedAzSubs) {
            $null = Set-AzContext -SubscriptionId $azSub.subId -TenantID $azsub.subTenantId | Select-Object -ExpandProperty name
            $azSubName = $azSub.subName
            Write-Host "Creating RBAC report in sub: $azSubName" -ForegroundColor green

            $SubRBAC = Get-AzSubPermissions -subscriptionID $azSub.subId -tenantID $azSub.subTenantId -azSubName $azSub.subName
            $rbacReport += $SubRBAC

        }

        $excelPath = Get-DesktopPath -date $date

        ## Remove existing resource report
        If (Test-Path $excelPath) {
            Remove-Item $excelPath -Force
        }

        #Outputing Excel File to current users desktop
        $rbacReport | Export-Excel -Path $excelPath -WorksheetName "AzureResources"

    }

}