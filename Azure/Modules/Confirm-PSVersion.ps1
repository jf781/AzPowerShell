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