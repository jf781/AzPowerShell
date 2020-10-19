function Confirm-ModulesInstalled {
    <#
    .SYNOPSIS
        This script will check to see if the modules supplied via the $modules parameter are installed on the system.  It will provide an out of all modules and if they are installed.  
    .DESCRIPTION
        This script does not install or make any changes.  It only checks to see if the modules are installed. 
    .PARAMETER Modules
            Please provide one or more modules that you wish to check if installed.  If there are multiples please seperate by a comma
    .INPUTS
        Requires the $module parameter to be populated with one or more items
    .OUTPUTS
        Outputs a list two columns.  ModuleName and Installed.  ModuleName will display the name of the module and Installed will display True or False depending if that module is installed on the system
    
    .NOTES
        Version:        1.0
        Author:         Joe Fecht - AHEAD, llc.
        Creation Date:  December 2019
        Purpose/Change: Initial deployment
    
    .EXAMPLE
        Confirm-ModulesInstalled -modules az.resources,az.accounts

        Checks for the modules Az.Resources and Az.Accounts
        Ouput shows the Az.Resources module is not installed but Az.Accounts is installed on the system. 

        ModuleName   Installed
        ----------   ---------
        az.accounts       True
        az.resources     False
    #>
    [CmdLetBinding()]
    param (
        [Parameter(
            Mandatory = $true,
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