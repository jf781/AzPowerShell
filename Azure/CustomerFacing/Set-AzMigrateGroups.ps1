
function Set-AzMigrateGroup {
  <#
    .SYNOPSIS
    Manages Azure Migrate groups by adding and removing virtual machines (VMs) from the group.

    In order for this script to reconcile the VMs associated with a group, an assessment must have been run for that group. The script will compare the VMs in the group with the discovered VMs and make the necessary changes.  The assessment will need to be up to date in order for the script to accurately determine the VMs in the group.

    .DESCRIPTION
    The Set-AzMigrateGroup function interacts with the Azure Migrate API to manage VM groups. It:
    - Checks if a group exists, and creates it if necessary.
    - Adds or removes VMs to/from the group based on user input.
    - Fetches discovered VMs and compares them with the existing group VMs.
    Utilizes helper functions for REST API operations with Azure Migrate.

    .PARAMETER subscriptionID
    The Azure subscription ID. If omitted, the current Azure context's subscription ID is used.

    .PARAMETER resourceGroupName
    The name of the resource group.

    .PARAMETER assessmentProject
    The name of the Azure Migrate assessment project.

    .PARAMETER groupName
    The name of the Azure Migrate group to manage or create.

    .PARAMETER groupVMs
    An array of VM names to add to or remove from the group.  Can specify directly or pull from a CSV or text file.

    .EXAMPLE
    Set-AzMigrateGroup -resourceGroupName "MyResourceGroup" -assessmentProject "MyAssessment" -groupName "MyGroup" -groupVMs @("VM1", "VM2")

    Adds VM1 and VM2 to the group "MyGroup" in the assessment project "MyAssessment".

    .EXAMPLE
    Set-AzMigrateGroup -resourceGroupName "MyResourceGroup" -assessmentProject "MyAssessment" -groupName "MyGroup" -groupVMs (Get-Content ListofVMs.txt)

    Adds the VMs listed in the text file `ListofVMs.txt` to the group "MyGroup" in the assessment project "MyAssessment".

    .NOTES
    Version:        1.0
    Author:         Joe Fecht - AHEAD, llc.
    Creation Date:  September 2024
    Purpose/Change: Initial deployment
  #>


  [CmdletBinding()]
  param (
    [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
    [string]
    $subscriptionID,
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [string]
    $resourceGroupName,
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [string]
    $assessmentProject,
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [string]
    $groupName,
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [string[]]
    $groupVMs
  )
  process {

    # Utility Functions
    function Add-AzMigrateGroupVMs {
      [CmdletBinding()]
      param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $subscriptionID,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $resourceGroupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $assessmentProject,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object]
        $group,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $accessToken,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $apiVersion,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string[]]
        $machines
      )
      process {
        $groupName = $group.name
        $groupEtag = $group.eTag

        $headers = @{
          Authorization = "Bearer $accessToken"
        }

        $groupProperties = @{
          "etag" = '"' + $groupEtag + '"';
          "properties" = @{
            "machines" = $machines
            "operationType" = "Add"
          }
        }
        $body = ConvertTo-Json $groupProperties -Depth 3
        $uri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$assessmentProject/groups/$groupName/updateMachines" + "?api-version=$apiVersion"

        try {
          Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType "application/json" | out-null
        } catch {
          Write-Error $_
          break
        }
      }
    }

    function Remove-AzMigrateGroupVMs {
      [CmdletBinding()]
      param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $subscriptionID,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $resourceGroupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $assessmentProject,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object]
        $group,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $accessToken,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $apiVersion,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string[]]
        $machines
      )
      process {
        $groupName = $group.name
        $groupEtag = $group.eTag

        $headers = @{
          Authorization = "Bearer $accessToken"
        }

        $groupProperties = @{
          "etag" = '"' + $groupEtag + '"';
          "properties" = @{
            "machines" = $machines
            "operationType" = "Remove"
          }
        }
        $body = ConvertTo-Json $groupProperties -Depth 3
        $uri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$assessmentProject/groups/$groupName/updateMachines" + "?api-version=$apiVersion"

        try {
          Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType "application/json" | Out-Null
        } catch {
          Write-Error $_
          break
        }
      }
    }

    function New-AzMigrateGroup {
      [CmdletBinding()]
      param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $subscriptionID,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $resourceGroupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $assessmentProject,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $groupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $accessToken,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $apiVersion
      )
      process {

        $headers = @{
          Authorization = "Bearer $accessToken"
        }

        $groupETag = (New-Guid).Guid
        $groupProperties = @{
          "etag" = '"' + $groupETag + '"';
          "properties" = @{}
        }
        $body = ConvertTo-Json $groupProperties -Depth 3
        $uri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$assessmentProject/groups/$groupName" + "?api-version=$apiVersion"


        try {
          $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $body -ContentType "application/json"
        } catch {
          Write-Error $_
          break
        }

        $props = [ordered]@{
          "assessmentProject" = $assessmentProject
          "name" = $response.name
          "eTag" = $response.eTag
          "id" = $response.id
        }

        $obj = New-Object -TypeName PSObject -Property $props

        return $obj
      }
    }

    function Get-AzMigrateGroup {
      [CmdletBinding()]
      param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $subscriptionID,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $resourceGroupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $assessmentProject,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $groupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $accessToken,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $apiVersion
      )
      process {

        $headers = @{
          Authorization = "Bearer $accessToken"
        }

        $uri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$assessmentProject/groups/$groupName" + "?api-version=$apiVersion"

        try {
          $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        } catch {
          Write-Verbose "Error trying to retrieve group: $groupName"
          return
        }

        if($response){
          Write-Verbose "Group $groupName found"
          $props = [ordered]@{
            "assessmentProject" = $assessmentProject
            "name" = $response.name
            "eTag" = $response.eTag
            "id" = $response.id
          }

          $obj = New-Object -TypeName PSObject -Property $props

          return $obj
        }else{
          Write-Verbose "Group $groupName not found"
          return $null
        }
      }
    }

    function Get-AzMigrateMachines {
      [CmdletBinding()]
      param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $subscriptionID,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $resourceGroupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $assessmentProject,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $accessToken,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $apiVersion
      )
      process {
        $discoveredVMs = New-Object System.Collections.ArrayList

        $headers = @{
          Authorization = "Bearer $accessToken"
        }

        $uri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$assessmentProject/machines" + "?api-version=$apiVersion"

        try {
          $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
          while($response.nextLink) {
            $discoveredVMs.addRange($response.value) | Out-Null
            $response = Invoke-RestMethod -uri $response.nextLink -Method GET -Headers $headers
          }

          $discoveredVMs.addRange($response.value) | Out-Null
        } catch {
          Write-Error $_
          break
        }

        return $discoveredVMs

      }
    }

    function Get-AzMigrateAssessment {
      [CmdletBinding()]
      param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $subscriptionID,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $resourceGroupName,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $assessmentProject,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $accessToken,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]
        $apiVersion,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object]
        $group
      )
      process {
        $groupName = $group.name

        $headers = @{
          Authorization = "Bearer $accessToken"
        }

        $assessmentUri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$assessmentProject/groups/$groupName/assessments" + "?api-version=$apiVersion"

        try {
          $assessmentResponse = Invoke-RestMethod -Uri $assessmentUri -Method Get -Headers $headers
          Write-Verbose "Assessment Found"
        } catch {
          Write-Verbose "No Assessment Found"
          Write-Verbose "Error: $_"
          return
        }
        
        if($assessmentResponse){
          $assessmentName = $assessmentResponse.value.name
          $assessmentDetailsUri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$assessmentProject/groups/$groupName/assessments/$assessmentName/assessedMachines" + "?api-version=$apiVersion"

          try{
            $assessmentDetailsResponse = Invoke-RestMethod -Uri $assessmentDetailsUri -Method Get -Headers $headers
          } catch {
            Write-Error $_
            return
          }

          $assessments = $assessmentDetailsResponse.value

          foreach($assessment in $assessments){
            $props = [ordered]@{
              "assessmentName" = $assessmentName
              "groupName"      = $groupName
              "vsphereName"   = $assessment.properties.displayName
            }

            New-Object -TypeName PSObject -Property $props

          }
        }else{
          Write-Verbose "No Assessments for $groupName"
          break
        }
      }
    }

    # Main Function

    ### Define Variables
    $existingVMsToBeRemoved = New-Object System.Collections.ArrayList
    $machinesToBeRemoved = New-Object System.Collections.ArrayList
    $vmsToBeAdded = New-Object System.Collections.ArrayList
    $machinesToBeAdded = New-Object System.Collections.ArrayList
    $vmErrors = New-Object System.Collections.ArrayList
    $apiVersion = "2023-03-15"

    $accessToken = (Get-AzAccessToken).Token

    if(!$subscriptionID){
      Write-Verbose "No Subscription ID provided, using current context"
      $subscriptionID = (Get-AzContext).Subscription.Id
    }

    ### Get all discovered VMs
    $discoveredVMs = Get-AzMigrateMachines -subscriptionID $subscriptionID -resourceGroupName $resourceGroupName -assessmentProject $assessmentProject -accessToken $accessToken -apiVersion $apiVersion

    ### Determine if group exists and create it if needed
    $group = Get-AzMigrateGroup -subscriptionID $subscriptionID -resourceGroupName $resourceGroupName -assessmentProject $assessmentProject -groupName $groupName -accessToken $accessToken -apiVersion $apiVersion -ErrorAction SilentlyContinue
    if($group){
      Write-Verbose "Group $groupName already exists"
    }else{
      $group = New-AzMigrateGroup -subscriptionID $subscriptionID -resourceGroupName $resourceGroupName -assessmentProject $assessmentProject -groupName $groupName -accessToken $accessToken -apiVersion $apiVersion
      Write-Verbose "Group $groupName created"
    }

    ### Identify existing VMs in group (Requires an assessment for that group to have already ran)
    $existingGroupVMs = Get-AzMigrateAssessment -subscriptionID $subscriptionID -resourceGroupName $resourceGroupName -assessmentProject $assessmentProject -accessToken $accessToken -apiVersion $apiVersion -group $group -ErrorAction SilentlyContinue

    if($existingGroupVMs){
      Write-Verbose "Existing Assessment found"
    }else{
      Write-Verbose "No existing Assessment found"
      $existingGroupVMs = [ordered]@{
        "assessmentName" = ""
        "groupName"      = $group.Name
        "vsphereName"    = ""
      }
    }

    # Determine changes to the VMs in the group
    foreach ($vm in $groupVMs){
      if($existingGroupVMs.vsphereName -contains $vm){
        Write-Debug "VM already exists, no changes"
      }else{
        Write-Debug "Adding VM: $vm"
        $vmsToBeAdded.Add($vm) | Out-Null
      }
    }

    foreach ($vm in $existingGroupVMs){
      if($groupVMs -contains $vm.vsphereName){
        Write-Debug "VM already exists, no changes"
      }else{
        Write-Debug "Removing VM: $($vm.vsphereName)"
        $existingVMsToBeRemoved.Add($vm.vsphereName) | Out-Null
      }
    }

    # Add VMs to the group
    if($vmsToBeAdded){
      foreach($vm in $vmsToBeAdded){
        $vmDetails = $discoveredVMs | Where-Object { $_.properties.displayName -eq $vm }

        if($vmDetails){
          $machinesToBeAdded.Add($vmDetails.id) | Out-Null
          Write-Host "Adding VM: $vm to $groupName"
        }else{
          Write-Host "VM $vm not found in discovered VMs. Please confirm the VM name in the list provided matches the discovered VM name in Azure Migrate"
          $vmError = [pscustomobject]@{
            "vmName"    = $vm
            "operation" = "Add"
            "error"     = "VM not found in discovered VMs. Please confirm the VM name in the list provided matches the discovered VM name in Azure Migrate"
          }
          $vmErrors.Add($vmError) | Out-Null
        }
      }

      Add-AzMigrateGroupVMs -subscriptionID $subscriptionID -resourceGroupName $resourceGroupName -assessmentProject $assessmentProject -group $group -accessToken $accessToken -apiVersion $apiVersion -machines $machinesToBeAdded
    }

    # Remove VMs from the group
    if($existingVMsToBeRemoved){
      foreach($vm in $existingVMsToBeRemoved){
        $vmDetails = $discoveredVMs | Where-Object { $_.properties.displayName -eq $vm }
        if($vmDetails){
          $machinesToBeRemoved.Add($vmDetails.id) | Out-Null
          Write-Host "Removing VM: $vm from $groupName"
        }else{
          Write-Host "VM $vm not found in discovered VMs. Please confirm the VM name in the list provided matches the discovered VM name in Azure Migrate"
          $vmError = [pscustomobject]@{
            "vmName"    = $vm
            "operation" = "Add"
            "error"     = "VM not found in discovered VMs. Please confirm the VM name in the list provided matches the discovered VM name in Azure Migrate"
          }
          $vmErrors.Add($vmError) | Out-Null
        }
      }

      Remove-AzMigrateGroupVMs -subscriptionID $subscriptionID -resourceGroupName $resourceGroupName -assessmentProject $assessmentProject -group $group -accessToken $accessToken -apiVersion $apiVersion -machines $machinesToBeRemoved
    }

    return $vmErrors
  }
}