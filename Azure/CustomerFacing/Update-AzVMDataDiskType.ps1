function Update-AzVMDataDiskType {
    <#
    .SYNOPSIS
        Updates the disk type of data disks attached to a specified Azure virtual machine.

    .DESCRIPTION
        The `Update-AzVMDataDiskType` function automates the process of updating the disk type for all data disks attached to a given Azure VM.
        
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

    .PARAMETER SourceDiskLun
        Specifies the LUN (Logical Unit Number) of the source disk to be updated. If not specified, all data disks will be updated.
        Type: Int
        Required: False

    .PARAMETER TargetDiskIOPS
        Specifies the target IOPS for the new disk.
        Type: Int
        Required: False

    .PARAMETER TargetDiskThroughput
        Specifies the target throughput (MBps) for the new disk.
        Type: Int
        Required: False

    .EXAMPLE
        PS C:\> Update-AzVMDataDiskType -ResourceGroupName "MyResourceGroup" -VMName "MyVM" -NewDiskType "PremiumV2_LRS"

        This command updates all data disks of the virtual machine 'MyVM' in the resource group 'MyResourceGroup' to use the 'PremiumV2_LRS' disk type.
    
    .EXAMPLE
        PS C:\> Update-AzVMDataDiskType -ResourceGroupName "MyResourceGroup" -VMName "MyVM" -NewDiskType "UltraSSD_LRS" -SourceDiskLun 1 -TargetDiskIOPS 5000 -TargetDiskThroughput 200

        This command updates the data disk with LUN 1 of the virtual machine 'MyVM' in the resource group 'MyResourceGroup' to use the 'UltraSSD_LRS' disk type with a target of 5000 IOPS and 200 MBps throughput.

    .NOTES
        Author: AHEAD
        Version: 1.1
        Date: 5/29/2024
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
        $logicalSectorSize=512,
        [Parameter(Mandatory=$false)]
        [int]
        $sourceDiskLun,
        [Parameter(Mandatory=$false)]
        [int]
        $targetDiskIOPS=0,
        [Parameter(Mandatory=$false)]
        [int]
        $targetDiskThroughput=0
    )
  
    process {
        $ErrorActionPreference = "Stop"

        function Update-VMDataDisk ($resourceGroupName,$dataDisk,$vm,$newDiskType,$logicalSectorSize,$targetDiskIOPS,$targetDiskThroughput) {
            # Get Disk Details
            try {
                $disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $dataDisk.Name
            } catch {
                Write-Error "Failed to get disk details. $_"
            }
            
            # Define Disk Specific Variables
            $snapshotName = $disk.Name + "-snapshot"
            $diskName = $disk.Name + "v2"
            if ($targetDiskIOPS -eq 0) {
                $diskIOPS = $disk.DiskIOPSReadWrite
            } else {
                $diskIOPS = $targetDiskIOPS
            }

            if ($targetDiskThroughput -eq 0) {
                $diskThroughput = $disk.DiskMBpsReadWrite
            } else {
                $diskThroughput = $targetDiskThroughput
            }
        
        
            # Create snapshot
            try {
                $snapshotConfig=New-AzSnapshotConfig -SourceUri $disk.Id -Location $vm.Location -CreateOption Copy -Incremental 
                $snapshot = New-AzSnapshot -ResourceGroupName $resourceGroupName -SnapshotName $snapshotName -Snapshot $snapshotConfig
            } catch {
                Write-Error "Failed to create snapshot. $_"
            }
        
            # Create new disk using new disk SKU
            try {
                if ($diskThroughput -lt 125) {
                    $diskThroughput = 125
                }
                if ($diskIOPS -lt 3000) {
                    $diskIOPS = 3000
                }
                $diskConfig = New-AzDiskConfig -SkuName $newDiskType -Location $disk.location -CreateOption Copy -SourceResourceId $snapshot.Id -DiskSizeGB $disk.DiskSizeGb -LogicalSectorSize $logicalSectorSize -Zone $disk.Zones -DiskIOPSReadWrite $diskIOPS -DiskMBpsReadWrite $diskThroughput
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

        try {
            $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
            Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vm.Name -Force
            $dataDisks = $vm.StorageProfile.DataDisks
        } catch {
            Write-Error "Failed to get VM details. $_"
        }

        if($sourceDiskLun -eq ""){

            foreach ($dataDisk in $dataDisks) {
                try {
                    Update-VMDataDisk `
                    -resourceGroupName $resourceGroupName `
                    -dataDisk $dataDisk `
                    -vm $vm `
                    -newDiskType $newDiskType `
                    -logicalSectorSize $logicalSectorSize `
                    -targetDiskIOPS $targetDiskIOPS `
                    -targetDiskThroughput $targetDiskThroughput
                } catch {
                    Write-Error "Failed to update disk type. $_"
                }
            }
        } else {
            foreach ($dataDisk in $dataDisks) {
                if ($dataDisk.Lun -eq $sourceDiskLun) {
                    try {

                        Update-VMDataDisk `
                        -resourceGroupName $resourceGroupName `
                        -dataDisk $dataDisk `
                        -vm $vm `
                        -newDiskType $newDiskType `
                        -logicalSectorSize $logicalSectorSize `
                        -targetDiskIOPS $targetDiskIOPS `
                        -targetDiskThroughput $targetDiskThroughput
                    } catch {
                        Write-Error "Failed to update disk type. $_"
                    }
                }
            }
        }
    }
}