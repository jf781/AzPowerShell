function Update-VMDataDiskType{
  [CmdletBinding()]
  param (
      [string] $resourceGroupName,
      [string] $vmName,
      [string] $newDiskType,
      [number] $logicalSectorSize=512
  )

  process {
    function Get-VMDataDisks ($resourceGroupName, $vmName) {
        $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
        $vm.StorageProfile.DataDisks
    }


    $dataDisks = Get-VMDataDisks -resourceGroupName $resourceGroupName -vmName $vmName

    foreach ($disk in $dataDisks) {
        # Create snapshot
        $snapshotName = $disk.Name + "-snapshot"
        $snapshotConfig=New-AzSnapshotConfig -SourceUri $disk.Id -Location $disk.Location -CreateOption Copy -Incremental 
        $snapshot = New-AzSnapshot -ResourceGroupName $resourceGroupName -SnapshotName $snapshotName -Snapshot $snapshotConfig

        # Create new disk using new disk SKU
        $diskName = $disk.Name + "v2"
        $diskConfig = New-AzDiskConfig -SkuName $newDiskType -Location $disk.location -CreateOption Copy -SourceResourceId $snapshot.Id -DiskSizeGB $disk.DiskSizeGb -LogicalSectorSize $logicalSectorSize -Zone $disk.Zone
        New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $diskName

    }
  }
}