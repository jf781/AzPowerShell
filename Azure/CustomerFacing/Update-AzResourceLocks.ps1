function Update-AzVnetNSGResourceLocks {
  
    <#

  .SYNOPSIS
  This funtion will help you document and create resource locks in place for Virtual Networks and Network security groups.


  .DESCRIPTION
  If you run the script with only specifying the required parameter, "OutputPath", it will document the current resource locks for all Vnets and NSGs in scope. 

  You can have it create a resource lock across all Vnets and NSG by populating the "LockName", "LockType", and "CreateLock" parameters. 

  .PARAMETER OutputPath
  This is the path to save the output CSV file.  It will validate the path before attempt to run the command

  .PARAMETER LockName
  If you are create a resource lock this is the name of the lock

  .PARAMETER LockType
  This is the type of Resource Lock.  It will only accept values of "ReadOnly" and "CanNotDelete".
  It defaults to "null" when documenting existing locks

  .PARAMETER CreateLock
  This is a boolean value to determine if you want to create locks.  It defaults to "False"

  .EXAMPLE
  Update-AzVnetNSGResourceLocks -OutputPath ~/Desktop
  
  This will document all existing resource locks and save the output as a CSV file to the current users Desktop

  .EXAMPLE
  Update-AzVnetNSGResourceLocks -LockName "SampleDeleteLockName"  -LockType "DoNotDelte" -CreateLock $True -OutputPath ~/Desktop

  This will create a lock for all NSG and VNets that will prevent them from being deleted.  The lock will be named "SampleDeleteLockName"
  It will output the value of all existing and new locks to the desktop of the current user.

  Any locks on the Vnet and NSGs that had a lock type of "DoNotDelete" will be removed so there is only the one lock with a level of "DoNotDelete".  Locks with a level of "ReadOnly" will not be modified

  .LINK
  https://www.thinkahead.com

  #>

  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $false)]
    [string]
    $LockName = "null",
    [Parameter(Mandatory = $false)]
    [ValidateSet('CanNotDelete','ReadOnly', 'null')]
    [string]
    $LockType = "null",
    [Parameter(Mandatory = $false)]
    [bool]
    $CreateLock = $false,
    [Parameter(Mandatory = $true)]
    [string]
    $OutputPath
  )

  process{

    #------------------------------------------------------
    # Define Utility Functions
    #------------------------------------------------------
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

    Function Get-AzLocks {
      [CmdletBinding()]
      param (
        [Parameter(mandatory = $true
        )]
        [bool]
        $CreateLock,
        [Parameter(mandatory = $false
        )]
        [string]
        $LockType = "null",
        [Parameter(mandatory = $false
        )]
        [string]
        $LockName = "null",
        [Parameter(mandatory = $true
        )]
        [string]
        $resourceName,
        [Parameter(mandatory = $true
        )]
        [string]
        $ResourceGroupName,
        [Parameter(mandatory = $true
        )]
        [string]
        $ResourceType
      )
      process {
        try{
          Write-Verbose "Checking Locks on Name: $ResourceName, RG: $ResourceGroupName, Type: $ResourceType"
          $lock = Get-AzResourceLock -ResourceName $ResourceName -resourceGroupName $ResourceGroupName -ResourceType $ResourceType -ErrorAction SilentlyContinue
          if (($lock.Properties.level -eq $LockType) -and ($lock.Name -eq $LockName)) {
            Write-Verbose "Found lock for $resourceName"
          }
          else {
            Write-Verbose "In Else. Lock with existing name not found"
            if ($CreateLock) {
              Write-Verbose "In If statement.  Setting resource lock"
              if ($lock.Properties.level -eq $LockType) {
                Write-Verbose "Removing existing locks that has the same lock level as we are trying to set for $ResourceName."
                $oldLocks = $lock | Where-Object {$_.properties.level -eq $LockType}
                foreach($oldLock in $oldLocks){
                  $oldLockName = $oldLock.Name
                  Write-Verbose "Removing lock $oldLockName from $ResourceName"
                  Remove-AzResourceLock -Name "$oldLockName" -ResourceName $ResourceName -ResourceGroupName $ResourceGroupName -ResourceType $ResourceType -Force
                }
              }
              else {
                Write-Verbose "There is not an existing lock type that has the same lock level that is being created"
              }
              Write-Host "Setting Lock $LockName on $ResourceName, ResourceType = $ResourceType" -ForegroundColor Green
              $lock = Set-AzResourceLock -LockName $LockName -LockLevel $LockType -ResourceName $ResourceName -ResourceGroupName $ResourceGroupName -ResourceType $ResourceType -Force
            }else{
              write-Verbose "In Else.  CreateLock set to false"
            }
          }
          return $lock
        }
        catch{                    
          Write-Verbose "Error getting lock on $ResourceName."
          Write-Host "Error getting lock on $ResourceName."
          Write-Verbose "Error Msg: $_"
          break
        }
      }
    }

    function Confirm-OutputPath {

      [CmdletBinding()]
      Param(
        [Parameter(
          Mandatory = $true)]
        [string]
        $outputPath
      )

      process {
        # Confirm output path is valid
        try{
          if(Test-Path $outputPath){
            Write-Verbose "Output path is valid"
          }else{
            write-verbose "Output path is invalid"
            Write-Host "Output Path is not valid" -ForegroundColor red
            Write-Host "Output Path set to: $outputPath" -ForegroundColor Red
            Write-Host "Please run execute command again with a valid output path"
            return "invalidPath"
          }          
        }catch{
          Write-Verbose "Failed to validate Output Path"
          Write-Host "Unable to validate Output Path: $outputPath" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }

        # Ensure output path has a trailing path separator
        try{
          if($env:HOME){
            Write-Verbose "Running in a non-windows environment.  Path seperator is '/'"
            if($outputPath.endsWith("/")){
              Write-Verbose "Output path ends with a trailing path separator"
              return $outputPath
            }else{
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $outputPath + "/"
              return $updatedOutputPath
            }
          }else{
            Write-Verbose "Running in a Windows environment.  Path seperator is '\'"
            if($outputPath.endsWith("\")){
              Write-Verbose "Output path ends with a trailing path separator"
              return $outputPath
            }else{
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $outputPath + "\"
              return $updatedOutputPath
            }
          }
        }catch{
          Write-Verbose "Failed to determine if the output path had a trailing path seperator"
          Write-Host "Unable to validate trailing path seperator for Output Path: $outputPath" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }
      }
    }

    #------------------------------------------------------
    # Main Function
    #------------------------------------------------------

    Write-Verbose "Defining base variables"
    $date = ((Get-Date).ToShortDateString()).replace("/","-")
    $output = @()


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
        return
    }

    Write-Verbose "Validating Output Path"
    $lockOutputPath = Confirm-OutputPath -outputPath $outputPath 
    

    if ($lockOutputPath -ne "invalidPath") {
      Write-Verbose "Output path is valid"

      try{
        $nsgs = Get-AzNetworkSecurityGroup
        foreach ($nsg in $nsgs){
          $nsgOutput = Get-AzLocks -ResourceName $nsg.Name -ResourceGroupName $nsg.ResourceGroupName -LockType $LockType -LockName $LockName -CreateLock $CreateLock -ResourceType "Microsoft.Network/networkSecurityGroups"
          $output += $nsgOutput
        }
      }catch{
        Write-Verbose "Error checking NSG Locks."
        Write-Host "Error checking NSG Locks."
        Write-Verbose "Error Msg: $_"
        break
      }

      try{
        $vnets = Get-AzVirtualNetwork
        foreach ($vnet in $vnets) {
          $vnetOutput = Get-AzLocks -ResourceName $vnet.Name -ResourceGroupName $vnet.ResourceGroupName -LockType $LockType -LockName $LockName -CreateLock $CreateLock -ResourceType "Microsoft.Network/virtualNetworks"
          $output += $vnetOutput
        }
      }catch{
        Write-Verbose "Error checking Vnet Locks."
        Write-Host "Error checking Vnet Locks."
        Write-Verbose "Error Msg: $_"
        break
      }

      try {
        $path = $lockOutputPath + "Existing-Vnet-NSG-Locks-" + $date + ".csv"
        $output | ConvertTo-Csv -NoTypeInformation | Out-File -path $path
      }catch {
        Write-Verbose "Error writting output."
        Write-Host "Error writting output."
        Write-Verbose "Error Msg: $_"
        break
      }

    }else{
      Write-Verbose "Output path invalid.  Exiting"
    }
  }
}