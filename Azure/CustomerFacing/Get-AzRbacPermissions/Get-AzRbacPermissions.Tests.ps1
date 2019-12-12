$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe 'Test-Export-RBACRoles' {

    $roleScope = "Test-Scope"
    $azSubName = "Test-Azure-Subscription"
    $role = [PSCustomObject]@{
        
        RoleAssignmentId   = '/subscriptions/8688fca6-f9ff-4c38-b2cb-b31972c4a1ad/providers/Microsoft.Authorization/roleAssignments/3c30ca0e-e99d-4ae4-837f-0e15161fc85a'
        Scope              = '/subscriptions/8688fca6-f9ff-4c38-b2cb-b31972c4a1ad'
        DisplayName        = 'Jason Bruno'
        SignInName         = 'jason.bruno@lab.aheadaviation.com'
        RoleDefinitionName = 'Owner'
        RoleDefinitionId   = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
        ObjectId           = '3074283f-2c83-4148-b084-fb3f7c2e09d9'
        ObjectType         = 'User'
        CanDelegate        = 'False'
    }
    
    it 'Confirm Role information is exported' {
        Export-RBACRoles -role $role -roleScope $roleScope -azSubName $azSubName | Should -Not -BeNullOrEmpty
    }

    it 'Confirm Role Export contains 7 items' {
        (Export-RBACRoles -role $role -roleScope $roleScope -azSubName $azSubName | Get-Member -MemberType NoteProperty).Count | Should -BeGreaterOrEqual 7
    }
}

Describe 'Test-Get-AzSubPermissions' { 
    
}