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