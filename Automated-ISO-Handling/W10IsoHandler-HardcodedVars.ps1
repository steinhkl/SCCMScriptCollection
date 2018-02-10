#Requires -Version 4.0
#Requires -RunAsAdministrator
#Requires -Modules ConfigurationManager
Import-Module ConfigrationManager
# GitHub Version
# Author: Klaus Steinhauer
# Version: 0.4
# Chagelog: Implement All the new SCCM PS Cmdlets!
# Please Note:
#  Due to the implemented naming conventions
#
#  The folders containing the files will be named as follows:
#      Windows10_[RELEASE]_[BRANCH]_[ARCHITECTURE]_[LANGUAGE]
#
#      Exanmple : Windows10_16.07_CB_x64_EN
#
#  The Script also assumes you will use the Languages English and German.
#  Accordingly, when downloaded with German Locale, this is what the Isos are named like:
#
#  SW_DVD5_WIN_ENT_10_1607_64BIT_English_MLF_X21-07102.ISO
#
#  As of 16.07CBB Microsoft has Changed the Name of the ISO file to:
#
#  SW_DVD5_WIN_ENT_10_1607.1_64BIT_English_MLF_X21-27030.ISO
#
#  Either Rename the ISO or expect the new OS Images in SCCM to be named as such:
#
#  Windows10_16.07.1_CB_x64_EN
#
#  Please also Note:
#  Your Apply Operating System Step Must be Named as follows:
#
#       [BRANCH] [ARCHITECTURE] [LANG]
#       Example: "CBB x64 DE"
#
#  In order for the  to work.
#  Please **mind the whitespaces**!
#
#  As usual your milage may vary and you may want to **edit the Set-CMTSStepApplyOperatingSystem function accordingly**!

## Hardcoded Vars
$SourcePath = "\\YOUR\ISO\SOURCE\FOLDER"
$Branch = "CB" # will probably be removed in the future.
$User = "DOM\USERNAME"
$Cred = "PASSWORD"
$ExtractPath = "\\YOUR\SCCM\Destination"
#$CopyTargetPath = "\\YOUR\SETUPSCAN\Destination"
$SiteCode = "CMG"
$InstallTSID = "CMG00002" # Your AIO Install TS
$UpgradeTSID = "CMG00002" # Your AIO Upgrade TS

Set-Location C:

# Mount Target Directories.
net use $ExtractPath $Cred /USER:$User
#net use $CopyTargetPath $Cred /USER:$User

Get-Childitem $SourcePath\*.iso | ForEach-Object{
    Write-Output "Found ISO: $_.Name"
    $Basename = $_.Name

    # Get the Version, Architecture, Language and Full desired name.
    $Version = $Basename.Split("_")[5].Insert(2,".")
    $Arch = @{$true = 'x86'; $false = 'x64' }['x'+$Basename.Split("_")[6].Split("BIT")[0] -eq "x32"]
    $Lang = @{$true = 'EN'; $false = 'DE' }[$Basename.Split("_")[7] -eq "EN"]
    $Name = "Windows10_"+$Version+"_"+$Branch+"_"+$Arch+"_"+$Lang
    $CMTsStepName = "$Branch $Arch $Lang"


    #Create Target Extract Folder
    New-Item -ItemType directory -Force -Path $ExtractPath\$Name | Out-Null
    # Mount and get Driveletter
    $source = (Get-Volume -DiskImage (Mount-DiskImage -PassThru -ImagePath $SourcePath)).DriveLetter + ":\"
    # Copy Files
    Get-ChildItem -Path $source | Copy-Item -Destination $ExtractPath\$Name -Recurse -Force
    <# Copy to an additional Server for reasons.
    New-Item -ItemType directory -Force -Path $CopyTargetPath\$Name | Out-Null
    Get-ChildItem -Path $source | Copy-Item -Destination $CopyTargetPath\$Name -Recurse -Force
    #>
    # Dismount Image
    Dismount-DiskImage -ImagePath $SourcePath

    # Switch to CFGMGr Drive
    If((Get-Location).Drive.Name -ne $SiteCode){
            Try{Set-Location -path $SiteCode":" -ErrorAction Stop}
            Catch{Throw "Unable to connect to Site $SiteCode. Ensure that the Site Code is correct and that you have access."}
          }
    # Import Image into SCCM
    New-CMOperatingSystemImage -Name $Name -Path $ExtractPath\$Name\sources\install.wim -Version 1.0 -Description $Name -ErrorAction STOP
    $CMOperatingSystemImagePackage = (Get-CMOperatingSystemImage -Name $Name)

    # Replace corresponding TS Step.
    Set-CMTSStepApplyOperatingSystem -TaskSequenceId $InstallTSID  -StepName $CMTsStepName -ImagePackage $CMOperatingSystemImagePackage -PackageIndex 1

    # Add OS Upgrade Package to SCCM
    New-CMOperatingSystemUpgradePackage -Name $Name -Path $ExtractPath\$Name\ -Version 1.0 -Description $Name -ErrorAction STOP
    $CMOperatingSystemUpgradePackage = (Get-CMOperatingSystemUpgradePackage -Name $Name)

    # Replace corresponding TS Step.
    Set-CMTSStepApplyOperatingSystem -TaskSequenceId $UpgradeTSID  -StepName $CMTsStepName -InstallPackage $CMOperatingSystemUpgradePackage -InstallPackageIndex 1

    Set-Location C:
}


if (Test-Path $ExtractPath) { net use $ExtractPath /delete }
#if (Test-Path $CopyTargetPath) { net use $CopyTargetPath /delete }


Write-Output "Finished Proecessing all ISOs."
