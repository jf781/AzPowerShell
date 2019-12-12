#### Get-AzRbacPermissions - Get permissions applied to Azure Environments

This will run through all Azure subscriptions associated with a tenant and detremine which permissions have been applied to items below:

- Resource Groups
- Subscriptions
- Management Groups

It does require the following into to successfully complete.  It will prompt you if any item is missing

- PowerShell 5.1 or newer
- Modules
    - Az.Accounts
    - Az.Resources

To execute, download the and run the file.  It will confirm the requirements above are met and will then check for access to an Azure subscription.  If the user is not authenticated with Azure it will start the login process. 

Once it completes it will save the results to a CSV on the current user's desktop.  