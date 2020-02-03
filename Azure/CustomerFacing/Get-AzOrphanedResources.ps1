
function Get-AzOrphanedResources {
    <#
    .SYNOPSIS
        This script is designed to export a list of orphaned Azure resources. 
    .DESCRIPTION
        This script does not install or make any changes.   It does have the following requirements that if not met, will stop the script from running
        - Running in PowerShell 5.1 or newer context
        - The following modules need to be installed
            - Az.Resources
            - Az.Accounts 
            - ImportExcel
        
    .INPUTS
        No input is needed to run the script.  If you are not connected to Azure it will prompt you to login. 
    .OUTPUTS
        It will output an Excel file on the current user's desktop that has a tab for the following orphaned resources.  (Excel does not need to be installed on the workstation running the file)
        - Network Security Groups
        - Public IP addresses
        - NICs
        - Managed Disks
        - Unmanaged Disks
    .NOTES
        Version:        1.0
        Author:         Joe Fecht - AHEAD, llc.
        Creation Date:  February 2020
        Purpose/Change: Initial deployment
    
    .EXAMPLE
        Get-AzOrphanedResources
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
        # Module to check for Orphaned NSGs
        #----------------------------------------------------------------------------------------
        function Get-AzOrphangedNetworkSecurityGroups {
            [CmdLetBinding()]
            param ()

            process {
                $orphanedNSGs = Get-AzNetworkSecurityGroup | Where-Object { ($_.NetworkInterfaces.Count -eq 0) -and ($_.subnets.Count -eq 0) }
                
                foreach ($orphanedNSG in $orphanedNSGs) {
                    $nsgNname = $orphanedNSG.Name
                    $nsgRgName = $orphanedNSG.ResourceGroupName
                    $nsgLocation = $orphanedNSG.Location
                    $nsgId = $orphanedNSG.id
                    $nsgRuleCount = $orphanedNSG.SecurityRules.Count
                    #$nsgTags        = $orphanedNSG.TagsTable

                    $nsgProps = [ordered]@{
                        NSG_Name       = $nsgNname
                        Resource_Group = $nsgRgName
                        Location       = $nsgLocation
                        Rule_Count     = $nsgRuleCount
                        Resource_Id    = $nsgId
                        #Tags           = $nsgTags
                    }
                    
                    New-Object -TypeName psobject -Property $nsgProps
                    
                }
            }
        }

        #----------------------------------------------------------------------------------------
        # Module to check for Orphaned Public IPs
        #----------------------------------------------------------------------------------------
        function Get-AzOrphanedPublicIps {
            [CmdletBinding()]
            param ()
            
            process {
                $orphanedPIPs = Get-AzPublicIpAddress | Where-Object { $_.IpConfiguration -eq $null }

                foreach ($orphanedPIP in $orphanedPIPs) {

                    $pipName = $orphanedPIP.Name
                    $pipRgName = $orphanedPIP.ResourceGroupName
                    $pipLocation = $orphanedPIP.Location
                    $pipSku = $orphanedPIP.Sku.Name
                    $pipAllocationMethod = $orphanedPIP.PublicIpAllocationMethod
                    $pipId = $orphanedPIP.id
                    #$pipTags                = $orphanedPIP.TagsTable

                    $pipProps = [ordered]@{
                        PublicIP_Name     = $pipName
                        Resource_Group    = $pipRgName
                        Location          = $pipLocation
                        SKU               = $pipSku
                        Allocation_Method = $pipAllocationMethod
                        Resource_Id       = $pipId
                        #Tags              = $pipTags
                    }
                    
                    New-Object -TypeName psobject -Property $pipProps
                }
            }
        }

        #----------------------------------------------------------------------------------------
        # Module to check for Orphaned NICs
        #----------------------------------------------------------------------------------------
        function Get-AzOrphanedNICs {
            [CmdletBinding()]
            param()

            process { 
                $orphanicNICs = Get-AzNetworkInterface | Where-Object { ($_.PrivateEndpoint -eq $null) -and ($_.VirtualMachine -eq $null) }

                foreach ($orphanedNIC in $orphanicNICs) {

                    $nicName = $orphanedNIC.Name
                    $nicRgName = $orphanedNIC.ResourceGroupName
                    $nicLocation = $orphanedNIC.Location
                    $nicIpConfigCount = $orphanedNIC.IpConfigurations.Count
                    $nicId = $orphanedNIC.id
                    #$nicTags            = $orphanedNIC.TagsTable

                    $nicProps = [ordered]@{
                        NIC_Name        = $nicName
                        Resource_Group  = $nicrgName
                        Location        = $nicLocation
                        IP_Config_Count = $nicIpConfigCount
                        Resource_Id     = $nicId
                        #Tags            = $nicTags
                    }

                    New-Object -TypeName psobject -Property $nicProps
                }
            }
        }
        
        #----------------------------------------------------------------------------------------
        # Module to check for Orphaned Managed Disks
        #----------------------------------------------------------------------------------------
        function Get-AzOrphanedManagedDisks {
            [CmdletBinding()]
            param ()

            process { 
                $orphanedMngDisks = Get-AzDisk | Where-Object { ($_.ManagedBy -eq $null) -and ($_.DiskState -eq "Unattached") }

                foreach ($orphanedMngDisk in $orphanedMngDisks) {
                    
                    $diskName = $orphanedMngDisk.Name
                    $diskRgName = $orphanedMngDisk.ResourceGroupName
                    $diskLocation = $orphanedMngDisk.Location
                    $diskType = $orphanedMngDisk.Sku.Name
                    $diskSize = $orphanedMngDisk.DiskSizeGb
                    $diskId = $orphanedMngDisk.id
                    #$diskTags = $orphanedMngDisk.TagsTable

                    $mngDiskProps = [ordered]@{
                        Disk_Name      = $diskName
                        Disk_Type      = "Managed" 
                        Resource_Group = $diskRgName
                        Location       = $diskLocation
                        Disk_Tier      = $diskType
                        Disk_Size_GB   = $diskSize
                        Resource_ID    = $diskId
                        #Tags           = $diskTags
                        
                    }

                    New-Object -TypeName psobject -Property $mngDiskProps

                }
            }
            
        }

        #----------------------------------------------------------------------------------------
        # Module to check for Orphaned Unmanaged Disks
        #----------------------------------------------------------------------------------------
        function Get-AzOrphanedUnmanagedDisks {
            [CmdletBinding()]
            param ()

            process {

                $storageAccounts = Get-AzStorageAccount
                foreach ($storageAccount in $storageAccounts) {
                    $stgAcct = Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction SilentlyContinue
                    if ($stgAcct -ne $null) {
                        if ($stgAcct[0].value) {
                            $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction SilentlyContinue)[0].Value
                            $context = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey
                            $containers = Get-AzStorageContainer -Context $context -ErrorAction silentlycontinue
                            foreach ($container in $containers) {
                                $blobs = Get-AzStorageBlob -Container $container.Name -Context $context | Where-Object { $_.BlobType -eq 'PageBlob' -and $_.Name.EndsWith('.vhd') }
                                foreach ($blob in $blobs) {
                                    if ($blob.ICloudBlob.Properties.LeaseStatus -eq 'Unlocked') {
                                        $unmngDiskName = $blob.ICloudBlob.Name
                                        $unmngDiskRgName = $storageAccount.ResourceGroupName
                                        $unmngDiskLocation = $StorageAccount.Location
                                        $unmngDiskUri = $blob.IcloudBlob.Uri.AbsoluteUri
                                        $unmngDiskSku = $storageAccount.Sku.Name
                                        $unmngDiskSize = [MATH]::floor([decimal]($blob.ICloudBlob.Properties.Length) / 1073741824)
                                        #$stgAcctTags = $storageAccount.Tags

                                        $unmngDiskProps = [ordered]@{
                                            Disk_Name      = $unmngDiskName
                                            Disk_Type      = "Unmanaged"
                                            Resource_Group = $unmngDiskRgName
                                            Location       = $unmngDiskLocation
                                            Disk_URI       = $unmngDiskUri
                                            Disk_Tier      = $unmngDiskSku
                                            Disk_Size_GB   = $unmngDiskSize
                                            #Stg_Acct_Tags  = $stgAcctTags
                                        }

                                        New-Object -TypeName psobject -Property $unmngDiskProps
                                            
                                    }
                                }
                            }
                        }
                    }
                    Else {
                        #Unable to access Storage Key
                    }
                }
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
                    Write-Verbose "Running on a non Windows.  Saving file to /users/%USERNAME%/Desktop"
                    $path = "$env:HOME/Desktop/Orphaned-Resources-$date.xlsx"
                }
                else {
                    Write-Verbose "Running a Windows PC. Saving file to C:\users\%USERNAME%\Desktop"
                    $path = "$env:HOMEPATH\Desktop\Orphaned-Resources-$date.xlsx"
                }
                return $path
            }
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

        #----------------------------------------------------------------------------------------
        # Main Function
        #----------------------------------------------------------------------------------------
        
        #Validate necessary modules are installed
        Write-Verbose "Ensuring the proper PowerShell Modules are installed"
        $installedModules = Confirm-ModulesInstalled -modules az.accounts, az.resources, ImportExcel

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

        # Defining all variables
        $Date = (Get-Date).ToShortDateString().Replace("/", "-")
        $orphanedNICs = @()
        $orphanedPIPs = @()
        $orphanedNSGs = @()
        $orphanedMngDisks = @()
        $orphanedUnmngDisks = @()
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
        
        ## Finding orphaned resources in each sub
        foreach ($azSub in $selectedAzSubs) {
            $outNull = Set-AzContext -SubscriptionId $azSub.subId -TenantID $azsub.subTenantId | select -expand name
            $azSubName = $azSub.subName
            Write-Host "Checking for orphaned resources in sub: $azSubName" -ForegroundColor green
            $subOrphanedNICs = Get-AzOrphanedNICs
            $subOrphanedPIPs = Get-AzOrphanedPublicIps
            $subOrphanedNSGs = Get-AzOrphangedNetworkSecurityGroups
            $subOrphanedMngDisks = Get-AzOrphanedManagedDisks
            $subOrphanedUnmngDisks = Get-AzOrphanedUnmanagedDisks

            $orphanedNICs += $subOrphanedNICs
            $orphanedPIPs += $subOrphanedPIPs
            $orphanedNSGs += $subOrphanedNSGs
            $orphanedMngDisks += $subOrphanedMngDisks
            $orphanedUnMngDisks += $subOrphanedUnmngDisks
        }

        $excelPath = Get-DesktopPath -date $date

        ## Remove existing orphaned resource report
        If (Test-Path $excelPath) {
            Remove-Item $excelPath -Force
        }

        #Outputing Excel File to current users desktop
        $orphanedPIPs | Export-Excel -Path $excelPath -WorksheetName "Public IPs"
        $orphanedNSGs | Export-Excel -Path $excelPath -WorksheetName "NSGs"
        $orphanedNICs | Export-Excel -Path $excelPath -WorksheetName "NICs"
        $orphanedMngDisks | Export-Excel -Path $excelPath -WorksheetName "Managed Disks"
        $orphanedUnmngDisks | Export-Excel -Path $excelPath -WorksheetName "Unmanaged Disks"

    }

}



Get-AzOrphanedResources

