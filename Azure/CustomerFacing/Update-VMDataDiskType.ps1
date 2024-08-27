function Update-VMDataDiskType {
    <#
    .SYNOPSIS
        Updates the disk type of data disks attached to a specified Azure virtual machine.

    .DESCRIPTION
        The `Update-VMDataDiskType` function automates the process of updating the disk type for all data disks attached to a given Azure VM.
        
        It includes stopping the VM, creating snapshots of the existing disks, creating new disks with the specified type, and replacing the old disks with the newly created ones.
        
        This function is useful for scenarios where disk performance or cost optimization is needed and can't be done in the portal (e.g., from Premium SSD to Premium SSD v2).

    .PARAMETER ResourceGroupName
        Specifies the name of the resource group that contains the VM.
        Type: String
        Required: True

    .PARAMETER VMName
        Specifies the name of the virtual machine whose disks are being updated.
        Type: String
        Required: True

    .PARAMETER NewDiskType
        Specifies the new disk type to which the data disks should be converted. Supports standard disk types available in Azure.
        Type: String
        Required: True
        Valid Values: 'PremiumV2_LRS', 'UltraSSD_LRS'

    .PARAMETER LogicalSectorSize
        Specifies the logical sector size of the new disk in bytes. Default is 512 bytes.
        Type: Int
        Required: False
        Defaults to: 512
        Valid Values: 512, 4096

    .EXAMPLE
        PS C:\> Update-VMDataDiskType -ResourceGroupName "MyResourceGroup" -VMName "MyVM" -NewDiskType "PremiumV2_LRS"

        This command updates all data disks of the virtual machine 'MyVM' in the resource group 'MyResourceGroup' to use the 'PremiumV2_LRS' disk type.

    .NOTES
        Author: AHEAD
        Version: 1.0
        Date: 5/4/2024
    #>

    [CmdletBinding()]
     
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $resourceGroupName,
        [Parameter(Mandatory=$true)]
        [string]
        $vmName,
        [Parameter(Mandatory=$true)]
        [string]
        [ValidateSet('PremiumV2_LRS','UltraSSD_LRS')]
        $newDiskType,
        [Parameter(Mandatory=$false)]
        [int]
        [ValidateSet('512','4096')]
        $logicalSectorSize=512
    )
  
    process {
        $ErrorActionPreference = "Stop"

        try {
            $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
            Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vm.Name -Force
            $dataDisks = $vm.StorageProfile.DataDisks
        } catch {
            Write-Error "Failed to get VM details. $_"
        }

        foreach ($dataDisk in $dataDisks) {
            # Get Disk Details
            try {
                $disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $dataDisk.Name
            } catch {
                Write-Error "Failed to get disk details. $_"
            }
            
            # Define Disk Specific Variables
            $snapshotName = $disk.Name + "-snapshot"
            $diskName = $disk.Name + "v2"


            # Create snapshot
            try {
                $snapshotConfig=New-AzSnapshotConfig -SourceUri $disk.Id -Location $vm.Location -CreateOption Copy -Incremental 
                $snapshot = New-AzSnapshot -ResourceGroupName $resourceGroupName -SnapshotName $snapshotName -Snapshot $snapshotConfig
            } catch {
                Write-Error "Failed to create snapshot. $_"
            }

            # Create new disk using new disk SKU
            try {
                $diskConfig = New-AzDiskConfig -SkuName $newDiskType -Location $disk.location -CreateOption Copy -SourceResourceId $snapshot.Id -DiskSizeGB $disk.DiskSizeGb -LogicalSectorSize $logicalSectorSize -Zone $disk.Zones
                $newDisk = New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $diskName
            } catch {
                Write-Error "Failed to create new disk. $_"
            }

            # Remove existing disk from VM
            try {
                Remove-AzVMDataDisk -vm $vm -DataDiskNames $disk.Name
                Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm
            } catch {
                Write-Error "Failed to remove existing disk from VM. $_"
            }

            # Attach the new disk to the VM
            try {
                Add-AzVMDataDisk -VM $vm -Name $diskName -CreateOption Attach -ManagedDiskId $newDisk.Id -Lun $dataDisk.Lun
                Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm
            } catch {
                Write-Error "Failed to attach new disk to VM. $_"
            }
        }
    }
}
