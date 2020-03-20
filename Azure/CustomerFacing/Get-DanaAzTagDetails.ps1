# Files are pulled invididually from the API https://docs.microsoft.com/en-us/rest/api/resources/tags/list 
# and saved locally.  

function Get-AzTagDetails{
    [CmdletBinding()]
    param (
        [Parameter(
            mandatory=$false
        )]
        [object[]]$JSONFile
    )

    process{
        # Get the list of keys used in the sub.  
        $keys = $JSONFile.value.tagName

        # Get the details from each Key
        foreach ($key in $keys){
            # Format key value
            $formattedKey = "/" + $key + "/"

            # Get all key:value pairs for current key
            $keyValues = $JSONFile.value.values | Where-Object {$_.id -like "*$formattedKey*"}

            # Get all of the values for the current value
            foreach($value in $keyValues){
                $valueCount = $value.Count.Value
                $tagValue = $value.tagValue
                $subID = ($JSONFile.value.id).split("/")[2]

                switch ($subID)
                {
                    6d82e6fd-345f-4df1-87e5-365c3f5df266 {
                        $subName = "Microsoft Project"
                    }
                    35f2466b-fa56-421c-982f-665e82a087a7 {
                        $subName = "GLB-NA01-Prod"
                    }
                    89b37d31-0104-487b-bc4e-8bdcacf3a91d {
                        $subName = "GLB-NA01-NONPROD"
                    }
                    8d386e25-ff43-4075-a576-f29dcdf273d4 {
                        $subName = "GLB-NA01-DR"
                    }
                    fb7b5dac-e8c8-4b9a-9c41-9cd760a12a35 {
                        $subName = "GLB-NA02-SBX"
                    }
                    212505e9-ad5d-44fd-8ed1-9c93a3765163 {
                        $subName = "GLB-NA01-SBX2"
                    }
                    9c3faafa-03e9-4afe-b68f-8b3bcee8c6d7 {
                        $subName = "GLB-Network-Hub"
                    }
                    fd33e7f9-c36a-4074-a0ab-60d4340bbacb {
                        $subName = "Electrification-DevOps"
                    }
                }

                $props = [ordered]@{
                    Subscription    = $subName
                    Keys            = $key
                    Value           = $tagValue
                    Count           = $valueCount
                }

                New-Object -TypeName psobject -Property $props
            }
        }
    }
}

###################################
# Define Variables 
###################################

$folderPath = "/Users/joe.fecht/OneDrive - AHEAD/Ahead-Docs/CustDocs/Dana/TKT0010464"
$date = (Get-Date).ToShortDateString().Replace("/", "-")

# Get a list of files in the folder that contains the JSON files
$files = Get-ChildItem -Path $folderPath -filter *.json

foreach($file in $files){
    # Pull and format data from the individual file
    $fileData = Get-Content -path $file.FullName -Raw | ConvertFrom-Json

    # Gets Tags associated with clients
    $subTags = Get-AzTagDetails -JSONFile $fileData

    # Add tags from Sub to the overall Client tags
    $clientTags += $subTags
}

$outputFileName = $folderPath + "/Dana_Tags_" + $date + ".csv"
$clientTags | Convertto-Csv -notypeinformation | out-file -path $outputFileName -force