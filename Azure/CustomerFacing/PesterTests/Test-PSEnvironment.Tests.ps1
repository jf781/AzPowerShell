

Describe 'PowerShell Version and modules' { 
    it 'PowerShell v5.1 or later is installed' { 
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
            Write-Verbose "PS Version is 4 or later"
            $compatible = $false
        }
        $compatible | Should -BeTrue
    }

    $modules = @{module = "Az.Accounts" }, @{module = "Az.Resources" }
    
    it 'The module <module> is installed' -TestCases $modules { 
        param($module)

        Get-Module -Name $module | Should -not -BeNullOrEmpty
    }
}

