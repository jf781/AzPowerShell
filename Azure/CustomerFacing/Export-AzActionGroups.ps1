function Export-AzActionGroups {
  [CmdletBinding()]
  param (
    [Parameter(
        Mandatory = $true
    )]
    [string]
    $outputPath
  )

  process{
    # ----------------------------------------------------------------------------------------
    # Utility Functions
    # ----------------------------------------------------------------------------------------

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

    Function Get-AzSubsFromTenant {
      [CmdletBinding()]
      param (
      )
      PROCESS {
        Write-Verbose "Testing to see if connected to Azure"
        $Context = Get-AzContext
        try {
          if ($Context) {
            Write-Verbose "Connected to Azure"
          }
          Else {
            Write-Verbose "Need to connect to Azure"
            Write-Host "Connecting to Azure.  Please check for a browser window asking for you to login" -ForegroundColor Yellow
            $null = Login-AzAccount -ErrorAction Stop
          }
        }
        catch {
          Write-Verbose "Error validating connection to Azure."
          Write-Host "Error validating connection to Azure" -ForegroundColor Red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          break
        }

        Write-Verbose "Getting list of Azure Subscriptions"
        $azSubs = Get-AzSubscription
        $tenantProps = @()

        foreach ($azSub in $azSubs) {
          Write-Verbose "Getting information about $Azsub"
          $subName = $azSub.Name
          $subId = $azSub.SubscriptionID
          $subTenantId = $azSub.TenantID
          $subProps = [pscustomobject]@{
            subName     = $subName
            subID       = $subId
            subTenantId = $subTenantId
          }
          $tenantProps += $subProps
        }
        return $tenantProps
      }
    }

    function Export-AzSubActionGroups {

      [CmdletBinding()]
      Param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true,
          ValueFromPipelineByPropertyName = $true)]
        [string]
        $subscriptionID,
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true,
          ValueFromRemainingArguments = $true
        )]
        [string]
        $tenantID,
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true,
          ValueFromRemainingArguments = $true
        )]
        [string]
        $outputPath
      )

      process {
        Write-Verbose "Attempting to connect to the subscription with SubID = $subscriptionID"
        try { 
          $azSub = Set-AzContext -SubscriptionId $subscriptionID -TenantId $tenantId -ErrorAction Stop
          Write-Verbose "Successfully connected to $azSubName"
        }
        Catch {
          Write-Verbose "Failed to connect to subscription with SudID = $subscriptionID, TenantID = $tenantID"
          Write-Host "Unable to Connect to SubscriptionID $subscriptionID" -ForegroundColor red 
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }

        # Determine the Subscription Name
        $subName = ((((Get-AzContext).Subscription.Name).Replace(" ", "-")).Replace("/", "-")).Replace("\", "-")

        # Get a list of action groups
        try {
          $actionGroups = Get-AzResource -ResourceType "microsoft.insights/actiongroups"
        }
        catch {
          Write-Verbose "Error getting actions groups for $subName"
          Write-Host "Error getting action groups" -ForegroundColor Red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }

        Write-host "Getting action groups for subscription: $subName" -ForegroundColor green

        foreach ($ag in $actionGroups) {
          try {
            $agFormattedName = ($ag.Name).replace(" ", "-")
            $agPath = $outputPath + $subName + "__" + $ag.ResourceGroupName + "__" + $agFormattedName + ".json"
            Export-AzResourceGroup -ResourceGroupName $ag.resourceGroupName -Resource $ag.ResourceId -Path $agPath
          }
          catch {
            Write-Verbose "Error exporting $agFormattedName"
            Write-Host "Error exporting action group $agFormattedName" -ForegroundColor Red
            Write-Host "Error Msg: $_" -ForegroundColor Red
            return
          }
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
        try {
          if (Test-Path $outputPath) {
            Write-Verbose "Output path is valid"
          }
          else {
            write-verbose "Output path is invalid"
            Write-Host "Output Path is not valid" -ForegroundColor red
            Write-Host "Output Path set to: $outputPath" -ForegroundColor Red
            Write-Host "Please run execute command again with a valid output path"
            return "invalidPath"
          }          
        }
        catch {
          Write-Verbose "Failed to validate Output Path"
          Write-Host "Unable to validate Output Path: $outputPath" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          break
        }

        # Ensure output path has a trailing path separator
        try {
          if ($env:HOME) {
            Write-Verbose "Running in a non-windows environment.  Path seperator is '/'"
            if ($outputPath.endsWith("/")) {
              Write-Verbose "Output path ends with a trailing path separator"
              return $outputPath
            }
            else {
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $outputPath + "/"
              return $updatedOutputPath
            }
          }
          else {
            Write-Verbose "Running in a Windows environment.  Path seperator is '\'"
            if ($outputPath.endsWith("\")) {
              Write-Verbose "Output path ends with a trailing path separator"
              return $outputPath
            }
            else {
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $outputPath + "\"
              return $updatedOutputPath
            }
          }
        }
        catch {
          Write-Verbose "Failed to determine if the output path had a trailing path seperator"
          Write-Host "Unable to validate trailing path seperator for Output Path: $outputPath" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }
      }
    }

    # ----------------------------------------------------------------------------------------
    # Main Function
    # ----------------------------------------------------------------------------------------

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

    Write-Verbose "Validating Output Path"
    $agOutputPath = Confirm-OutputPath -outputPath $outputPath 

    if($agOutputPath -ne "invalidPath"){
      Write-Verbose "Output path is valid"

      Write-Verbose "Getting subs associated with Tenant"
      $tenantSubs = Get-AzSubsFromTenant

      Write-verbose "Getting action groups for each subscription"
      foreach ($tenantSub in $tenantSubs) {
        Export-AzSubActionGroups -subscriptionID $tenantSub.subID -tenantID $tenantSub.subTenantId -outputPath $agOutputPath
      }
    }else{
      Write-Verbose "Output path invalid.  Exiting"
    }
  }
}
