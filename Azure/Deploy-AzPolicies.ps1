Function Deploy-AzPolicies {
    [CmdletBinding()]
    param(
    )
    PROCESS { 
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

        function Confirm-PSVersion {
            <#
    .SYNOPSIS
        This script will check to see if the running version of PowerShell is 5.1 or newer.   
    .DESCRIPTION
        This script does not install or make any changes.  It only checks to see if the version of PowerShell is 5.1 or newer 
    .INPUTS
        None
    .OUTPUTS
        It will output a boolean value.    If the version of PowerShell is 5.1 or newer, the value will be 'True'.  
        If it is not, then the value will be 'False'.  
    
    .NOTES
        Version:        1.0
        Author:         Joe Fecht - AHEAD, llc.
        Creation Date:  December 2019
        Purpose/Change: Initial deployment
    
    .EXAMPLE
        Confirm-PSVersion

        If the running version of PowerShell is 5.1 or newer the result will be below.  

        True
    #>
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

        function Get-PoliciesToDeploy { 
            [CmdletBinding()]
            Param(
                # Parameter help description
                [Parameter(
                    Mandatory = $false,
                    ValueFromPipeline = $true
                )]
                [String]
                $PathToPolicies
            )
            PROCESS { 
                $policies = @()
                Write-Verbose "Defining the current working path"
                $here = Split-Path -Parent $MyInvocation.MyCommand.Path
                Write-Output "Here is the `$here var - $here"

                Write-Verbose "Looking for folders in the working path"
                $childDirectories = Get-ChildItem -Path $here | Where-Object { $_.PSIsContainer -eq $true }
                
                foreach ($directory in $childDirectories) {
                    $directoryPath = $directory.FullName
                    Write-Verbose "Checking contents of $directoryPath for policies"
                    $files = Get-ChildItem -Path $directory -Filter *.json
                    foreach ($file in $files) {
                        Write-verbose "Checking to see if $file is a policy"
                        if ((Get-Content -Path $file) -contains "*policyRule:*") {
                            Write-Verbose "$File is a policy.  Adding to `$Policies"
                            $policies += $file
                        }
                        Else {
                            Write-Verbose "$File is not a policy"
                        }
                    }
                }
                return $policies
            }
        }

        function deploy
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
        $installedModules = Confirm-ModulesInstalled -modules Az.Accounts, Az.Resources, Az.PolicyInsights

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

        If ($installedModules.installed -contains $false) {
            Write-Verbose "There are PowerShell modules that need to be installed"
            Write-Host ""
            Write-Host "Existing script.  Please run the necessary commands listed in GREEN above to install the needed modules" -ForegroundColor Yellow
            exit
        }
        Else {
            Write-Verbose "Needed modules are installed.  Proceeding with script"
        }
    }
}