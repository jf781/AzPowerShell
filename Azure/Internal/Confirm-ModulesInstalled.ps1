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

# Example
# Confirm-ModulesInstalled -modules Az.Accounts,Az.Resources