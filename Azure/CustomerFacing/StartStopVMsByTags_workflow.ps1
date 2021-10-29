# Workflow Stop-Start-AzureVM 
{ 
    Param 
    (    
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        [String]
        $TagName,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        [String]
        $TagValue,
        [Parameter(Mandatory=$true)][ValidateSet("Start","Stop")] 
        [String] 
        $Action
    ) 
     
    # Ensures you do not inherit an AzContext in your runbook
    Disable-AzContextAutosave -Scope Process 


    # Connect using a Managed Service Identity
    try {
        Connect-AzAccount -Identity -ErrorAction stop -WarningAction SilentlyContinue 
    }catch{
        Write-Output "There is no system-assigned user identity. Aborting."; 
        exit
    }

    $subs = Get-AzSubscription
    $overallList = @()

    foreach ($sub in $subs){
        $subName = $sub.Name
        Write-Output "Checking VMs on subscription $subName"
        $outNull = Set-AzContext -SubscriptionObject $sub
        $azureVms = $null
        $AzureVMs = Get-AzResource -TagName $TagName -TagValue $TagValue -ResourceType Microsoft.Compute/virtualMachines
    
        if($Action -eq "Stop") 
        { 
            foreach -parallel ($AzureVM in $AzureVMs) 
            { 
                $vmName = $AzureVM.name

                try{
                    Write-Output "Stopping $vmName"
                    $outNullInside = Get-AzVM | Where-Object {$_.Id -eq $AzureVM.ResourceId} | Stop-AzVM -Force
                    $WORKFLOW:overallList += $vmName
                }catch{
                    Write-Output "Error powering off vm - $vmName"
                }
            } 
        } 
        elseif($Action -eq "Start") 
        { 
            foreach -parallel ($AzureVM in $AzureVMs) 
            { 
                $vmName = $AzureVM.name
                try{
                    Write-Output "Starting $vmName"
                    $outNullInside = Get-AzVM | Where-Object {$_.Id -eq $AzureVM.ResourceId} | Start-AzVM
                    $WORKFLOW:overallList += $vmName
                }catch{
                    Write-Output "Error powering on vm - $vmName"
                }
            } 
        } 
    }

    Write-Output "The following VMs had the `"$action`" action performed"
    Write-Output $overallList
}