<#
.SYNOPSIS
This PowerShell script modifies registry settings in the `NTUSER.DAT` file of the Default User to customize system behavior for newly created user accounts.

.DESCRIPTION
The script performs the following steps:
1. Loads the `NTUSER.DAT` registry hive for the Default User under a temporary registry key.
2. Modifies or creates registry keys and values to apply custom settings, such as disabling Windows Copilot, changing wallpaper settings, and taskbar customization.
3. Saves the changes back to the hive and unloads it cleanly from the system.

.PARAMETER defaultUserHivePath
Specifies the path to the `NTUSER.DAT` file of the Default User. By default, this path is set to `C:\Users\Default\NTUSER.DAT`.

.NOTES
- Ensure that the script is executed with administrative privileges.
- Any existing mappings for the specified registry drive will be removed before loading the hive.
- The changes made by this script will only apply to new user accounts created after these modifications.

.REQUIREMENTS
- PowerShell 5.0 or later
- Administrative privileges

.AUTHOR
Nolan Nash for TECHsperience

.LICENSE
This script is provided "as is" without warranty of any kind.
#>
# Function to Import Registry Hive
Function Import-RegistryHive {
  [CmdletBinding()]
  Param(
    [String][Parameter(Mandatory = $true)]$File,
    [String][Parameter(Mandatory = $true)][ValidatePattern('^(HKLM\\|HKCU\\|HKU\\)[a-zA-Z0-9- _\\]+$')]$Key,
    [String][Parameter(Mandatory = $true)][ValidatePattern('^[^;~/\\\.\:]+$')]$Name
  )

  # Check if the drive name is already in use (if yes, means it is hanging from previous )
  $TestDrive = Get-PSDrive -Name $Name -ErrorAction SilentlyContinue
  if ($null -ne $TestDrive) {
    Write-Host "Drive '$Name' already exists. Removing it..." -ForegroundColor Yellow
    Remove-PSDrive -Name $Name -Force
  }

  # Attempt to load the registry hive
  $Process = Start-Process -FilePath "$env:WINDIR\System32\reg.exe" -ArgumentList "load $Key ""$File""" -NoNewWindow -PassThru -Wait
  if ($Process.ExitCode -ne 0) {
    throw "Failed to load registry hive '$File'. Exit code: $($Process.ExitCode). Check file path or permissions."
  }

  # Create a PowerShell drive for the loaded hive
  try {
    New-PSDrive -Name $Name -PSProvider Registry -Root $Key -Scope Global | Out-Null
  }
  catch {
    throw "Failed to create PSDrive '$Name'. Check if the registry hive is loaded correctly."
  }
}

# Function to Remove Registry Hive
Function Remove-RegistryHive {
  <#
  .SYNOPSIS
  Unloads a registry hive and removes its associated PowerShell drive.

  .DESCRIPTION
  This function uses `reg.exe` to unload a previously loaded registry hive and removes 
  its mapping from the PowerShell session.

  .PARAMETER Name
  The name of the PowerShell drive associated with the registry hive.
  #>

  [CmdletBinding()]
  Param(
    [String][Parameter(Mandatory = $true)][ValidatePattern('^[^;~/\\\.\:]+$')]$Name
  )

  # Retrieve PSDrive info
  $Drive = Get-PSDrive -Name $Name -ErrorAction Stop
  $Key = $Drive.Root

  # Remove the drive
  Remove-PSDrive -Name $Name -Force

  # Attempt to unload the hive
  $Process = Start-Process -FilePath "$env:WINDIR\System32\reg.exe" -ArgumentList "unload $Key" -NoNewWindow -PassThru -Wait
  if ($Process.ExitCode -ne 0) {
    throw "Failed to unload registry hive '$Key'. Exit code: $($Process.ExitCode)."
  }
}

# Main Script
$defaultUserHivePath = 'C:\Users\Default\NTUSER.DAT'
if (-Not (Test-Path $defaultUserHivePath)) {
  throw "The specified NTUSER.DAT file does not exist: $defaultUserHivePath"
}

try {
  Write-Host "Starting registry import..." -ForegroundColor Cyan

  # Load the default user hive
  Import-RegistryHive -File $defaultUserHivePath -Key 'HKU\TEMP_HIVE' -Name TempHive

  # Customize registry settings
  $settings = @(
    #removal and prevention of copilot keys
    @{ Path = "Policies\Microsoft\Windows\WindowsCopilot"; Properties = @{ "TurnOffWindowsCopilot" = 1 } }
    @{ Path = "Microsoft\Windows\Shell\Copilot"; Properties = @{ "IsCopilotAvailable" = 0 } }
    @{ Path = "Microsoft\Windows\CurrentVersion\WindowsCopilot"; Properties = @{ "AllowCopilotRuntime" = 0 } }
    ##disables copilot in the start and search menus
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Properties = @{ "ShowCopilotButton" = 0 } }

    #control desktop/wallpaper stuff (color doesn't work yet)
    @{ Path = "Control Panel\Desktop"; Properties = @{ "Wallpaper" = ""; "WallpaperStyle" = "2"; "TileWallpaper" = "0" } }
    @{ Path = "Control Panel\Colors"; Properties = @{ "Background" = "255 0 0" } }  # Correct RGB string format

    #taskbar customization
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Properties = @{ "TaskbarAl" = 0 } }
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Search"; Properties = @{ "SearchboxTaskbarMode" = 1 } }
  )

  # Apply the registry settings
  foreach ($setting in $settings) {
    $fullPath = "TempHive:\SOFTWARE\$($setting.Path)"
    if (-Not (Test-Path $fullPath)) {
      New-Item -Path $fullPath -Force | Out-Null
    }

    foreach ($property in $setting.Properties.Keys) {
      $value = $setting.Properties[$property]
      $propertyType = if ($value -is [int]) { 'DWORD' } else { 'String' }
      New-ItemProperty -Path $fullPath -Name $property -Value $value -PropertyType $propertyType -Force | Out-Null
    }
  }

  Write-Host "Registry modifications completed." -ForegroundColor Green

  # Sleep before unloading the hive
  Write-Host "Waiting for 60 seconds before unloading the registry hive..." -ForegroundColor Yellow
  for ($i = 60; $i -ge 1; $i--) {
    Write-Host "Time remaining: $i seconds" -NoNewline
    Start-Sleep -Seconds 1
    Write-Host " `r" -NoNewline
  }
  Write-Host "Proceeding to unload the registry hive..." -ForegroundColor Cyan

  # Unload the hive
  Remove-RegistryHive -Name TempHive

}
catch {
  Write-Error "An error occurred: $_"
  exit 1
}