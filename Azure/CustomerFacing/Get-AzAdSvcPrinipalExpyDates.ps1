

function Get-AzAdAppCredentialsWithExpirationDates {
    <#
    .SYNOPSIS
        This script is will review service prinipals within an existing RBAC report that is based off Excel.  It will determine if the app registration
        associated with the service principal has valid credentials or not.  It will then create a new worksheet in the Excel file with the 
        app registration information

    .DESCRIPTION
        This script does not install or make any changes.   It does have the following requirements that if not met, will stop the script from running
        - Running in PowerShell 5.1 or newer context
        - The following modules need to be installed
            - Az.*
            - ImportExcel

    .PARAMETER ExcelPath
        This is the path to the existing Excel File with the RBAC report.

    .PARAMETER WorksheetName
    This is the name of the worksheet name in the existing Excel File with the RBAC report.

    .OUTPUTS
        This will add a new worksheet to the excel named "ServicePrinicpals"

    .NOTES
        Version:        1.0
        Author:         Joe Fecht - AHEAD, llc.
        Creation Date:  July 2022
        Purpose/Change: Initial deployment

        Next steps to add:
        1. Validate current Azure AD context

    .EXAMPLE
        Get-AzAdAppCredentialsWithExpirationDates -ExcelPath ~/Desktop/rbac-report.xlsx -WorksheetName RBAC
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [string]
        $excelPath,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [string]
        $WorksheetName
    )
    process {

        #----------------------------------------------------------------------------------------
        # Confirm PS Version and Az module is installed
        #----------------------------------------------------------------------------------------
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

        #----------------------------------------------------------------------------------------
        # Confirm Path
        #----------------------------------------------------------------------------------------

        function Get-AzADServicePrincipals {
            [CmdLetBinding()]
            param (
                [Parameter(
                    Mandatory = $true,
                    ValueFromPipeline = $true
                )]
                [object[]]
                $excelData,
                [Parameter(
                    Mandatory = $true,
                    ValueFromPipeline = $true
                )]
                [DateTime]
                $date
            )
            PROCESS {
                $svcPrincipals = $excelData | Where-Object {$_.principalType -eq "ServicePrincipal"}

                foreach ($prinicpal in $svcPrincipals){
                    $creds = $null
                    $svc = Get-AzADServicePrincipal -ObjectId $prinicpal.PrincipalId
                    $creds = Get-AzADAppCredential -ApplicationId $svc.AppId

                    if($creds){
                        $expiredCreds = $true
                        foreach ($cred in $creds){
                            
                            if($cred.EndDateTime -ge $date){
                                Write-Verbose "Creds are valid"
                                $expiredCreds = $false
                            }else{
                                Write-Verbose "Creds are expired"
                            }    
                        }

                        $newestCred = $creds | Sort-Object EndDateTime | Select-Object -Last 1

                        $props = [ordered]@{
                            ServicePrincipalName            = $svc.DisplayName 
                            SerivcePrinipalObjectId         = $svc.Id
                            ServicePrincipalAppId           = $svc.AppId
                            CredentialsExpired              = $expiredCreds
                            NewestCredName                  = $newestCred.DisplayName
                            NewestCredExpirationDate        = $newestCred.EndDateTime
                        }
                            
                        New-Object -TypeName psobject -Property $props

                    }
                }
            }
        }

        #----------------------------------------------------------------------------------------
        # Main Function
        #----------------------------------------------------------------------------------------

        #Validate necessary modules are installed
        Write-Verbose "Ensuring the proper PowerShell Modules are installed"
        $installedModules = Confirm-ModulesInstalled -modules az,  ImportExcel
        $modulesNeeded = $False

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
                $modulesNeeded = $true
            }
        }

        If ($modulesNeeded) {
            Write-Host "Please install the modules listed above and then run the script again" -ForegroundColor Yellow
            Exit
        }

        # Defining all variables
        $date = Get-Date
        $apps = @()

        If (Test-Path -Path $excelPath){
            $excelData = Import-Excel -Path $excelPath -WorksheetName $WorksheetName
            $apps = Get-AzADServicePrincipals -excelData $excelData -date $date
        }

        #Outputing Excel File to current users desktop
        $apps | Export-Excel -Path $excelPath -WorksheetName "ServicePrinicpals"

    }

}