
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
    $outputPath,
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
        [Microsoft.SharePoint.Client.ClientObject]$object = $(throw "Please provide a Client Object"), [string]$PropertyName
      )
      $ctx = $object.Context
      $Load = [Microsoft.SharePoint.Client.ClientContext].GetMethod("Load")
      $Type = $object.GetType()
      $ClientLoad = $Load.MakeGenericMethod($Type)
                
      $Parameter = [System.Linq.Expressions.Expression]::Parameter(($Type), $Type.Name)
      $Expression = [System.Linq.Expressions.Expression]::Lambda([System.Linq.Expressions.Expression]::Convert([System.Linq.Expressions.Expression]::PropertyOrField($Parameter, $PropertyName), [System.Object] ), $($Parameter))
      $ExpressionArray = [System.Array]::CreateInstance($Expression.GetType(), 1)
      $ExpressionArray.SetValue($Expression, 0)
      $ClientLoad.Invoke($ctx, @($object, $ExpressionArray))
    }
    
    function Test-CSVPath {
      [CmdletBinding()]
      param (
        [Parameter()]
        [string]
        $csvPath
      )
      process {
        write-verbose "In Test-CSVPath Fx"
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

    Function Get-SPOPermissions {
      [CmdletBinding()]
      param (
        [Parameter()]
        [Microsoft.SharePoint.Client.SecurableObject]
        $object
      )
      process {
        write-verbose "In Get-SPOPermissions Fx"
        #Determine the type of the object
        Switch($object.TypedObject.ToString())
        {
          "Microsoft.SharePoint.Client.Web"  { $objectType = "Site" ; $objectURL = $object.URL; 
          $objectTitle = $object.Title }
          "Microsoft.SharePoint.Client.ListItem"
          { 
            If($object.FileSystemObjectType -eq "Folder")
            {
              write-verbose "$($object.Title) is a folder"
              $objectType = "Folder"
              #Get the URL of the Folder
              Invoke-LoadMethod -Object $object -PropertyName "Folder"
              $ctx.ExecuteQuery()
              $objectTitle = $object.Folder.Name
              $objectURL = $("{0}{1}" -f $ctx.Web.Url.Replace($ctx.Web.ServerRelativeUrl,''), $object.Folder.ServerRelativeUrl)
            }
            Else #File or List Item
            {
              #Get the URL of the Object
              Invoke-LoadMethod -Object $object -PropertyName "File"
              $ctx.ExecuteQuery()
              If($object.File.Name -ne $Null)
              {
                write-verbose "$($object.File.Name) is a file"
                $objectType = "File"
                $objectTitle = $object.File.Name
                $objectURL = $("{0}{1}" -f $ctx.Web.Url.Replace($ctx.Web.ServerRelativeUrl,''), $object.File.ServerRelativeUrl)
              }
              else
              {
                $ObjectType = "List Item"
                $objectTitle = $object["Title"]
                #Get the URL of the List Item
                write-verbose "$($object["Titie"]) is a folder"
                Invoke-LoadMethod -Object $object.ParentList -PropertyName "DefaultDisplayFormUrl"
                $ctx.ExecuteQuery()
                $defaultDisplayFormUrl = $object.ParentList.DefaultDisplayFormUrl
                $objectURL = $("{0}{1}?ID={2}" -f $ctx.Web.Url.Replace($ctx.Web.ServerRelativeUrl,''), $defaultDisplayFormUrl,$object.ID)
              }
            }
          }
          Default 
          { 
            $objectType = "List or Library"
            $objectTitle = $object.Title
            #Get the URL of the List or Library
            write-verbose "$($object.Title) is a List"
            $ctx.Load($object.RootFolder)
            $ctx.ExecuteQuery()            
            $objectURL = $("{0}{1}" -f $ctx.Web.Url.Replace($ctx.Web.ServerRelativeUrl,''), $object.RootFolder.ServerRelativeUrl)
          }
        }

        #Get permissions assigned to the Folder
        Write-Verbose "Loading role assignments for the $objectTitle."
        $roleAssignments = $object.RoleAssignments
        $ctx.Load($roleAssignments)
        $ctx.ExecuteQuery()
    
        #Loop through each permission assigned and extract details
        Foreach ($roleAssignment in $roleAssignments) {
          $ctx.Load($roleAssignment.Member)
          $ctx.executeQuery()
          Write-Verbose "Loaded $RoleAssignment"
    
          #Get the User Type
          $permissionType = $roleAssignment.Member.PrincipalType
          Write-Verbose "Permission Type = $permissionType"
    
          #Get the Permission Levels assigned
          $ctx.Load($roleAssignment.RoleDefinitionBindings)
          $ctx.ExecuteQuery()
          $permissionLevels = ($roleAssignment.RoleDefinitionBindings | Where-Object { $_.name -ne "Limited Access" } | Select-Object -ExpandProperty Name) -join ","
          Write-Verbose "Permission levels = $permissionLevels"
                        
          #Get the User/Group Name
          $name = $roleAssignment.Member.Title # $RoleAssignment.Member.LoginName
          Write-Verbose "User/Group name is $Name"
    
          if ($permissionLevels) {
            Write-Verbose "Adding Permissions to Object"
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
        $list,
        [Parameter()]
        [Microsoft.SharePoint.Client.Web]
        $web
      )
      process {
        write-verbose "In Get-SPOListItems Fx"
        Write-Verbose "Getting permissions on $($list.title)"
        $listPermissions = Get-SPOPermissions -Object $list
            
        $query = New-Object Microsoft.SharePoint.Client.CamlQuery
        $query.ViewXml = "<View Scope='RecursiveAll'><RowLimit>1000000</RowLimit></View>"
        $listItems = $list.GetItems($query)
        $listName = $list.Title
        $listPath = $list.ParentWebUrl
        $listFullPath = $listPath + "/" + $listName
        $ctx.Load($listItems)
        $ctx.ExecuteQuery()
        Write-Verbose "Getting items from $($list)."
            
        Write-host -f Green "`t Auditing items in list '$listName'"
            
        New-Object PSObject -Property ([Ordered] @{
            site            = $list.ParentWebUrl
            list            = $listName
            itemName        = $null
            itemFullPath    = $listFullPath
            itemType        = "List"
            itemUniquePerms = $null
            inheritedFrom   = $null
            itemPermissions = ($listPermissions | Out-String).Trim()
                        
          })

        Write-Verbose "Added permissions for List $($list.title) to output"
            
        foreach ($item in $listItems) {
          Invoke-LoadMethod -Object $item -PropertyName "HasUniqueRoleAssignments"
          Invoke-LoadMethod -Object $item -PropertyName "FirstUniqueAncestorSecurableObject"
          Invoke-LoadMethod -Object $item -PropertyName "ParentList"
          $ctx.ExecuteQuery()
          Write-Verbose "Reviewing $($item.fieldValues.FileRef) in $($list.title)."
          
          $itemName         = $item.fieldValues.FileLeafRef
          $itemFullPath     = $item.fieldValues.FileRef
          $itemUniquePerms  = $item.HasUniqueRoleAssignments
          $itemType         = $item.FileSystemObjectType
          $site             = $item.ParentList.ParentWebUrl
          $inheritedFrom    = $item.FirstUniqueAncestorSecurableObject.FieldValues.FileRef
                        
            
          if ($itemUniquePerms) {
            Write-verbose "$($item.fieldValues.FileRef) has unique permissions"
            $itemPermissions = Get-SPOPermissions -Object $item
            $inheritedFrom = $null
          }
          elseif ($inheritedFrom) {
            Write-verbose "$($item.fieldValues.FileRef) is inheriting it's permission from another object in the list"
            $itemPermissions = $null
            $inheritedFrom = $inheritedFrom
          }
          else {
            Write-verbose "$($item.fieldValues.FileRef) is inheriting it's permission from the list"
            $itemPermissions = $null
            $inheritedFrom = "Inherited from List"
          }
            
          New-Object PSObject -Property ([Ordered] @{
              site            = $site
              list            = $listName
              itemName        = $itemName
              itemFullPath    = $itemFullPath
              itemType        = $itemType
              itemUniquePerms = $itemUniquePerms
              inheritedFrom   = $inheritedFrom
              itemPermissions = ($itemPermissions | Out-String).Trim()
            })

          Write-Verbose "Added permissions for $($itemName) to output" 
          $counter++
          Write-Progress -PercentComplete ($counter / ($list.ItemCount) * 100) -Activity "Processing Items: $counter of $($list.ItemCount)" -Status "Searching Unique Permissions in List Items of '$($list.Title)'"
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
        write-verbose "In Get-SPOSiteLists Fx"
        ### Get unique permission in Lists
        Write-host -f Green "`t Getting lists from site $($web.title)"
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
          Write-Verbose "Reviewing $($list.title)"
          $ctx.Load($list)
          $ctx.ExecuteQuery()
          Write-Verbose "Loaded items for $($list.title)"
                
          If ($excludedLists -NotContains $list.Title -and $list.Hidden -eq $false) {
            # $data = $list
            Write-Verbose "$($List.title) is not excluded, will be auditing item permissions."
            $dataColleciton += $list
          }
          else {
            Write-Verbose "$($List.title) is excluded." 
          }
        }
        return $dataColleciton
      }
    }
    
    #Function to Check Webs's Permissions from given URL
    Function Get-SPOWebs {
      [CmdletBinding()]
      param (
        [Parameter()]
        [Microsoft.SharePoint.Client.Web]
        $web
      )
      process {
        write-verbose "In Get-SPOWebs Fx"
        # Clear Site Lists Variable
        $siteLists = $null
        Write-Verbose "`$siteLists cleared"

        #Get all immediate subsites of the site
        $ctx.Load($web.Webs) 
        $ctx.executeQuery()
        Write-Verbose "Loaded subsites for $($web.title)"
        
        #Get list of lists within the web
        Write-host -f Green "`tSearching for Lists and Libraries in "$web.URL"..."
        $siteLists = Get-SPOSiteLists -web $Web
        foreach ($list in $siteLists) {
          Write-Verbose "Reviewing list: $($list.Title)"
          $Global:listPermissions += Get-SPOListItems -list $list -Web $web
        }
        
        #Iterate through each subsite in the current web
        Foreach ($subweb in $web.Webs) {
          #Call the function recursively  
          Write-Verbose "Calling Get-SPOWebs for site $($subWeb.title)"
          Get-SPOWebs -web $subWeb
        }
        return $Global:listPermissions
      }
    }
  
    
    ########################################
    # Main Function
    ########################################
    
    #Load SharePoint CSOM Assemblies
    try{
      Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
      Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
    }catch{
      Write-host -f Red "`t It appears the SharePoint CSOM assemblies are not installed. Exiting!!"  
      Write-host -f Red "`t Please download and install the assemblies from - https://www.microsoft.com/en-us/download/details.aspx?id=42038."
      return
    }
            
    # Test CSV path
    Test-CSVPath -csvPath $outputPath
            
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
      $ctx.Load($web)
      $ctx.ExecuteQuery()
    }catch{
      Write-host -f Red "`t User is not part of the Site Collection Administrators Group. Exiting!!"  
      Write-host -f Red "`t User will need to be added as a Site Collection Administrator before proceeding."
      Write-host -f Red "`t Please see the following for additional details - https://docs.microsoft.com/en-us/sharepoint/manage-site-collection-administrators"
      return
    }
    try{
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

      # Get the sub sites

      $ctx.Load($web.Webs) 
      $ctx.executeQuery()
    
      # Determine the user account of the authenticated user
      $currentUser = $ctx.web.CurrentUser
      $ctx.load($CurrentUser)
      $ctx.ExecuteQuery()
      $userAccount = $currentuser.LoginName
    
      # Get the user Object
      $searchUser = $web.EnsureUser($userAccount)
      $ctx.Load($searchUser)
      $ctx.ExecuteQuery()
    }
    catch {
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
    $formatedPath = ($outputPath).replace("\\\W", "")
    $auditReportPath = $formatedPath + "\" + $fileName
    
    
    ########################################
    # Checking if user has access to list 
    ########################################
    
    If ($SearchUser.IsSiteAdmin -eq $True) {
      Write-host -f Cyan "Found the User under Site Collection Administrators Group!"
    }
    
    ########################################
    # Auditing permissions on Lists
    ########################################
    
    # Get a list of Lists from the site 
    $Global:listPermissions = @()
    try {
      $Global:listPermissions = Get-SPoWebs -web $rootWeb
    }
    catch {
      Write-Verbose "Error occurred getting lists from Site $siteUrl"
      write-host -f Red "`t Error Auditing to $($siteUrl)!" 
      write-host -f Red "`t --" 
      write-host -f Red "`t $($_.Exception.Message)"
    }
    
    try{
      $listCount = $Global:listPermissions | measure-Object | Select-object -ExpandProperty Count
      $Global:listPermissions | Select-Object -first $listCount | Export-Excel -Path $auditReportPath -WorksheetName "$auditTitle"
    }catch{
      Write-Verbose "Error occurred getting lists from Site $siteUrl"
      write-host -f Red "`t Error occurred writting to $($auditReportPath)!" 
      write-host -f Red "`t --" 
      write-host -f Red "`t $($_.Exception.Message)"
    }
  }
} 