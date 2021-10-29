
Function Audit-SPOListPermissions {
  [CmdletBinding()]
  param (
    [Parameter(
      Mandatory = $true
    )]
    [string]
    $siteURL,
    [Parameter(
      Mandatory = $true
    )]
    [string]
    $csvOutputPath,
    [Parameter(
      Mandatory = $false
    )]
    [System.Management.Automation.PSCredential]
    $cred
    
  )
    
  process {
    ########################################
    # Declare Functions
    ########################################
    Function Invoke-LoadMethod() {
      Param(
        [Microsoft.SharePoint.Client.ClientObject]$Object = $(throw "Please provide a Client Object"), [string]$PropertyName
      )
      $Ctx = $Object.Context
      $Load = [Microsoft.SharePoint.Client.ClientContext].GetMethod("Load")
      $Type = $Object.GetType()
      $ClientLoad = $Load.MakeGenericMethod($Type)
                
      $Parameter = [System.Linq.Expressions.Expression]::Parameter(($Type), $Type.Name)
      $Expression = [System.Linq.Expressions.Expression]::Lambda([System.Linq.Expressions.Expression]::Convert([System.Linq.Expressions.Expression]::PropertyOrField($Parameter, $PropertyName), [System.Object] ), $($Parameter))
      $ExpressionArray = [System.Array]::CreateInstance($Expression.GetType(), 1)
      $ExpressionArray.SetValue($Expression, 0)
      $ClientLoad.Invoke($Ctx, @($Object, $ExpressionArray))
    }
    
    function Test-CSVPath {
      [CmdletBinding()]
      param (
        [Parameter()]
        [string]
        $csvPath
      )
      process {
        try {
          if (test-path -Path $csvPath) {
            Write-Verbose "CSV Path Valid"
          }
          else {
            Write-Verbose "CSV Path $csvPath is invalid"
            throw
          }
        }
        catch {
          Write-Error "The CSV path $csvPath is invalid.  Please update CSV path and run again" -ErrorAction Stop
        }
      }
    
    } 
    
    Function Get-SPOItemPermissions {
      [CmdletBinding()]
      param (
        [Parameter()]
        [string]
        $itemType,
        [Parameter()]
        [string]
        $relativeUrl
      )
    
      Process {
        if ($itemType -eq "Folder") {
          $item = $ctx.Web.GetFolderByServerRelativeUrl($relativeUrl)
        }
        Else {
          $item = $ctx.Web.GetFileByServerRelativeUrl($relativeUrl)
        }
        $ctx.Load($item)
        $ctx.ExecuteQuery()
    
        #Get permissions assigned to the Folder
        $roleAssignments = $item.ListItemAllFields.RoleAssignments
        $ctx.Load($roleAssignments)
        $ctx.ExecuteQuery()
    
        #Loop through each permission assigned and extract details
        $permissionCollection = @()
        Foreach ($roleAssignment in $roleAssignments) {
          $ctx.Load($roleAssignment.Member)
          $ctx.executeQuery()
    
          #Get the User Type
          $permissionType = $roleAssignment.Member.PrincipalType
    
          #Get the Permission Levels assigned
          $ctx.Load($roleAssignment.RoleDefinitionBindings)
          $ctx.ExecuteQuery()
          $permissionLevels = ($roleAssignment.RoleDefinitionBindings | Where-Object { $_.name -ne "Limited Access" } | Select-Object -ExpandProperty Name) -join ","
                        
          #Get the User/Group Name
          $name = $roleAssignment.Member.Title # $RoleAssignment.Member.LoginName
    
          if ($permissionLevels) {
            #Add the Data to Object
            New-Object PSObject -Propert ([Ordered] @{
                name             = $name
                permissionType   = $permissionType
                permissionLevels = $permissionLevels
              })
          }
        }
      }
    } 
    
    Function Get-SPOListPermissions {
      [CmdletBinding()]
      param (
        [Parameter()]
        [Microsoft.SharePoint.Client.List]
        $list
      )
    
      Process {
        #Get permissions assigned to the Folder
        $roleAssignments = $list.RoleAssignments
        $ctx.Load($roleAssignments)
        $ctx.ExecuteQuery()
    
        #Loop through each permission assigned and extract details
        $permissionCollection = @()
        Foreach ($roleAssignment in $roleAssignments) {
          $ctx.Load($roleAssignment.Member)
          $ctx.executeQuery()
    
          #Get the User Type
          $permissionType = $roleAssignment.Member.PrincipalType
    
          #Get the Permission Levels assigned
          $ctx.Load($roleAssignment.RoleDefinitionBindings)
          $ctx.ExecuteQuery()
          $permissionLevels = ($roleAssignment.RoleDefinitionBindings | Where-Object { $_.name -ne "Limited Access" } | Select-Object -ExpandProperty Name) -join ","
                        
          #Get the User/Group Name
          $name = $roleAssignment.Member.Title # $RoleAssignment.Member.LoginName
    
          if ($permissionLevels) {
            #Add the Data to Object
            New-Object PSObject -Propert ([Ordered] @{
                name             = $name
                permissionType   = $permissionType
                permissionLevels = $permissionLevels
              })
          }
        }
      }
    } 
    
    Function Get-SPOListItems {
      [CmdletBinding()]
      param (
        [Parameter()]
        [Microsoft.SharePoint.Client.List]
        $list
      )
            
      process {
        #Check if the given site is using unique permissions
        $listPermissions = Get-SPOListPermissions -list $list
            
            
        $query = New-Object Microsoft.SharePoint.Client.CamlQuery
        $query.ViewXml = "<View Scope='RecursiveAll'><RowLimit>1000000</RowLimit></View>"
        $listItems = $list.GetItems($query)
        $listName = $list.Title
        $ctx.Load($listItems)
        $ctx.ExecuteQuery()
            
        Write-host -f Green "`t Auditing items in list '$listName'"
            
        New-Object PSObject -Property ([Ordered] @{
            site            = $list.ParentWebUrl
            list            = $listName
            itemName        = $null
            itemType        = "List"
            itemUniquePerms = $null
            inheritedFrom   = $null
            itemPermissions = ($listPermissions | Out-String).Trim()
                        
          })
            
        foreach ($item in $listItems) {
          Invoke-LoadMethod -Object $item -PropertyName "HasUniqueRoleAssignments"
          Invoke-LoadMethod -Object $item -PropertyName "FirstUniqueAncestorSecurableObject"
          Invoke-LoadMethod -Object $item -PropertyName "ParentList"
          $Ctx.ExecuteQuery()
            
          $itemPath = $item.fieldValues.FileRef
          $itemName = $item.fieldValues.FileLeafRef
          $itemUniquePerms = $item.HasUniqueRoleAssignments
          $itemType = $item.FileSystemObjectType
          $site = $item.ParentList.ParentWebUrl
          $inheritedFrom = $item.FirstUniqueAncestorSecurableObject.FieldValues.FileRef
                        
            
          if ($itemUniquePerms) {
            # write-output "`$itemPath = $itemPath"
            $itemPermissions = Get-SPOItemPermissions -relativeUrl $itemPath -itemType $itemType
            $inheritedFrom = $null
          }
          elseif ($inheritedFrom) {
            $itemPermissions = $null
            $inheritedFrom = $inheritedFrom                
          }
          else {
            $itemPermissions = $null
            $inheritedFrom = "Inherited from List"
          }
            
          New-Object PSObject -Property ([Ordered] @{
              site            = $site
              list            = $listName
              itemName        = $itemName
              itemType        = $itemType
              itemUniquePerms = $itemUniquePerms
              inheritedFrom   = $inheritedFrom
              itemPermissions = ($itemPermissions | Out-String).Trim()
            
            })
          $Counter++
          Write-Progress -PercentComplete ($Counter / ($List.ItemCount) * 100) -Activity "Processing Items: $Counter of $($List.ItemCount)" -Status "Searching Unique Permissions in List Items of '$($List.Title)'"
        }
      }
    }
    
    function Get-SPOSiteLists {
      [CmdletBinding()]
      param (
        [Parameter()]
        [Microsoft.SharePoint.Client.Web]
        $web
      )
      process {
        ### Get unique permission in Lists
        Write-host -f Green "`t Getting lists from site"
        $lists = $web.Lists
        $ctx.Load($lists)
        $ctx.ExecuteQuery()
                
        #Exclude system lists
        $excludedLists = @("App Packages", "appdata", "appfiles", "Apps in Testing", "Cache Profiles", "Composed Looks", "Content and Structure Reports", "Content type publishing error log", "Converted Forms",
          "Device Channels", "Form Templates", "fpdatasources", "Get started with Apps for Office and SharePoint", "List Template Gallery", "Long Running Operation Status", "Maintenance Log Library", "Style Library",
          , "Master Docs", "Master Page Gallery", "MicroFeed", "NintexFormXml", "Quick Deploy Items", "Relationships List", "Reusable Content", "Search Config List", "Solution Gallery", "Site Collection Images",
          "Suggested Content Browser Locations", "TaxonomyHiddenList", "User Information List", "Web Part Gallery", "wfpub", "wfsvc", "Workflow History", "Workflow Tasks", "Preservation Hold Library")
    
        $dataColleciton = @()
        ForEach ($list in $lists) {
          $ctx.Load($list)
          $ctx.ExecuteQuery()
                
          If ($excludedLists -NotContains $list.Title -and $list.Hidden -eq $false) {
            # $data = $list
            $dataColleciton += $list
          }
                        
        }
        return $dataColleciton
      }
    }
    
    # Function Get-SPOAccess {
    #   [CmdletBinding()]
    #   param (
    #     [Parameter()]
    #     [Microsoft.SharePoint.Client.SecurableObject]
    #     $Object
    #   )
    #   process {
    #     #Determine the type of the object
    #     Switch ($Object.TypedObject.ToString()) {
    #       "Microsoft.SharePoint.Client.Web" { $ObjectType = "Site" ; $ObjectURL = $Object.URL }
    #       "Microsoft.SharePoint.Client.ListItem" {
    #         $ObjectType = "List Item/Folder"
        
    #         #Get the URL of the List Item
    #         Invoke-LoadMethod -Object $Object.ParentList -PropertyName "DefaultDisplayFormUrl"
    #         $Ctx.ExecuteQuery()
    #         $DefaultDisplayFormUrl = $Object.ParentList.DefaultDisplayFormUrl
    #         $ObjectURL = $("{0}{1}?ID={2}" -f $Ctx.Web.Url.Replace($Ctx.Web.ServerRelativeUrl, ''), $DefaultDisplayFormUrl, $Object.ID)
    #       }
    #       Default {
    #         $ObjectType = "List/Library"
    #         #Get the URL of the List or Library
    #         $Ctx.Load($Object.RootFolder)
    #         $Ctx.ExecuteQuery()           
    #         $ObjectURL = $("{0}{1}" -f $Ctx.Web.Url.Replace($Ctx.Web.ServerRelativeUrl, ''), $Object.RootFolder.ServerRelativeUrl)
    #       }
    #     }
        
    #     #Get permissions assigned to the object
    #     $Ctx.Load($Object.RoleAssignments)
    #     $Ctx.ExecuteQuery()
        
    #     Foreach ($RoleAssignment in $Object.RoleAssignments) {
    #       $Ctx.Load($RoleAssignment.Member)
    #       $Ctx.executeQuery()
        
    #       #Check direct permissions
    #       if ($RoleAssignment.Member.PrincipalType -eq "User") {
    #         #Is the current user is the user we search for?
    #         if ($RoleAssignment.Member.LoginName -eq $SearchUser.LoginName) {
    #           #Write-Host  -f green "Found the User under direct permissions of the $($ObjectType) at $($ObjectURL)"
                                
    #           #Get the Permissions assigned to user
    #           $UserPermissions = @()
    #           $Ctx.Load($RoleAssignment.RoleDefinitionBindings)
    #           $Ctx.ExecuteQuery()
    #           foreach ($RoleDefinition in $RoleAssignment.RoleDefinitionBindings) {
    #             $UserPermissions += $RoleDefinition.Name + ";"
    #           }
    #           #Send the Data to Report file
    #           "$($ObjectURL) `t $($ObjectType) `t $($Object.Title)`t Direct Permission `t $($UserPermissions)" | Out-File $accessReportPath -Append
    #         }
    #         else {
    #           Write-Host -f Cyan "`t $($userTitle) does not have access to $($ObjectUrl)"
    #         }
    #       }
                        
    #       Elseif ($RoleAssignment.Member.PrincipalType -eq "SharePointGroup") {
    #         #Search inside SharePoint Groups and check if the user is member of that group
    #         $Group = $Web.SiteGroups.GetByName($RoleAssignment.Member.LoginName)
    #         $GroupUsers = $Group.Users
    #         $Ctx.Load($GroupUsers)
    #         $Ctx.ExecuteQuery()
        
    #         #Check if user is member of the group
    #         Foreach ($User in $GroupUsers) {
    #           #Check if the search users is member of the group
    #           if ($user.LoginName -eq $SearchUser.LoginName) {
    #             Write-Host -f Green "Found the User under Member of the Group '$($RoleAssignment.Member.LoginName)' on $($ObjectType) at $($ObjectURL)"
        
    #             #Get the Group's Permissions on site
    #             $GroupPermissions = @()
    #             $Ctx.Load($RoleAssignment.RoleDefinitionBindings)
    #             $Ctx.ExecuteQuery()
    #             Foreach ($RoleDefinition  in $RoleAssignment.RoleDefinitionBindings) {
    #               $GroupPermissions += $RoleDefinition.Name + ";"
    #             }         
    #             #Send the Data to Report file
    #             "$($ObjectURL) `t $($ObjectType) `t $($Object.Title)`t Member of '$($RoleAssignment.Member.LoginName)' Group `t $($GroupPermissions)" | Out-File $accessReportPath -Append
    #           }
    #         }
    #       }
    #     }
    #   }
    # }
    
    # Function Get-SPOListItemAccess {
    #   [CmdletBinding()]
    #   param (
    #     [Parameter()]
    #     [Microsoft.SharePoint.Client.List]
    #     $list
    #   )
    #   process {
    #     Write-host -f Green "Searching in List Items of the List '$($List.Title)..."
        
    #     $Query = New-Object Microsoft.SharePoint.Client.CamlQuery
    #     $Query.ViewXml = "<View Scope='RecursiveAll'><Query><OrderBy><FieldRef Name='ID' Ascending='TRUE'/></OrderBy></Query><RowLimit Paged='TRUE'>$BatchSize</RowLimit></View>"
      
    #     $Counter = 0
    #     #Batch process list items - to mitigate list threashold issue on larger lists
    #     Do { 
    #       #Get items from the list in Batch
    #       $ListItems = $List.GetItems($Query)
    #       $Ctx.Load($ListItems)
    #       $Ctx.ExecuteQuery()
                
    #       $Query.ListItemCollectionPosition = $ListItems.ListItemCollectionPosition
    #       #Loop through each List item
    #       ForEach ($ListItem in $ListItems) {
    #         Invoke-LoadMethod -Object $ListItem -PropertyName "HasUniqueRoleAssignments"
    #         $Ctx.ExecuteQuery()
    #         if ($ListItem.HasUniqueRoleAssignments -eq $true) {
    #           #Call the function to generate Permission report
    #           Get-SPOAccess -Object $ListItem
    #         }
    #         $Counter++
    #         Write-Progress -PercentComplete ($Counter / ($List.ItemCount) * 100) -Activity "Processing Items $Counter of $($List.ItemCount)" -Status "Searching Unique Permissions in List Items of '$($List.Title)'"
    #       }
    #     } While ($Query.ListItemCollectionPosition -ne $null)
    #   }
    # }
      
    # #Function to Check Permissions of all lists from the web
    # Function Get-SPOListAccess {
    #   [CmdletBinding()]
    #   param (
    #     [Parameter()]
    #     [Microsoft.SharePoint.Client.Web]
    #     $web
    #   )
    #   process {
    #     #Get All Lists from the web
    #     $lists = $Web.Lists
    #     $Ctx.Load($Lists)
    #     $Ctx.ExecuteQuery()
        
    #     #Get all lists from the web  
    #     ForEach ($List in $Lists) {
    #       #Exclude System Lists
    #       If ($List.Hidden -eq $False) {
    #         #Get List Items Permissions
    #         Get-SPOListItemAccess -list $List
        
    #         #Get the Lists with Unique permission
    #         Invoke-LoadMethod -Object $List -PropertyName "HasUniqueRoleAssignments"
    #         $Ctx.ExecuteQuery()
        
    #         If ( $List.HasUniqueRoleAssignments -eq $True) {
    #           #Call the function to check permissions
    #           Get-SPOAccess -Object $List
    #         }
    #       }
    #     }
    #   }
    # }
      
    # #Function to Check Webs's Permissions from given URL
    # Function Get-SPOWebAccess {
    #   [CmdletBinding()]
    #   param (
    #     [Parameter()]
    #     [Microsoft.SharePoint.Client.Web]
    #     $web
    #   )
    #   process {
    #     #Get all immediate subsites of the site
    #     $Ctx.Load($web.Webs) 
    #     $Ctx.executeQuery()
        
    #     #Call the function to Get Lists of the web
    #     Write-host -f Green "Searching in the Web "$Web.URL"..."
        
    #     #Check if the Web has unique permissions
    #     Invoke-LoadMethod -Object $Web -PropertyName "HasUniqueRoleAssignments"
    #     $Ctx.ExecuteQuery()
        
    #     #Get the Web's Permissions
    #     If ($web.HasUniqueRoleAssignments -eq $true) {
    #       Get-SPOAccess -Object $Web
    #     }
        
    #     #Scan Lists with Unique Permissions
    #     Write-host -f Green "Searching in the Lists and Libraries of "$Web.URL"..."
    #     Get-SPOListAccess -web  $Web
        
    #     #Iterate through each subsite in the current web
    #     Foreach ($Subweb in $web.Webs) {
    #       #Call the function recursively                           
    #       Get-SPOWebAccess -web $SubWeb
    #     }
    #   }
    # }
    
    ########################################
    # Main Function
    ########################################
    
    #Load SharePoint CSOM Assemblies
    Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
    Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
           
    # Test CSV path
    Test-CSVPath -csvPath $csvOutputPath
            
    # Get Credentials to connect
    if ($cred) {
      # Creds provided when command launched. No need to prompt.
    }
    else {
      $cred = Get-Credential
    }
    try {
      # Setup the context
      $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($siteURL)
      $ctx.Credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($cred.UserName, $cred.Password)
                
      # Get the Web
      $web = $ctx.Web
      $ctx.Load($Web)
      $ctx.ExecuteQuery()
    
      # Get Role Definitions
      $roleDefs = $web.RoleDefinitions
      $ctx.Load($roleDefs)
      $ctx.ExecuteQuery()
    
      # Check if the given site is using unique permissions
      Invoke-LoadMethod -Object $web -PropertyName "HasUniqueRoleAssignments"
      $ctx.ExecuteQuery()
                
      #Get the Root Web
      $rootWeb = $ctx.site.RootWeb
      $ctx.Load($rootWeb)
      $ctx.ExecuteQuery()
    
      # Determine the user account of the authenticated user
      $currentUser = $ctx.web.CurrentUser
      $ctx.load($CurrentUser)
      $ctx.ExecuteQuery()
      $userAccount = $currentuser.LoginName
    
      # Get the user Object
      $searchUser = $Web.EnsureUser($userAccount)
      $Ctx.Load($searchUser)
      $Ctx.ExecuteQuery()
    }catch{
      write-host -f Red "`t Error connecting to $($siteUrl)!" 
      write-host -f Red "`t --" 
      write-host -f Red "`t $($_.Exception.Message)"
      return
    }

    
    ########################################
    # Define variables
    ########################################
    
    # Define Date
    $date = ((Get-Date).ToShortDateString().Replace("/", "-"))
    
    # Define Audit report path
    $auditTitle = $ctx.web.title        
    $fileName = $auditTitle + "_" + $date + ".xlsx"
    $auditReportPath = $csvOutputPath + $fileName
    
    
    ########################################
    # Checking if user has access to list 
    ########################################
    
    If ($SearchUser.IsSiteAdmin -eq $True) {
      Write-host -f Cyan "Found the User under Site Collection Administrators Group!"
    }else{
      Write-host -f Red "`t User is not part of the Site Collection Administrators Group. Exiting!!"  
      Write-host -f Red "`t User will need to be added as a Site Collection Administrator before proceeding."
      Write-host -f Red "`t Please see the following for additional details - https://docs.microsoft.com/en-us/sharepoint/manage-site-collection-administrators"
      return
    }
    
    # try {
    #   Get-SPOWebAccess $Web
    #   Write-Host -ForegroundColor Green "`t Verified access to all libraries.  Beginging audit off library permissions"
    # }
    # catch {
    #   write-host -f Red "Error validating access to report!" $_.Exception.Message
    # }
    
    ########################################
    # Auditing permissions on Lists
    ########################################
    
    # Get a list of Lists from the site
    try {
      $lists = Get-SPOSiteLists -web $rootWeb
    }
    catch {
      Write-Verbose "Error occurred getting lists from Site $siteUrl"
    }
    
    # Iterate through each list to get the permissions needed for each list. 
    $sitePermissions = @()
    foreach ($list in $lists) {
      $listItemPermissions = Get-SPOListItems -list $list
      $sitePermissions += $listItemPermissions
    }
    
    ##$sitePermissions | ConvertTo-Csv -NoTypeInformation -ErrorAction SilentlyContinue | Out-File $auditReportPath
    return $sitePermissions
    #$sitePermissions | Export-Excel -Path $auditReportPath -WorksheetName "$webTitle"
  }
} 
    
    