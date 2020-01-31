<#
## This sections is for the core scriptes

#Get Orphaned NSGs
Get-AzNetworkSecurityGroup | Where-Object { ($_.NetworkInterfaces.Count -eq 0) -and ($_.subnets.Count -eq 0) }

#Get Orphaned Public IPs
Get-AzPublicIpAddress | Where-Object { $_.IpConfiguration -eq $null }

#Get Orphanic NetworkInterfaces
Get-AzNetworkInterface | Where-Object { ($_.PrivateEndpoint -eq $null) -and ($_.VirtualMachine -eq $null) }

#Get Orphaned Managed Disks
get-azdisk | Where-Object { $_.ManagedBy -eq $null }

https://docs.microsoft.com/en-us/azure/templates/microsoft.compute/2019-07-01/disks#CreationData


#Get Unmanaged disks
https://docs.microsoft.com/en-us/azure/virtual-machines/windows/find-unattached-disks


$storageAccounts = Get-AzStorageAccount
foreach ($storageAccount in $storageAccounts) {
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction silentlycontinue)[0].Value
    $context = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey
    $containers = Get-AzStorageContainer -Context $context -ErrorAction SilentlyContinue
    foreach ($container in $containers) {
        $blobs = Get-AzStorageBlob -Container $container.Name -Context $context
        #Fetch all the Page blobs with extension .vhd as only Page blobs can be attached as disk to Azure VMs
        $blobs | Where-Object { $_.BlobType -eq 'PageBlob' -and $_.Name.EndsWith('.vhd') } | ForEach-Object {
            $_.ICloudBlob.Uri.absoluteUri
        }
    }
}

#>


function Get-AzOrphanedResources {
    [CmdletBinding()]
    param (
        
    )
    process {
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

        function Set-AlternatingCSSClasses {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $True, ValueFromPipeline = $True)][string]$HTMLFragment,
                [Parameter(Mandatory = $True)][string]$CSSEvenClass,
                [Parameter(Mandatory = $True)][string]$CssOddClass
            )

            [xml]$xml = $HTMLFragment
            $table = $xml.SelectSingleNode('table')
            $classname = $CSSOddClass
            foreach ($tr in $table.tr) {
                if ($classname -eq $CSSEvenClass) {
                    $classname = $CssOddClass
                }
                else {
                    $classname = $CSSEvenClass
                }
                $class = $xml.CreateAttribute('class')
                $class.value = $classname
                $tr.attributes.append($class) | Out-null
            }
            $xml.innerxml | out-string
        }

        function Get-AzOrphangedNetworkSecurityGroups {
            [CmdLetBinding()]
            param ()

            process {
                $orphanedNSGs = Get-AzNetworkSecurityGroup | Where-Object { ($_.NetworkInterfaces.Count -eq 0) -and ($_.subnets.Count -eq 0) }
                
                foreach ($orphanedNSG in $orphanedNSGs) {
                    $nsgNname       = $orphanedNSG.Name
                    $nsgRgName      = $orphanedNSG.ResourceGroupName
                    $nsgLocation    = $orphanedNSG.Location
                    $nsgId          = $orphanedNSG.id
                    $nsgRuleCount   = $orphanedNSG.SecurityRules.Count
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

        function Get-AzOrphanedPublicIps {
            [CmdletBinding()]
            param ()
            
            process {
                $orphanedPIPs = Get-AzPublicIpAddress | Where-Object { $_.IpConfiguration -eq $null }

                foreach ($orphanedPIP in $orphanedPIPs) {

                    $pipName                = $orphanedPIP.Name
                    $pipRgName              = $orphanedPIP.ResourceGroupName
                    $pipLocation            = $orphanedPIP.Location
                    $pipSku                 = $orphanedPIP.Sku.Name
                    $pipAllocationMethod    = $orphanedPIP.PublicIpAllocationMethod
                    $pipId                  = $orphanedPIP.id
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

        function Get-AzOrphanedNICs {
            [CmdletBinding()]
            param()

            process { 
                $orphanicNICs = Get-AzNetworkInterface | Where-Object { ($_.PrivateEndpoint -eq $null) -and ($_.VirtualMachine -eq $null) }

                foreach ($orphanedNIC in $orphanicNICs) {

                    $nicName            = $orphanedNIC.Name
                    $nicRgName          = $orphanedNIC.ResourceGroupName
                    $nicLocation        = $orphanedNIC.Location
                    $nicIpConfigCount   = $orphanedNIC.IpConfigurations.Count
                    $nicId              = $orphanedNIC.id
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

        function Get-AzOrphanedUnmanagedDisks {
            [CmdletBinding()]
            param ()

            process {

                $storageAccounts = Get-AzStorageAccount
                foreach ($storageAccount in $storageAccounts) {
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

                foreach ($azSub in $azSubs) {
                    Write-Verbose "Getting information about $Azsub"
                    $subName = $azSub.Name
                    $subId = $azSub.SubscriptionID
                    $subTenantId = $azSub.TenantID
                    $subProps = [pscustomobject]@{
                        subName     = $subName
                        subID       = $subId
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

        $Date = (Get-Date).ToShortDateString().Replace("/", "-")

        $orphanedNICs = @()
        $orphanedPIPs = @()
        $orphanedNSGs = @()
        $orphanedMngDisks = @()
        $orphanedUnmngDisks = @()

        $AzTenats = Get-AzSubsFromTenant

        
        foreach ($AzSub in $AzTenats) {
            Set-AzContext -SubscriptionId $azSub.subId -TenantID $azsub.subTenantId
            $subOrphanedNICs = Get-AzOrphanedNICs
            $subOrphanedPIPs = Get-AzOrphanedPublicIps
            $subOrphanedNSGs = Get-AzOrphangedNetworkSecurityGroups
            $subOrphanedMngDisks = Get-AzOrphanedManagedDisks
            #$subOrphanedUnmngDisks = Get-AzOrphanedUnmanagedDisks

            $orphanedNICs += $subOrphanedNICs
            $orphanedPIPs += $subOrphanedPIPs
            $orphanedNSGs += $subOrphanedNSGs
            $orphanedMngDisks += $subOrphanedMngDisks
            #$orphanedUnMngDisks += $subOrphanedUnmngDisks
        }


        $orphanedPIPs | ConvertTo-Csv -NoTypeInformation | Out-File /tmp/orphaned-publicips-$date.csv

        $orphanedNSGs | ConvertTo-Csv -notypeInformation | Out-File /tmp/orphaned-nsgs-$date.csv

        $orphanedNICs | ConvertTo-Csv -notypeInformation | Out-File /tmp/orphaned-nics-$date.csv

        $orphanedMngDisks | ConvertTo-Csv -notypeInformation | Out-File /tmp/orphaned-mng-disks-$date.csv

        $orphanedUnmngDisks | ConvertTo-Csv -notypeInformation | Out-File /tmp/orphaned-unmng-disk-$date.csv

    }

}

Get-AzOrphanedResources

