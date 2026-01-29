function Get-AzOperationalInsightsOverview {
  <#
  .SYNOPSIS
      This script is designed to export the policy assignments to an Excel file

  .DESCRIPTION
      This script does not install or make any changes.   It does have the following requirements that if not met, will stop the script from running
      - Running in PowerShell 5.1 or newer context
      - The following modules need to be installed
          - Az
          - ImportExcel
      
  .INPUTS
      No input is needed to run the script.  If you are not connected to Azure it will prompt you to login. 

  .OUTPUTS
      

  .NOTES
      Version:        1.0
      Author:         Joe Fecht - AHEAD, llc.
      Creation Date:  November 2022
      Purpose/Change: Initial deployment
  
  .EXAMPLE
      Get-AzPolicyAssignmentDetails
  #>
  [CmdletBinding()]
  param (
      
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
      # Module to get the Policy Assignment Details
      #----------------------------------------------------------------------------------------
      
      function Get-AzOperationalInsightsWorkspaceUsageDetails ($largeLawsThresholdSize) {
    
        # Get a list of all Log Analytics workspaces in the current subscription
        try {
            $workspaces = Get-AzOperationalInsightsWorkspace
        } catch {
            Write-Host "Error getting Log Analytics workspaces: $_" -ForegroundColor Red
            return
        }

        # Loop through each workspace to gather details
        foreach ($workspace in $workspaces) {
            # Get the total usage data (ingested volume in GB)
            $totalUsageQuery = @"
                Usage
                | where TimeGenerated > ago(30d)
                | where IsBillable == true
                | summarize TotalBillableUsageGB = sum(Quantity) / (1024)
                | project TotalBillableUsageGB
"@
            try {
              $ingestResult = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $totalUsageQuery
            } catch {
              Write-Host "Error querying workspace $($workspace.Name): $_" -ForegroundColor Red
              continue
            }
            $thirtyDayIngestVolumeGB = [math]::Round(($ingestResult.Results.TotalBillableUsageGB), 2)
            $dailyIngestVolumeGB = [math]::Round(($thirtyDayIngestVolumeGB/30), 2)
            if($thirtyDayIngestVolumeGB -gt $largeLawsThresholdSize){
              $largeLaw = $true
            }else{
              $largeLaw = $false
            }
        
            # Add the details to the results array
            $props = [ordered]@{
                "SubscriptionName"    = (Get-AzContext).Subscription.Name
                "WorkspaceName"       = $workspace.Name
                "ResourceGroup"       = $workspace.ResourceGroupName
                "RetentionInDays"     = $workspace.retentionInDays
                "BillingType"         = $workspace.Sku
                "ThirtyDayUsageInGB"  = $thirtyDayIngestVolumeGB
                "DailyIngestVolumeGB" = $dailyIngestVolumeGB
                "LargeLaw"            = $largeLaw
            }
            New-Object -TypeName psobject -Property $props
        }
    }
      

      #----------------------------------------------------------------------------------------
      # Modules to determine path to save Excel file
      #----------------------------------------------------------------------------------------
      function Get-DesktopPath {
          [CmdletBinding()]
          Param(
              [Parameter(
                  ValueFromPipeline = $true
              )]
              [string]
              $date,
              [Parameter(
                  ValueFromPipeline = $true
              )]
              [string]
              $fileName
          )

          process { 
              If ($env:HOME) {
                  Write-Verbose "Running on a non Windows computer.  Saving file to /users/%USERNAME%/Desktop"
                  $path = "$env:HOME/Desktop/$fileName-$date.xlsx"
                  $desktopPath = "$env:HOME/Desktop"
              }
              elseif($env:HOMEPATH) {
                  Write-Verbose "Running a Windows PC. Saving file to C:\users\%USERNAME%\Desktop"
                  $path = "$env:HOMEPATH\Desktop\$fileName-$date.xlsx"
                  $desktopPath = "$env:HOMEPATH\Desktop\"
              }

              If (Test-Path -Path $desktopPath){
                  Write-Verbose "Desktop path is valid"
              }
              Else{
                  Write-Verbose "Path is not valid.  Setting output to current working directory"
                  $folderPath = Get-Location | Select-Object -ExpandProperty Path
                  if($env:HOME){
                      Write-Verbose "Running on a non Windows computer."
                      $path = $folderPath + "/$fileName-$date.xlsx"
                  }else{
                      Write-Verbose "Running on a Windows computer."
                      $path = $folderPath + "\$fileName-$date.xlsx"
                  }
              }

              return $path
          }
      }


      #----------------------------------------------------------------------------------------
      # Module to get subs from the Tenant
      #----------------------------------------------------------------------------------------
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
              $i = 0

              foreach ($azSub in $azSubs) {
                  Write-Verbose "Getting information about $Azsub"
                  $subName = $azSub.Name
                  $subId = $azSub.SubscriptionID
                  $subTenantId = $azSub.TenantID
                  $subProps = [pscustomobject]@{
                      index       = $i
                      subName     = $subName
                      subID       = $subId
                      subTenantId = $subTenantId
                  }
                  $tenantProps += $subProps
                  $i++
              }
              return $tenantProps
          }
      }

      function Read-AzSubsToRunAgainst() {
          $input_subs = @()
          $user_input = Read-Host "Select Subscriptions (example: 0,2)"
          $input_subs = $user_input.Split(',') | ForEach-Object { [int]$_ }
          return $input_subs
      }

      #----------------------------------------------------------------------------------------
      # Modules to validate user input
      #----------------------------------------------------------------------------------------
      function Confirm-Numeric ($Value) {
          return $Value -match "^[\d\.]+$"
      }

      function Confirm-ValidSelectedIds($ids, $subs) {
          if ($ids.Length -gt $subs.Length) {
              Write-Host -fore red "Too many subscription indexes selected." -Verbose
              return 1
          }
          for ($i = 0; $i -le $ids.Length - 1; $i++) {
              $index = [int]$ids[$i]
              $is_numeric = Confirm-Numeric $index
              if (!$is_numeric) {
                  Write-Host -fore red "Invalid subscription selection, enter only numbers." -Verbose
                  return 1
              }
              if ($index -gt $subs.Length - 1) {
                  Write-Host -fore red "Invalid subscription selection, only select valid indexes." -Verbose
                  return 1
              }
          }
          return 0
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
      $date = (Get-Date).ToShortDateString().Replace("/", "-")
      $selectedAzSubs = @()
      $laws = [System.Collections.ArrayList]::new()
      $largeLaws = [System.Collections.ArrayList]::new()
      $largeLawsUsage = [System.Collections.ArrayList]::new()
      $largeLawsBillable = [System.Collections.ArrayList]::new()
      $largeLawsThresholdSize = 10
      $billableResourcesQuery = @"
find where TimeGenerated between(startofday(ago(1d))..startofday(now())) project _ResourceId, _BilledSize, _IsBillable, Type, Category, Computer
| where _IsBillable == true
| summarize DailyBillableDataGB = sum(_BilledSize)/(1024 * 1024 * 1024) by _ResourceId, Type, Category, Computer
| where DailyBillableDataGB >= 1
| sort by DailyBillableDataGB nulls last
"@

      $usageQuery = @"
Usage 
| where TimeGenerated > ago(32d)
| where StartTime >= startofday(ago(31d)) and EndTime < startofday(now())
| where IsBillable == true
| summarize BillableDataGB = sum(Quantity) / 1000 by Solution, DataType
| sort by Solution asc, DataType asc
"@

      #Gathering and determine which subs to run against. 
      $azSubs = Get-AzSubsFromTenant 
      Write-Output $azSubs | Format-Table -AutoSize

      $selectedSubIds = Read-AzSubsToRunAgainst

      $selectedSubsValid = Confirm-ValidSelectedIds $selectedSubIds $azSubs
      if ($selectedSubsValid -ne 0) {
          exit
      }
      Else {
          #Sub selection valid
      }

      ForEach ($selectedSubId in $selectedSubIds) {
        $sub = $azSubs | Where-Object { $_.Index -eq $selectedSubId }
        $selectedAzSubs += $sub
      }

      ## Gathering security score in each sub
      foreach ($azSub in $selectedAzSubs) {
        $null = Set-AzContext -SubscriptionId $azSub.subId -TenantID $azsub.subTenantId | Select-Object -ExpandProperty name
        $azSubName = $azSub.subName
        Write-Host "Getting Log Analytic Workspaces for sub: $azSubName" -ForegroundColor green
        $subLawsUsage = Get-AzOperationalInsightsWorkspaceUsageDetails -largeLawsThresholdSize $largeLawsThresholdSize
        if($subLawsUsage.count -eq 1){
          $laws.Add($subLawsUsage) | Out-Null
        }elseif($subLawsUsage.count -gt 1){
          $laws.AddRange($subLawsUsage) | Out-Null
        }else{
          Write-Host "No Log Analytic Workspaces found for $azSubName" -ForegroundColor Red
        }
        foreach($law in $subLawsUsage) {
          if($law.LargeLaw) {
            $largeLaws.Add($law) | Out-Null
          }
        }
      }

      $excelPath = Get-DesktopPath -date $date -fileName "AzLAWS"

      ## Remove existing resource report
      If (Test-Path $excelPath) {
          Remove-Item $excelPath -Force
      }

      #Outputing Excel File to current users desktop
      $laws | Export-Excel -Path $excelPath -WorksheetName "Workspaces"

      ## Analying Large Log Analytic Workspaces



      # Investigate Large Log Analytic Workspaces
      foreach($law in $largeLaws) {
        Set-AzContext -SubscriptionName $law.SubscriptionName | Out-Null
        try{
          $ws = Get-AzOperationalInsightsWorkspace -ResourceGroupName $law.ResourceGroup -Name $law.WorkspaceName
        }catch{
          Write-Host "Error getting workspace $($law.WorkspaceName): $_" -ForegroundColor Red
          continue
        }
        $wsName = $ws.Name.Substring(0, [System.Math]::Min(30, $ws.Name.Length))

        $billableQueryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $ws.CustomerId -Query $billableResourcesQuery
        if($billableQueryResults.Results.DailyBillableDataGB) {
          $results = [System.Collections.ArrayList]::new()
          foreach($result in $billableQueryResults.Results){
            $props = [ordered]@{
              "SubscriptionName" = $law.SubscriptionName
              "WorkspaceName" = $wsName
              "ResourceId" = $result._ResourceId
              "Type" = $result.Type
              "Category" = $result.Category
              "Computer" = $result.Computer
              "DailyBillableDataGB" = $result.DailyBillableDataGB
            }
            $output = New-Object -TypeName psobject -Property $props
            $results.add($output) | Out-Null
          }
          if($results.Count -gt 1){
            $largeLawsBillable.AddRange($results) | Out-Null
          }else{
            $largeLawsBillable.Add($results) | Out-Null
          }
          $results | Export-Excel -Path $excelPath -WorksheetName $wsName
        }else{
          $usageQueryResults= Invoke-AzOperationalInsightsQuery -WorkspaceId $ws.CustomerId -Query $usageQuery
          if($usageQueryResults.Results.BillableDataGB) {
            $results = [System.Collections.ArrayList]::new()
            foreach($result in $usageQueryResults.Results){
              $props = [ordered]@{
                "SubscriptionName" = $law.SubscriptionName
                "WorkspaceName" = $wsName
                "Solution" = $result.Solution
                "DataType" = $result.DataType
                "BillableDataGB" = $result.BillableDataGB
              }
              $output = New-Object -TypeName psobject -Property $props
              $results.add($output) | Out-Null
            }
            $results | Export-Excel -Path $excelPath -WorksheetName $wsName
            if($results.Count -gt 2){
              $largeLawsUsage.AddRange($results) | Out-Null
            }else{
              $largeLawsUsage.Add($results) | Out-Null
            }
          }else{
            Write-Verbose "No data found for $wsName"
          }
        }

      $largeLawsBillable | Export-Excel -Path $excelPath -WorksheetName "Total Billable Data"
      $largeLawsUsage | Export-Excel -Path $excelPath -WorksheetName "Total Usage Data"
      }
  }
}