# BlobTrigger - PowerShell

The `BlobTrigger` makes it incredibly easy to react to new Blobs inside of [Azure Blob Storage](https://azure.microsoft.com/en-us/services/storage/blobs/).
This sample demonstrates a simple use case of processing data from a given Blob using PowerShell.

## How it works

For a `BlobTrigger` to work, you provide a path which dictates where the blobs are located inside your container, and can also help restrict the types of blobs you wish to return. For instance, you can set the path to `samples/{name}.png` to restrict the trigger to only the samples path and only blobs with ".png" at the end of their name.

## Learn more

<TODO> Documentation

### Outstanding items
[ ] Listen for changes to a storage blob and when a CSV file is updated it will execute  
[ ] It will read the contents of the CSV file and perform the following  
[ ] Validate the file has the correct headers (Record Name, Type, Address, TTL, etc...)  
[ ] Validate each of the records in the file is of the appropriate type (Name, Record type, RegEx for the IP address)  
[ ] If the file contents are valid it will then review each record in the file and compare it to the target DNS Zone  
[ ] If the record exists and the address matches. No change.  
[ ] If the record exists but the address is different. Update the address  
[ ] If the record doe not exist. Create record  

