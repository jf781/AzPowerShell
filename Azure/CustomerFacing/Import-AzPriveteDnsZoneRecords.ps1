function Import-AzPriveteDnsZoneRecords {
  [CmdletBinding()]
  param(    [Parameter(
      Mandatory = $true,
      ValueFromPipeline = $true
    )]
    [string]
    $CSVFile
  )
  process {
    #----------------------------------------------------------------------------------------
    # Utility Functions 
    #----------------------------------------------------------------------------------------
    function Get-CsvFile {
      [CmdLetBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [string]
        $File
      )
      process {
        try {
          if (Test-Path -Path $File) {
            $csvFile = Import-Csv -Path $File
            return $csvFile
          }
          Else {
            Write-Output "Failed to validate path to $csvFilePath"
          }
        }
        catch {
          Write-Verbose "Error getting CSV file"
          Write-Host "Error getting CSV file for path $csvFilePath" -ForegroundColor Red
          Write-Host "Error Msg: $_" -ForegroundColor Red
        }
      }
    }

    function Confirm-CsvRecords {
      [CmdletBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [PSCustomObject]
        $CSV
      )
      process {
        # Define pattern for matching DNS zone
        $dnsZonePattern = "[a-zA-Z]+\.[a-zA-Z]+"
        $dnsNumericPattern = "\d+"

        try {
          foreach ($record in $CSV) {
            # Validating Record Name field
            if ($record.Name) {
              Write-Verbose "Validated Name field is present for $record"
            }
            else {
              Write-Verbose "Missing Name field for $record"
              throw "Missing field 'Name' for $record"
            }

            # Validating Record Zone field
            if ($record.Domain) {
              Write-Verbose "Validated Domain field is present for $record"

              # Validate record zone is in the proper format
              if ($record.Domain -match $dnsZonePattern) {
                Write-Verbose "Validated Domain field is a valid dns zone name for $record"
              }
              else {
                Write-Verbose "Domain field is not a valid dns zone name for record $record"
                throw "Domain field is not a valid dns zone name for record $record"
              }
            }
            else {
              Write-Verbose "Missing Domain field for $record"
              throw "Missing field 'Domain' for $record"
            }

            # Validating Record Type field
            if ($record.recordType) {
              Write-Verbose "Validated recordType field is present for $record"
            }
            else {
              Write-Verbose "Missing recordType field for $record"
              throw "Missing field 'recordType' for $record"
            }

            # Validating Destination field
            if ($record.Destination) {
              Write-Verbose "Validated Destination field is present for $record"
      
              ## Validating A or AAAA record types
              if (($record.recordType -eq "a") -or ($record.recordType -eq "aaaa")) {
            
                # Validate Destination field is formatted as a proper IP Destination
                if ($record.Destination -as [IPAddress] -as [Bool]) {
                  Write-Verbose "Validated Destination field is a valid IP Address"
                }
                else {
                  Write-Verbose "Destination field is not a valid IP Address for record $record"
                  throw "Destination field is not a valid IP address for record $record"
                }
              }

              ## CNAME or NS
              elseif (($record.RecordType -eq "cname") -or ($record.RecordType -eq "ns")) {

                if ($record.Destination -match $dnsZonePattern) {
                  Write-Verbose "Validated Destination field is a CNAME or NS record"
                }
                else {
                  Write-Verbose "Destination field is not a valid CNAME or NS value for record $record"
                  throw "Destination field is not a valid CNAME or NS value for record $record"
                }
              }

              ## MX Records
              elseif ($record.RecordType -eq "mx") {
                # Validate Destination Value
                if (($record.Destination -match $dnsZonePattern) -or ($record.Destination -as [IPAddress] -as [Bool])) {
                  Write-Verbose "Validated Destination field is a MX record"
                }
                else {
                  Write-Verbose "Destination field is not a valid MX record for record $record"
                  throw "Destination field is not a valid MX value for record $record"
                }

                # Validate MX Preference Value
                if ($record.MxPreference -match $dnsNumericPattern) {
                  Write-Verbose "Validated MX Preference field is set"
                }
                else {
                  Write-Verbose "MX Preference field is not a valid for a MX record. Record: $record"
                  throw "MX Preference field is not a valid for a MX record. Record: $record"
                }
              }

              ## SRV Records
              elseif ($record.RecordType -eq "SRV") {
                # Validate MX Preference Value
                if (($record.SrvPriority -match $dnsNumericPattern) -and ($record.SrvWeight -match $dnsNumericPattern) -and ($record.SrvPort -match $dnsNumericPattern)) {
                  Write-Verbose "Validated SRV fields"
                }
                else {
                  Write-Verbose "One or more of the SRV fields is not a valid for a SRV record. Record: $record"
                  throw "One or more of the SRV fields is not a valid for a SRV record. Record: $record"
                }

              }

              ## HTTPRED Records
              elseif ($record.RecordType -eq "HTTPRD") {
                Write-Verbose "HTTPRED records not allowed"
                throw "HTTPRED Not a valid record type."
              }
              ## Not validating TXT or other record types

            }
            else {
              Write-Verbose "Missing Destination field for $record"
              throw "Missing field 'Destination' for $record"
            }

            # Validating TTL  field
            if ($record.ttl) {
              Write-Verbose "Validated TTL field is present for $record"

              # Validate TTL is in the proper format
              if ($record.ttl -match $dnsNumericPattern) {
                Write-Verbose "Validated TTL field is a valid dns zone name for $record"
              }
              else {
                Write-Verbose "TTL field is not a valid integer for record $record"
                throw "TTL field is not a valid integer for record $record"
              }
            }
            else {
              Write-Verbose "Missing TTL field for $record"
              throw "Missing field 'TTL' for $record"
            }
          }
        }
        catch {
          Write-Verbose "Error validating record $record."
          Write-Verbose "Error message: $PSItem.Exception.message"
          return $PSItem.Exception.message
        }
      }
    }

    function Confirm-DnsRecords {
      [CmdletBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [PSCustomObject]
        $dnsRecord
      )
      process {
        $zone = Get-AzPrivateDnsZone -Name $dnsRecord.Domain
        $zoneRecords = Get-AzPrivateDnsRecordSet -Zone $zone


        if ($zoneRecords.Name.Contains($dnsRecord.Name)) {
          Write-Debug "Existing record name exists in the DNS zone"
          $zoneIndex = $zoneRecords.Name.IndexOf($dnsRecord.Name)
          $zoneRecord = $zoneRecords[$zoneIndex]
      
          # Check if the existing record matches the IP address
          if (($zoneRecord.Records).IPv4Address -eq $dnsRecord.Destination) {
            Write-Debug "Existing record matches IP address in CSV file"
          }
          else {
            $zoneRecordOutput = $zoneRecord  | Select-Object Name, ZoneName, RecordType, Records, Ttl
            Write-Debug "Existing record's IP address is different"
            Write-Debug "Zone Record: $zoneRecordOutput"
            Write-Debug "File Record: $dnsRecord"
            return $false
          }

          # Check if the existinig record's type matches
          if ($zoneRecord.RecordType -eq $dnsRecord.recordType) {
            Write-Debug "Existing record matches record type in CSV file"
          }
          else {
            $zoneRecordOutput = $zoneRecord  | Select-Object Name, ZoneName, RecordType, Records, Ttl
            Write-Debug "Existing record's type is different"
            Write-Debug "Zone Record: $zoneRecordOutput"
            Write-Debug "File Record: $dnsRecord"
            return $false
          }

          # Check if the existinig record's TTL matches
          if ($zoneRecord.Ttl -eq $dnsRecord.ttl) {
            Write-Debug "Existing record matches TTL set in CSV file"
            return $true
          }
          else {
            $zoneRecordOutput = $zoneRecord  | Select-Object Name, ZoneName, RecordType, Records, Ttl
            Write-Debug "Existing record's TTL is different"
            Write-Debug "Zone Record: $zoneRecordOutput"
            Write-Debug "File Record: $dnsRecord"
            return $false
          }
        }
        else {
          $zoneRecordOutput = $zoneRecord  | Select-Object Name, ZoneName, RecordType, Records, Ttl
          Write-Debug "Record does not exist in DNS zone.  $zoneRecordOutput"
          Write-Debug "File Record: $dnsRecord"
          return $false
        }
      }
    }

    function New-PrivateZoneDnsRecords {
      [CmdletBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [PSCustomObject]
        $csvFile
      )
      process {
        $zones = $csvFile | Group-Object -Property Domain
    
        foreach ($zone in $zones) {
          Write-Verbose "Reviewing records for zone $zone.Name"
          $zoneRecords = $csvFile | Where-Object -Property Domain -eq $zone.Name
          $dnsZone = Get-AzPrivateDnsZone | Where-Object -Property Name -EQ $zone.Name

          $multipleRecords = $zoneRecords |
          Group-Object -Property Name |
          Where-Object -Property Count -gt 1

          $singleRecords = $zoneRecords |
          Group-Object -Property Name |
          Where-Object -Property Count -eq 1

          foreach ($multipleRecord in $multipleRecords) {
            $recordsType = $multipleRecord.Group.recordType | Select-Object -First 1
            if ($recordsType -ne "NS") {
              $dnsRecordConfig = @()
              $recordsName = $multipleRecord.Group.Name |  Select-Object -First 1
              Write-Verbose "Reviewing all entries with $recordsName"

              $records = $csvFile | Where-Object { ($_.Name -eq $recordsName) -and ($_.Domain -eq $zone.Name) -and ($_.recordType -eq $recordsType) }
              ForEach ($record in $records) {
                try {
                  Write-Verbose "Defining DNS Config for $record"
                  $dnsRecordConfig += New-DnsRecordConfig -DnsRecord $record -DnsZone $dnsZone
                }
                catch {
                  Write-Verbose "Error adding DNS record config for $record"
                  Write-Host "Error adding DNS config for $record" -ForegroundColor Red
                  Write-Host "Error Msg: $_" -ForegroundColor Red
                  break
                }
              }
              try {
                $record = $records | Select-Object -First 1
                New-AzPrivateDnsRecordSet -ErrorAction Stop`
                  -Name $record.Name `
                  -ZoneName $record.Domain`
                  -ResourceGroupName $DnsZone.ResourceGroupName `
                  -RecordType $record.recordType `
                  -TTL $record.ttl `
                  -PrivateDnsRecord $dnsRecordConfig | Out-Null
              }
              catch {
                Write-Verbose "Error adding DNS record to Azure."
                Write-Host "Error adding record to DNS Zone $zone.Name.  $record" -ForegroundColor Red
                Write-Host "Error Msg: $_" -ForegroundColor Red
                break
              }
            }else{
              Write-Verbose "Record is a Name Server and cannot be hosted in an Azure Private DNS zone"
            }
          }

          foreach ($singleRecord in $singleRecords) {
            if ($singleRecord.Group.recordType -ne "NS") {
              try {
                $dnsRecordConfig = @()
                $dnsRecordConfig = New-DnsRecordConfig -DnsRecord $singleRecord.Group -DnsZone $dnsZone
                Write-Verbose "Setting record for $records for $dnsRecord"
                Write-Verbose "In for loop for single"
                New-AzPrivateDnsRecordSet -ErrorAction Stop `
                  -Name $singleRecord.Group.Name `
                  -ZoneName $singleRecord.Group.Domain`
                  -ResourceGroupName $DnsZone.ResourceGroupName `
                  -RecordType $singleRecord.Group.recordType `
                  -TTL $singleRecord.Group.ttl `
                  -PrivateDnsRecord $dnsRecordConfig | Out-Null
              }
              catch {
                Write-Verbose "Error validating adding DNS record to Azure."
                Write-Host "Error adding record to DNS Zone $zone.Name.  $singleRecord.Group" -ForegroundColor Red
                Write-Host "Error Msg: $_" -ForegroundColor Red
                break
              }
            }else {
              Write-Verbose "Record is a Name Server and cannot be hosted in an Azure Private DNS zone"
            }
          }
        }
      }
    }

    function New-DnsRecordConfig {
      [CmdletBinding()]
      param(
        [Parameter(
          Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [PSCustomObject]
        $DnsRecord,
        [Parameter(`
            Mandatory = $true,
          ValueFromPipeline = $true
        )]
        [PSCustomObject]
        $DnsZone
      )
      process {
        $recordConfig = @()
        switch ($dnsRecord.RecordType) {
          A {
            Write-Verbose "Record type is an A record"
            $recordConfig += New-AzPrivateDnsRecordConfig -Ipv4Address $dnsRecord.Destination
          }

          AAAA {
            Write-Verbose "Record type is an AAAA record"
            $recordConfig += New-AzPrivateDnsRecordConfig -Ipv6Address $dnsRecord.Destination
          }

          CNAME {
            Write-Verbose "Record type is a CNAME record"
            $recordConfig += New-AzPrivateDnsRecordConfig -Cname $dnsRecord.Destination
          }

          MX {
            Write-Verbose "Record type is a MX record"
            $recordConfig += New-AzPrivateDnsRecordConfig `
              -Exchange $dnsRecord.Destination `
              -Preference $dnsRecord.MxPreference
          }

          PTR {
            Write-Verbose "Record type is a PTR record"
            $recordConfig += New-AzPrivateDnsRecordConfig -Ptrdname $dnsRecord.Destination
          }

          TXT {
            Write-Verbose "Record type is a TXT record"
            $recordConfig += New-AzPrivateDnsRecordConfig -Value $dnsRecord.Destination
          }

          SRV {
            Write-Verbose "Record type is a SRV record"
            $recordConfig += New-AzPrivateDnsRecordConfig `
              -Priority $dnsRecord.SrvPriority `
              -Target $dnsRecord.Destination `
              -Port $dnsRecord.SrvPort `
              -Weight $dnsRecord.SrvWeight
          }
        }

        return $recordConfig
      }
    }


    #----------------------------------------------------------------------------------------
    # Main Function
    #----------------------------------------------------------------------------------------
    $csv = Get-CsvFile -File $CSVFile
    Write-Verbose "Validated CSV file exists and imported file"

    $validCsvFile = Confirm-CsvRecords -CSV $csv
    Write-Verbose "Checked CSV file to ensure it has valid records.  Results:  $validCsvFile"
    
    if ($validCsvFile -eq $null) {
      Write-Verbose "Records in CSV are valid DNS records"
    }else {
      write-verbose "One or more reecords are not properly formatted and cannot be imported into DNS"
      return $validCsvFile
    }

    New-PrivateZoneDnsRecords -csvFile $csv
  
  }
}