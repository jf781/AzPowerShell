$csv = import-csv -Path /Users/joe.fecht/Desktop/junk-folder/ss-vm-prod.csv

foreach ($vm in $csv){
    $vmName = $vm.Vmname
    $extension = $vm.ExtentsionName
    $vmStatus = get-azvm -Name $vmName -ResourceGroupName $vm.RGName -Status | select -expand statuses | ?{$_.code -eq "PowerState/running"} | select -expand DisplayStatus
    if ($vmStatus -eq "VM running"){
        
        Write-Host "Removing $extension from $vmName" -ForegroundColor Green
        Remove-AzVMExtension -vmname $vmName -ResourceGroupName $vm.RGName -Name $extension -Force
    }else{
        Write-Host "$vmName is powered off" -ForegroundColor Yellow
    }
}




$vmName = "az-p-1052"
$vmRgName = "CoreAdmin"

# Declare variables
$CustomScriptFileName = "Qualsys.ps1"
$extensionName = "QualysAgent"
$ContainerName = "cse"
$StorageAccountName = "terraformprodsa"
$StorageAccountRgName = "TerraformProdRg"
$ScriptArguments = "-customerid 927e229b-49d9-6b4b-810b-f4eab40b9151 -activationId 775f0992-758d-49b8-9a42-5493b667c98e"
$CommandToExecute = "$CustomScriptFileName $ScriptArguments"

# Get storage account context
$StorageAccount = Get-AzStorageAccount -name $StorageAccountName -ResourceGroupName $StorageAccountRgName

# Retrieve storage account key
$StorageAccountKey = (Get-AzStorageAccountKey `
    -ResourceGroupName $StorageAccountRgName `
    -Name $StorageAccountName).Value[0]


Foreach ($vm in $vms){

    $vmName = $vm.Name
    $vmRgName = $vm.resourceGroupName
    $vmStatus = get-azvm -Name $vmName -ResourceGroupName $vmRgName -Status | 
        Select-Object -expand statuses | 
        ?{$_.code -eq "PowerState/running"} | 
        Select-Object -expand DisplayStatus
    
    if($vmStatus -eq "VM running"){

        $existingCSE = Get-AzVMExtension -VMName $vmName -ResourceGroupName $vmRgName | ?{$_.ExtensionType -eq "CustomScriptExtension"}
        
        if($existingCSE){

            Write-Host "Removing existing custom script extension from $vmName" -ForegroundColor Yellow
            
            Remove-azvmextension `
            -VMName $vmName `
            -ResourceGroupName $vmRgName `
            -Name $existingCSE.Name
        }
        
        
        
        Write-host "Install Qualys agent on $vmName" -ForegroundColor Green

        # Add custom script extension to Windows VM
        Set-AzVMCustomScriptExtension `
        -ContainerName $ContainerName `
        -FileName $CustomScriptFileName `
        -Location $vm.Location `
        -Name $extensionName `
        -VMName $VMName `
        -ResourceGroupName $vmRgName `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey $StorageAccountKey `
        -Run $CommandToExecute `
        -SecureExecution
    }else{
        Write-Host "$vmName is powered off" -ForegroundColor Yellow
    }
}