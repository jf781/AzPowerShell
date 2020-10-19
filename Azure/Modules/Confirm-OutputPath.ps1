    function Confirm-OutputPath {
      <#
  .SYNOPSIS
      This will check to see what OS the script is being ran from and ensure that output path is formatted properly and that
      the path will have a trailing slash (either forward or backward depending on the OS)   
  .DESCRIPTION
      This script does not install or make any changes.  It checks to ensure that the path is valid and is formatted properly
      for the OS
  .INPUTS
      path
  .OUTPUTS
      It will output a validated OutputPath variable formatted properly for the OS it is running on

  .NOTES
      Version:        1.0
      Author:         Joe Fecht - AHEAD, llc.
      Creation Date:  December 2019
      Purpose/Change: Initial deployment

  .EXAMPLE
      Confirm-OutputPath -path ~/Documents

      If running on Linux/MacOS it will output a value that shows the current users home directly.   

      /Users/joe/Documents/

      .EXAMPLE
      Confirm-OutputPath -path ~\Documents

      If running on Linux/MacOS it will output a value that shows the current users home directly.   

      C:\Users\joe\Documents\

  #>
      [CmdletBinding()]
      Param(
        [Parameter(
          Mandatory = $true)]
        [string]
        $path
      )

      process {
        # Confirm output path is valid
        try {
          if (Test-Path $path) {
            Write-Verbose "Output path is valid"
          }
          else {
            write-verbose "Output path is invalid"
            Write-Host "Output Path is not valid" -ForegroundColor red
            Write-Host "Output Path set to: $path" -ForegroundColor Red
            Write-Host "Please run execute command again with a valid output path" -ForegroundColor Red
            return $false
          }          
        }
        catch {
          Write-Verbose "Failed to validate Output Path"
          Write-Host "Unable to validate Output Path: $path" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return $false
        }

        # Ensure output path has a trailing path separator
        try {
          if ($env:HOME) {
            Write-Verbose "Running in a non-windows environment.  Path seperator is '/'"
            if ($path.endsWith("/")) {
              Write-Verbose "Output path ends with a trailing path separator"
              return $path
            }
            else {
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $path + "/"
              return $updatedOutputPath
            }
          }
          else {
            Write-Verbose "Running in a Windows environment.  Path seperator is '\'"
            if ($path.endsWith("\")) {
              Write-Verbose "Output path ends with a trailing path separator"
              return $path
            }
            else {
              Write-Verbose "Output path does NOT end with a trailing path separator"
              $updatedOutputPath = $path + "\"
              return $updatedOutputPath
            }
          }
        }
        catch {
          Write-Verbose "Failed to determine if the output path had a trailing path seperator"
          Write-Host "Unable to validate trailing path seperator for Output Path: $path" -ForegroundColor red
          Write-Host "Error Msg: $_" -ForegroundColor Red
          return $false
        }
      }
    }