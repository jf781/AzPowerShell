function Replace-AzTagName {
  [CmdLetBinding()]
  param(
    [Parameter(
      Mandatory = $true)]
    [string]
    $existingTagName,
    [Parameter(
      Mandatory = $true)]
    [string]
    $newTagName,
    [Parameter(
      Mandatory = $false)]
    [bool]
    $removeOldTag = $false
  )
  
  process {

    #------------------------------------------------------
    # Define Utility Functions
    #------------------------------------------------------

    function Update-AzTagName {
      [CmdLetBinding()]
      param(
        [Parameter(
          mandatory = $true)]
        [string]
        $existingTagName,
        [Parameter(
          mandatory = $true)]
        [string]
        $NewTagName,
        [Parameter(
          mandatory = $true)]
        [string]
        $resourceId,
        [Parameter(
          mandatory = $true)]
        [bool]
        $removeOldTag
      )

      process{
        Write-Verbose "In Replace-AzTag function"
        $existingTagValue = $null
        
        Write-Verbose "Getting tag values for `$resourceId: $resourceId"
        (Get-AzTag -ResourceId $resourceId | 
          Select-Object -ExpandProperty Properties | 
          Select-Object -expandProperty TagsProperty).TryGetValue($existingTagName, [ref]$existingTagValue)
    
        $newTag = @{"$NewTagName" = "$existingTagValue" }
        Write-Verbose "New Tag value is $newTag"

        try{
          Write-Host "Updating the tag for $resourceId" -ForegroundColor Green
          Write-Host "New Tag Value:   $NewTagName = $existingTagValue" -ForegroundColor green
          Write-Host "--" -ForegroundColor green
          Update-AzTag -ResourceId $resourceId -Tag $newTag -Operation Merge | Out-Null
        }catch{
          Write-Verbose "Failed to update tag for: $resourceId"
          Write-Host "Failed to update tag for: $resourceId" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }

        try{
          if ($removeOldTag) {
            $oldTag = @{"$existingTagName" = "$existingTagValue" }
            Write-Verbose "In If block.  `$removeOldTag value: $removeOldTag"
            Write-Host "Removing existing tag from $resourceId" -ForegroundColor Green
            Write-Host "Old Tag Value:  $existingTagName = $existingTagValue" -ForegroundColor Green
            Write-Host "--" -ForegroundColor green
            Update-AzTag -ResourceId $resourceId -Tag $oldTag -Operation Delete | Out-Null
          }else{
            Write-Verbose "In Else block.  `$removeOldTag value: $removeOldTag"
          }
        }catch{
          Write-Verbose "Failed to remove tag: $oldTag"
          Write-Host "Failed to remove tag: $resourceId" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return
        }
      }
    }

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


    #------------------------------------------------------
    # Main Function
    #------------------------------------------------------

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
      return
    }

    Write-Verbose "Getting resources that have the existing tag name defined"
    $resourceIds = Get-AzResource -TagName $existingTagName | Select-Object -ExpandProperty ResourceId

    foreach($resourceId in $resourceIds){
      Write-Verbose "Replacing Tag Names for `$resourceId: $resourceId"
      Update-AzTagName -existingTagName $existingTagName -newTagName $newTagName -resourceId $resourceId -removeOldTag $removeOldTag
    }

    Write-Verbose "Getting resource groups that have the existing tag name defined"
    $resourceGroupIds = Get-AzResourceGroup | Select-Object -ExpandProperty ResourceId

    foreach($resourceGroupId in $resourceGroupIds){
      Write-Verbose "Determining if tag $existingTagName is defined on $resourceGroupId"
      $existingTags = $null
      $groupContainsExistingTag = $null
      $existingTags = Get-AzTag -ResourceId $resourceGroupId | 
                                  Select-Object -ExpandProperty Properties |
                                  Select-Object -ExpandProperty TagsProperty

      if ($existingTags) {
        Write-Verbose "In If block.  See if $existingTagName is defined in $resourceGroupId"
        $groupContainsExistingTag = $existingTags.ContainsKey("$existingTagName")
      }else{
        Write-Verbose "In Else block.  $resourceGroupId does not have any tags defined. "
      }

      If($groupContainsExistingTag){
        Write-Verbose "Tag: $existingTagName is present on $resourceGroupId. Updating Tag"
        Update-AzTagName -existingTagName $existingTagName -newTagName $newTagName -resourceId $resourceGroupId -removeOldTag $removeOldTag
      }else{
        Write-Verbose "Tag: $existingTagName is not present on $resourceGroupId"
      }
    }

    Write-Verbose "Checking the subscription to see if the existing tag is defined"
    $subTags = $null
    $subContainsExistingTag = $null
    $subId = "/subscriptions/" + (Get-AzContext).Subscription.Id
    
    $subTags = Get-AzTag -ResourceId $subId -ErrorAction SilentlyContinue | 
                                Select-Object -ExpandProperty Properties |
                                Select-Object -ExpandProperty TagsProperty

    if($subTags){
      Write-Verbose "In If block.  Subscription has tags defined"
      $subContainsExistingTag = $subTags.ContainsKey("$existingTagName")
    }else{
      Write-Verbose "In Else block.  Subscription does not have tags. "
    }

    If($subContainsExistingTag) {
      Write-Verbose "Tag: $existingTagName is present on $subId. Updating Tag"
      Update-AzTagName -existingTagName $existingTagName -newTagName $newTagName -resourceId $subId -removeOldTag $removeOldTag
    }else{
      Write-Verbose "Tag: $existingTagName is not present on $subId"
    }

  }
}