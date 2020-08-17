
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
        $Expression = [System.Linq.Expressions.Expression]::Lambda([System.Linq.Expressions.Expression]::Convert([System.Linq.Expressions.Expression]::PropertyOrField($Parameter,$PropertyName),[System.Object] ), $($Parameter))
        $ExpressionArray = [System.Array]::CreateInstance($Expression.GetType(), 1)
        $ExpressionArray.SetValue($Expression, 0)
        $ClientLoad.Invoke($Ctx,@($Object,$ExpressionArray))
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
                if($itemType -eq "Folder"){
                    $item = $ctx.Web.GetFolderByServerRelativeUrl($relativeUrl)
                }Else{
                    $item= $ctx.Web.GetFileByServerRelativeUrl($relativeUrl)
                }
                $ctx.Load($item)
                $ctx.ExecuteQuery()

                #Get permissions assigned to the Folder
                $roleAssignments = $item.ListItemAllFields.RoleAssignments
                $ctx.Load($roleAssignments)
                $ctx.ExecuteQuery()

                #Loop through each permission assigned and extract details
                $permissionCollection = @()
                Foreach($roleAssignment in $roleAssignments)
                {
                    $ctx.Load($roleAssignment.Member)
                    $ctx.executeQuery()

                    #Get the User Type
                    $permissionType = $roleAssignment.Member.PrincipalType

                    #Get the Permission Levels assigned
                    $ctx.Load($roleAssignment.RoleDefinitionBindings)
                    $ctx.ExecuteQuery()
                    $permissionLevels = ($roleAssignment.RoleDefinitionBindings | Where {$_.name -ne "Limited Access"} | Select -ExpandProperty Name) -join ","
                    
                    #Get the User/Group Name
                    $name = $roleAssignment.Member.Title # $RoleAssignment.Member.LoginName

                    #Add the Data to Object
                    $permissions = New-Object PSObject
                    $permissions | Add-Member NoteProperty Name($name)
                    $permissions | Add-Member NoteProperty Type($permissionType)
                    $permissions | Add-Member NoteProperty PermissionLevels($permissionLevels)

                    if($permissions.PermissionLevels){
                        $permissionCollection += $permissions
                    }
                }
                Return $permissionCollection
            }
        } 

        Function Get-SPOListPermissions {
            [CmdletBinding()]
            param (
                [Parameter()]
                $list
            )

            Process {
                #Get permissions assigned to the Folder
                $roleAssignments = $list.RoleAssignments
                $ctx.Load($roleAssignments)
                $ctx.ExecuteQuery()

                #Loop through each permission assigned and extract details
                $permissionCollection = @()
                Foreach($roleAssignment in $roleAssignments)
                {
                    $ctx.Load($roleAssignment.Member)
                    $ctx.executeQuery()

                    #Get the User Type
                    $permissionType = $roleAssignment.Member.PrincipalType

                    #Get the Permission Levels assigned
                    $ctx.Load($roleAssignment.RoleDefinitionBindings)
                    $ctx.ExecuteQuery()
                    $permissionLevels = ($roleAssignment.RoleDefinitionBindings | Where {$_.name -ne "Limited Access"} | Select -ExpandProperty Name) -join ","
                    
                    #Get the User/Group Name
                    $name = $roleAssignment.Member.Title # $RoleAssignment.Member.LoginName

                    #Add the Data to Object
                    $permissions = New-Object PSObject
                    $permissions | Add-Member NoteProperty Name($name)
                    $permissions | Add-Member NoteProperty Type($permissionType)
                    $permissions | Add-Member NoteProperty PermissionLevels($permissionLevels)

                    if($permissions.PermissionLevels){
                        $permissionCollection += $permissions
                    }
                }
                Return $permissionCollection
            }
        } 

        Function Get-SPOListItems {
            [CmdletBinding()]
            param (
                [Parameter()]
                $list
            )

            process {
                #Check if the given site is using unique permissions
                $listPermissions = Get-SPOListPermissions -list $list


                $query = New-Object Microsoft.SharePoint.Client.CamlQuery
                $query.ViewXml = "<View Scope='RecursiveAll'><RowLimit>1000000</RowLimit></View>"
                $listItems = $list.GetItems($query)
                $listName  = $list.Title
                $ctx.Load($listItems)
                $ctx.ExecuteQuery()

                $dataCollection = @()
                Write-host -f Green "`t Auditing items in list '$listName'"

                $LibData = New-Object PSObject -Property ([Ordered] @{
                    site            = $list.ParentWebUrl
                    list            = $listName
                    itemName        = $null
                    itemType        = "List"
                    itemUniquePerms = $null
                    inheritedFrom   = $null
                    itemPermissions = $listPermissions
                    
                })
                $dataCollection += $libData

                foreach ($item in $listItems){
                    Invoke-LoadMethod -Object $item -PropertyName "HasUniqueRoleAssignments"
                    Invoke-LoadMethod -Object $item -PropertyName "FirstUniqueAncestorSecurableObject"
                    Invoke-LoadMethod -Object $item -PropertyName "ParentList"
                    $Ctx.ExecuteQuery()

                    $itemPath           = $item.fieldValues.FileRef
                    $itemName           = $item.fieldValues.FileLeafRef
                    $itemUniquePerms    = $item.HasUniqueRoleAssignments
                    $itemType           = $item.FileSystemObjectType
                    $site               = $item.ParentList.ParentWebUrl
                    $inheritedFrom      = $item.FirstUniqueAncestorSecurableObject.FieldValues.FileRef
                    

                    if ($itemUniquePerms) {
                        # write-output "`$itemPath = $itemPath"
                        $itemPermissions    = Get-SPOItemPermissions -relativeUrl $itemPath -itemType $itemType
                        $inheritedFrom      = $null
                    }elseif ($inheritedFrom) {
                        $itemPermissions    = $null
                        $inheritedFrom      = $inheritedFrom                
                    }else{
                        $itemPermissions    = $null
                        $inheritedFrom      = "Inherited from List"
                    }

                    $data = New-Object PSObject -Property ([Ordered] @{
                        site            = $site
                        list            = $listName
                        itemName        = $itemName
                        itemType        = $itemType
                        itemUniquePerms = $itemUniquePerms
                        inheritedFrom   = $inheritedFrom
                        itemPermissions = $itemPermissions
                        
                    })
                    $dataCollection += $data
                }
                return $dataCollection
            }
        }
        function Get-SPOSiteLists {
            [CmdletBinding()]
            param (
                [Parameter()]
                $web
            )
            process {
                ### Get unique permission in Lists
                Write-host -f Green "`t Getting lists from site"
                $lists =  $web.Lists
                $ctx.Load($lists)
                $ctx.ExecuteQuery()
            
                #Exclude system lists
                $excludedLists = @("App Packages","appdata","appfiles","Apps in Testing","Cache Profiles","Composed Looks","Content and Structure Reports","Content type publishing error log","Converted Forms",
                "Device Channels","Form Templates","fpdatasources","Get started with Apps for Office and SharePoint","List Template Gallery", "Long Running Operation Status","Maintenance Log Library", "Style Library",
                ,"Master Docs","Master Page Gallery","MicroFeed","NintexFormXml","Quick Deploy Items","Relationships List","Reusable Content","Search Config List", "Solution Gallery", "Site Collection Images",
                "Suggested Content Browser Locations","TaxonomyHiddenList","User Information List","Web Part Gallery","wfpub","wfsvc","Workflow History","Workflow Tasks", "Preservation Hold Library")

                $dataColleciton = @()
                ForEach($list in $lists)
                {
                    $ctx.Load($list)
                    $ctx.ExecuteQuery()
            
                    If($excludedLists -NotContains $list.Title -and $list.Hidden -eq $false){
                        # $data = $list
                        $dataColleciton += $list
                    }
                    
                }
                return $dataColleciton
            }
        }

        ########################################
        # Main Function
        ########################################

        #Load SharePoint CSOM Assemblies
        Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
        Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
              
        #Get Credentials to connect
        if($cred){
            # Creds provided when command launched. No need to prompt.
        }else{
            $cred = Get-Credential
        }

        #Setup the context
        $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($siteURL)
        $ctx.Credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($cred.UserName,$cred.Password)
            
        #Get the Web
        $web = $ctx.Web
        $ctx.Load($Web)
        $ctx.ExecuteQuery()

        # Get Role Definitions
        $roleDefs = $web.RoleDefinitions
        $ctx.Load($roleDefs)
        $ctx.ExecuteQuery()

        #Check if the given site is using unique permissions
        Invoke-LoadMethod -Object $web -PropertyName "HasUniqueRoleAssignments"
        $ctx.ExecuteQuery()
            
        #Get the Root Web
        $rootWeb = $ctx.site.RootWeb
        $ctx.Load($rootWeb)
        $ctx.ExecuteQuery()

        # ### Get unique permission in Lists
        # Write-host -f Yellow "`t Searching Unique Permissions on the Lists..."
        # $lists =  $RootWeb.Lists.GetByTitle("Documents")
        # $ctx.Load($lists)
        # $ctx.ExecuteQuery()

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

        return $sitePermissions
    }
} 

