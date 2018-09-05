#Requires -Version 4.0
#Requires -RunAsAdministrator
Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1' -Force -ErrorAction Stop
# GitHub Version
# Author: Klaus Steinhauer
# Version: 0.4.2
# Chagelog: Fix some bugs

## Hardcoded Vars
$SourcePath = "\\YOUR\ISO\SOURCE\FOLDER"
$Branch = "CB" # will probably be removed in the future.
$User = "DOM\USERNAME"
$Cred = "PASSWORD"
$ExtractPath = "\\YOUR\SCCM\Destination"
$SiteCode = "CMG"
$InstallTSID = "CMG00002" # Your AIO Install TS
$UpgradeTSID = "CMG00002" # Your AIO Upgrade TS

Set-Location C:

# Mount Target Directories.
net use $ExtractPath $Cred /USER:$User
net use $SourcePath $Cred /USER:$User

Get-Childitem $SourcePath\*.iso | ForEach-Object{
    Write-Output "Found ISO: $_.Name"
    $Basename = $_.Name

    # Get the Version, Architecture, Language and Full desired name.
    $Version = $Basename.Split("_")[8].Insert(2,".")
    $Arch = @{$true = 'x86'; $false = 'x64' }[$Basename.Split("_")[9].Split("BIT")[0] -eq "32"]
    $Lang = @{$true = 'EN'; $false = 'DE' }[$Basename.Split("_")[10] -eq "English"]
    $Name = "Windows10_"+$Version+"_"+$Branch+"_"+$Arch+"_"+$Lang
    $CMTsStepName = "$Branch $Arch $Lang"

    # Create Target Extract Folder
    New-Item -ItemType directory -Force -Path $ExtractPath\$Name | Out-Null
    # Mount and get Driveletter
    $source = (Get-Volume -DiskImage (Mount-DiskImage -PassThru -ImagePath $_ -ErrorAction Stop)).DriveLetter + ":\"

    Write-Output "Beginning to copy files from ISO."
    # Copy Files
    Get-ChildItem -Path $source | Copy-Item -Destination $ExtractPath\$Name -Recurse -Force
    Write-Output "Finished copying files."

    # Dismount Image
    Dismount-DiskImage -ImagePath $_.FullName

    # Switch to CFGMGr Drive
    If((Get-Location).Drive.Name -ne $SiteCode){
            Try{Set-Location -path $SiteCode":" -ErrorAction Stop}
            Catch{Throw "Unable to connect to Site $SiteCode. Ensure that the Site Code is correct and that you have access."}
          }
    # Import Image into SCCM
    Write-Output "Importing and enabling new Operating System Image"
    New-CMOperatingSystemImage -Name $Name -Path $ExtractPath\$Name\sources\install.wim -Version 1.0 -Description $Name -ErrorAction STOP | Out-Null
    $CMOperatingSystemImagePackage = (Get-CMOperatingSystemImage -Name $Name)

    # Replace corresponding TS Step.
    Set-CMTSStepApplyOperatingSystem -TaskSequenceId $InstallTSID  -StepName $CMTsStepName -ImagePackage $CMOperatingSystemImagePackage -ImagePackageIndex 3 -DestinationVariable "OSDrive" -ErrorAction Stop

    # Add OS Upgrade Package to SCCM
    Write-Output "Importing and enabling new Operating System Upgrade Package"
    New-CMOperatingSystemUpgradePackage -Name $Name -Path $ExtractPath\$Name\ -Version 1.0 -Description $Name -ErrorAction STOP | Out-Null
    $CMOperatingSystemUpgradePackage = (Get-CMOperatingSystemUpgradePackage -Name $Name)

    # Replace corresponding TS Step.
    Set-CMTSStepUpgradeOperatingSystem -TaskSequenceId $UpgradeTSID -StepName $CMTsStepName -UpgradePackage $CMOperatingSystemUpgradePackage -EditionIndex 1 -SetupTimeout 360 -IgnoreMessage $True -DynamicUpdateSetting OverridePolicy -ErrorAction Stop

    Set-Location C:
}
Write-Output "Finished Proecessing all ISOs."
Write-Output "Please make sure to distribute content and check your TS for successfull exchange of the OS images."

if (Test-Path $ExtractPath) { net use $ExtractPath /delete }
if (Test-Path $SourcePath) { net use $SourcePath /delete }

