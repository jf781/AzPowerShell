function Get-AzKeyVaultAccessPolicies {
    <#
    .SYNOPSIS
        This script is designed to export the access policies of a Key Vault. 

    .DESCRIPTION
        This script does not install or make any changes.   It does have the following requirements that if not met, will stop the script from running
        - Running in PowerShell 5.1 or newer context
        - The following modules need to be installed
            - Az.KeyVault
            - ImportExcel
        
    .INPUTS
        No input is needed to run the script.  If you are not connected to Azure it will prompt you to login. 

    .OUTPUTS
        

    .NOTES
        Version:        1.0
        Author:         Joe Fecht - AHEAD, llc.
        Creation Date:  August 2021
        Purpose/Change: Initial deployment
    
    .EXAMPLE
        Get-AzKeyVaultAccessPolicies
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
        # Module to get the key vault access policies
        #----------------------------------------------------------------------------------------
        
        function Get-AzKeyVaultPolicies {
            [CmdLetBinding()]
            param (
                [Parameter(
                    Mandatory = $true,
                    ValueFromPipeline = $true
                )]
                [string]
                $vaultName
            )
            PROCESS {
                try {
                    $subName = (Get-AzContext | Select-Object -ExpandProperty Name).Split('(')[0]
                    $kv = Get-AzKeyVault -VaultName $vaultName
                    $vaultName = $kv.VaultName
                }catch{
                    Write-Verbose "In Catch block.  Error occurred determining Getting Vault $vaultName"
                    Write-Host "In Catch block.  Error occurred determining Getting Vault $vaultName" -ForegroundColor Red
                    Write-Host "Error Msg: $_" -ForegroundColor Red
                    break
                }
        
                $count = 1

                if ($kv.NetworkAcls.DefaultAction -eq "Allow"){
                    $publicAccessRestrictured = "FALSE"
                } else {
                    $publicAccessRestrictured = "TRUE"
                }

                if ($kv.EnablePurgeProtection){
                    $purgeProtectionEnabled = "TRUE"
                } else {
                    $purgeProtectionEnabled = "FALSE"
                }


                
                if($kv){
                    if($kv.EnableRbacAuthorization){
                        Write-Debug "Determined Vault $vaultName is using RBAC authorization"
            
                        $rolesAssigned = Get-AzRoleAssignment -scope $kv.ResourceId | Where-Object -Property RoleDefinitionName -Like "*Key Vault*"
            
                        foreach ($assignment in $rolesAssigned){
            
                            if($assignment.Scope -eq $kv.ResourceId){
                                $roleAssignment = "Directly Assigned"
                            }else{
                                $roleAssignment = $assignment.Scope
                            }
            
                            $objectName = $assignment.DisplayName
                            $objectId = $assignment.objectId
                            $type = $assignment.ObjectType
                            $role = $assignment.RoleDefinitionName

                            if($count -eq "1"){
                                $firstEntry = "TRUE"
                            } else {
                                $firstEntry = "FALSE"
                            }
            
            
                            $props = [ordered]@{
                                Subscription                = $subName
                                VaultName                   = $vaultName
                                FirstKeyVaultEntry          = $firstEntry
                                PublicAccessRestrictured    = $publicAccessRestrictured
                                PurgeProtectionEnabled      = $purgeProtectionEnabled
                                RBAC                        = "TRUE"
                                ObjectName                  = $objectName
                                ObjectType                  = $type
                                ObjectId                    = $objectId
                                RoleAssigned                = $role
                                KeyPermissions              = "n/a"
                                SecretPermissions           = "n/a"
                                CertificatePermisssions     = "n/a"
                                StorageAcctPermissions      = "n/a"
                                RoleScope                   = $roleAssignment
                            }
                        
                            New-Object -TypeName psobject -Property $props

                            $count ++
                        }
            
                    }elseif($kv.AccessPolicies){
                        Write-Debug "Determined Vault $vaultName is using Access Policies to manage access."
                        
                        $policies = $kv.AccessPolicies
                        
                        foreach ($policy in $policies){

                            try {        
                                if(($policy.DisplayName).split(' (')[1]){
                                    $type = "User/Service Principal"
                                }else{
                                    $type = "Group"
                                }
                            } catch {
                                $type = "Unknown object"
                                continue
                            }

                            if($count -eq "1"){
                                $firstEntry = "TRUE"
                            } else {
                                $firstEntry = "FALSE"
                            }
                            
                            try {
                                $objectName = ($policy.DisplayName).split(' (')[0]
                            } catch {
                                $objectName = "Unknown"
                                continue
                            }

                            $objectId = $policy.ObjectId
                            $keyPerms = $policy.PermissionsToKeysStr
                            $secretPerms = $policy.PermissionsToSecretsStr
                            $certPerms = $policy.PermissionsToCertificatesStr
                            $stgAcctPerms = $policy.PermissionsToStorageStr
            
                            $props = [ordered]@{
                                Subscription                = $subName
                                VaultName                   = $vaultName
                                FirstKeyVaultEntry          = $firstEntry
                                PublicAccessRestrictured    = $publicAccessRestrictured
                                RBAC                        = "FALSE"
                                ObjectName                  = $objectName
                                ObjectType                  = $type
                                ObjectId                    = $objectId
                                RoleAssigned                = "n/a"
                                KeyPermissions              = $keyPerms
                                SecretPermissions           = $secretPerms
                                CertificatePermisssions     = $certPerms
                                StorageAcctPermissions      = $stgAcctPerms
                                RoleScope                   = "Direct"
                            }
                        
                            New-Object -TypeName psobject -Property $props

                            $count ++
                        }
                    }else{
                        $props = [ordered]@{
                            Subscription                = $subName
                            VaultName                   = $vaultName
                            FirstKeyVaultEntry          = "TRUE"
                            PublicAccessRestrictured    = $publicAccessRestrictured
                            PurgeProtectionEnabled      = $purgeProtectionEnabled
                            RBAC                        = "FALSE"
                            ObjectName                  = "n/a"
                            ObjectType                  = $type
                            ObjectId                    = "n/a"
                            RoleAssigned                = "n/a"
                            KeyPermissions              = "n/a"
                            SecretPermissions           = "n/a"
                            CertificatePermisssions     = "n/a"
                            StorageAcctPermissions      = "n/a"
                            RoleScope                   = "No access policies or RBAC permissions assigned to vault"
                        }
                    
                        New-Object -TypeName psobject -Property $props
                    }
                }else{
                    $props = [ordered]@{
                        Subscription                = $subName
                        VaultName                   = $vaultName
                        FirstKeyVaultEntry          = "n/a"
                        PublicAccessRestrictured    = "n/a"
                        PurgeProtectionEnabled      = "n/a"
                        RBAC                        = "n/a"
                        ObjectName                  = "n/a"
                        ObjectType                  = "n/a"
                        ObjectId                    = "n/a"
                        RoleAssigned                = "n/a"
                        KeyPermissions              = "n/a"
                        SecretPermissions           = "n/a"
                        CertificatePermisssions     = "n/a"
                        StorageAcctPermissions      = "n/a"
                        RoleScope                   = "No data returned when querying key vault"
                    }
                
                    New-Object -TypeName psobject -Property $props
                }
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
                $date,
                [Parameter(
                    ValueFromPipeline = $true
                )]
                [string]
                $workbookName

            )

            process { 

                $worksheet = $workbookName + "-" + $date + ".xlsx"
                If ($env:HOME) {
                    Write-Verbose "Running on a non Windows computer.  Saving file to /users/%USERNAME%/Desktop"
                    $path = "$env:HOME/Desktop/$worksheet"
                    $desktopPath = "$env:HOME/Desktop"
                }
                elseif($env:HOMEPATH) {
                    Write-Verbose "Running a Windows PC. Saving file to C:\users\%USERNAME%\Desktop"
                    $path = "$env:HOMEPATH\Desktop\$worksheet"
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
                        $path = $folderPath + "/$worksheet"
                    }else{
                        Write-Verbose "Running on a Windows computer."
                        $path = $folderPath + "\$worksheet"
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
        $installedModules = Confirm-ModulesInstalled -modules az.network,  ImportExcel
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
        # $accessPolicies = @()
        $accessPolicies = [System.Collections.ArrayList]::new()
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
            Write-Host "Getting key vaults in sub: $azSubName" -ForegroundColor green
            $keyVaults = Get-AzKeyVault
            foreach($vault in $keyVaults){
                $vaultAccessPolicies = Get-AzKeyVaultPolicies -vaultName $vault.VaultName
                # $accessPolicies += $vaultAccessPolicies
                $accessPolicies.Add($vaultAccessPolicies) | Out-Null
            }
        }

        $excelPath = Get-DesktopPath -date $date -workbookName "KeyVaultAccessPolicies"

        ## Remove existing resource report
        If (Test-Path $excelPath) {
            Remove-Item $excelPath -Force
        }

        #Outputing Excel File to current users desktop
        $accessPolicies | Export-Excel -Path $excelPath -WorksheetName "AccessPolicies"


    }

}