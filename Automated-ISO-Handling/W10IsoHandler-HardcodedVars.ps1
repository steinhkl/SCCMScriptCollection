#Requires -Version 4.0
#Requires -RunAsAdministrator
#Requires -Modules ConfigurationManager
#Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
#  GitHub Version
#
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
#  In order for the doModify Switch to work.
#  Please **mind the whitespaces**!
#
#  As usual your milage may vary and you may want to **edit the StringHandling/ModifyTS function accordingly**!

<#
.SYNOPSIS
    !This script is still in early alpha. Do not use in production without prior testing!
    Microsoft is planning to release new Windows 10 Images every 4 months. 
    Given the potential for error when updating your OSD Task Sequence as well as In-Place-Upgrade TS it seemed a good idea to automate all the steps required post downloading the ISOs.
.DESCRIPTION
    Here is what the script can do:
    - Extract ISO files from a given Path to a given Path
    - Copy the extracted files to another Path 
    - Create a new Operating System Image in SCCM from a given Image
    - Modify a given Task Sequence to use a different Operating System Image

    Here is what the script will be able to do once there is a way to do it in PS:
    - Create a new Operating System Upgrade Image in SCCM
    - Modify a given (IPU) Task Sequence to use a differen Operating System Upgrade Package

    Use with Caution.

.NOTES
    File Name: isohandler.ps1
    Author: Klaus Steinhauer
    Version: 0.3

.PARAMETER SourcePath
    The Path where you stored your ISO files
.PARAMETER Branch
    The Branch of your ISO files [ CB, CBB, LTSB ]
.PARAMETER User
    The Domain\User used to access the target directory
.PARAMETER Cred
    The Password used to access the target directroy

.EXAMPLE
isohandler.ps1 -SourcePath C:\isos -Branch CB -User DMN\USER -Cred PASSWORD
# Unpacks ISO, copies it to Isilon, adds SCCM OS Image, Edits TS to use new Image.
#>

Write-Output "Copy Function is disabled by default as I am probably the only one who needs this."

PARAM
(
    # Source
    [Parameter(Mandatory=$true, Position = 0, Helpmessage = "Please enter the Source Path where your ISO files are located.")]
    [ValidateNotNullOrEmpty()] [string] $SourcePath,
    # Branch
    [Parameter(Mandatory=$true, Position = 1, Helpmessage = "Please enter the Branch of your ISO Files.")]
    [ValidateSet("CB","CBB","LTSB", IgnoreCase = $true)] [string] $Branch,
     
    # Credentials
    [Parameter(Mandatory=$true, Position = 2, Helpmessage = "Please enter the useraccount with which I should transfer the files (DOMAIN\USER).")] 
    [ValidateNotNullOrEmpty()] [string] $User,
    [Parameter(Mandatory=$true, Position = 3, Helpmessage = "Please enter the password of the useraccount.")]
    [ValidateNotNullOrEmpty()] [string] $Cred

)

## Hardcoded Vars
$ExtractPath = "\\YOUR\SCCM\Destination"
$CopySourcePath = "\\YOUR\SCCM\Destination"
$CopyTargetPath = "\\YOUR\SETUPSCAN\Destination"
$SiteServer = "YOUR.SITESERVER.FQDN.COM"
$SiteCode = "CMG"
$TaskSequenceID = "UML000AF" # Your AIO TS


function MountDir{
    PARAM(
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the ISO files are to be extracted (must be SCCM Readable for Import).")]
        [ValidateNotNullOrEmpty()] [string] $TargetPath,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the useraccount with which I should transfer the files (DOMAIN\USER).")] 
        [ValidateNotNullOrEmpty()] [string] $User,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the password of the useraccount.")]
        [ValidateNotNullOrEmpty()] [string] $Cred
    )

    # mount target directory
    Write-Output "Mounting dir $TargetPath"
    net use $TargetPath $Cred /USER:$User

}

function StringHandling{
    # Hier wirds hässlich, aufgrund unserer Namenskonvention vs der von MS
    PARAM(
        [Parameter(Mandatory = $true, HelpMessage = "Please enter the filename")]
        [ValidateNotNullOrEmpty()] [string] $FileName,
        [Parameter(Mandatory = $true, HelpMessage = "Tell me what you want.")]
        [ValidateSet("ALL","ARCH","LANG", IgnoreCase = $true)] [string] $desiredString
    )

    $Base = $FileName 
    $Version = $Base.Split("_")[5].Insert(2,".")
    # Language
    $Lang = $Base.Split("_")[7]
    if ($Lang -eq "English") {$Lang = "EN"} else {$Lang = "DE"}
    # Architecture
    $Arch = $Base.Split("_")[6].Split("BIT")[0]
    if ($Arch -eq "32"){$Arch = "86"}
    $Arch = "x"+$Arch

    
    Switch ($desiredString){
        ALL  { return "Windows10_"+$Version+"_"+$Branch+"_"+$Arch+"_"+$Lang }
        ARCH { return $Arch }
        LANG { return $Lang }
    }


}

function Extract{
    PARAM(
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the root Source Path where your ISO files are located.")]
        [ValidateScript({ Test-Path $_ })] [string] $SourcePath,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the ISO files are to be extracted (must be SCCM Readable for Import).")]
        [ValidateScript({ Test-Path $_ })] [string] $ExtractPath, 
        [Parameter(Mandatory = $true, HelpMessage = "Please enter the Folder Name")]
        [ValidateNotNullOrEmpty()] [string] $Name
    )
    #Create Target Folder
    
    New-Item -ItemType directory -Force -Path $ExtractPath\$Name | Out-Null 
    # Mount Iso Image
    $Mount = Mount-DiskImage -PassThru -ImagePath $SourcePath 
    # Get Driveletter
    $driveletter = (Get-Volume -DiskImage $Mount).driveletter
    $source = $driveletter + ":\"
    Write-Output "Copying Files from Image " $SourcePath " to " $ExtractPath\$Name
    # Copy Files
    Get-ChildItem -Path $source | Copy-Item -Destination $ExtractPath\$Name -Recurse -Force 

    # Write-Output "Dismounting Image."
    # Dismount Image
    Dismount-DiskImage $Mount.ImagePath
}

function CopyISO{
    PARAM(
        # Source DIR is where the ISO was extracted.
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the files will be copied from.")]
        [string] $SourceDirectory,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the files will be copied to.")]
        [string] $TargetDirectory, 
        [Parameter(Mandatory = $true, HelpMessage = "Please enter the Folder Name")]
        [ValidateNotNullOrEmpty()] [string] $Name
    )


    # Create Target Directory
    New-Item -ItemType directory -Force -Path $TargetDirectory\$Name | Out-Null
    Write-Output "Copying Files from Image " $SourcePath " to " $CopyPath
    # Copy Files
    Copy-Item $SourceDirectory\$Name -Destination $TargetDirectory -Recurse -Force 

}

Function AddOSImage{
    # http://cm12sdk.net/?p=1696
    PARAM(
        [Parameter(Mandatory = $True, HelpMessage = "Please enter OS Image Name")]
        [ValidateNotNullOrEmpty()] [string] $Name,
        [Parameter(Mandatory = $True, HelpMessage = "Please enter OS Image WIM image location")]
        [ValidateScript({ Test-Path $_ })] [string] $Path,
        [Parameter(Mandatory = $False, HelpMessage = "Please enter OS Image version")]
        [ValidateNotNullOrEmpty()] [string] $Version
    )
    # Write-Output "Adding Image $Name to SCCM"
    # https://gallery.technet.microsoft.com/scriptcenter/Display-the-source-98d77c8e
    If((Get-Location).Drive.Name -ne $SiteCode){ 
            Try{Set-Location -path $SiteCode":" -ErrorAction Stop} 
            Catch{Throw "Unable to connect to Site $SiteCode. Ensure that the Site Code is correct and that you have access."} 
    # Write-Output "I will now create the Image."
    $OSImage = New-CMOperatingSystemImage -Name $Name -Path $Path -Version 1.0 -Description $Name -ErrorAction STOP 
    return (Get-CMOperatingSystemImage -Name $Name).PackageID
    

    }
}

function modifyTS{
PARAM(
    [Parameter(Mandatory=$true, Helpmessage = "Please enter the FQDN of your SCCM Site Server.")]
    [ValidateNotNullOrEmpty()] [string] $SiteServer,
    [Parameter(Mandatory=$true, Helpmessage = "Please enter your SiteCode.")]
    [ValidateNotNullOrEmpty()] [string] $SiteCode,
    [Parameter(Mandatory=$true, Helpmessage = "Please enter the Branch of your ISO Files.")]
    [ValidateSet("CB","CBB","LTSB", IgnoreCase = $true)] [string] $Branch,
    [Parameter(Mandatory=$true, Helpmessage = "Please enter the Architecture of your OS Image")]
    [ValidateSet("x86","x64", IgnoreCase = $true)] [string] $Arch,
    [Parameter(Mandatory=$true, Helpmessage = "Please enter the Language of your OS Image")]
    [ValidateSet("DE","EN", IgnoreCase = $false)] [string] $Lang,
    [Parameter(Mandatory=$true, Helpmessage = "Please enter your Task Sequence Package ID.")]
    [ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] [string] $TaskSequenceID,
    [Parameter(Mandatory=$true, Helpmessage = "Please enter your (new) OS Image Package ID.")]
    #[ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] 
    [string] $newPackageID

)

    # Get SMS_TaskSequencePackage WMI object
    $TaskSequencePackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Filter "PackageID like '$TaskSequenceID'"
    $TaskSequencePackage.Get()

    # Get SMS_TaskSequence WMI object from TaskSequencePackage
    $TaskSequence = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "GetSequence" -ArgumentList $TaskSequencePackage

    # Convert WMI object to XML
    $TaskSequenceResult = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequence -ComputerName $SiteServer -Name "SaveToXml" -ArgumentList $TaskSequence.TaskSequence
    [XML]$TaskSequenceXML = $TaskSequenceResult.ReturnValue

    # Select Matching OS
    $OldNode = $TaskSequenceXML.SelectSingleNode("//step[contains(@name,'$Branch $Arch $Lang')]")
    # Replace Package ID in Variable List
    $OldNode.LastChild.ChildNodes.Item(1)."#text" = $newPackageID
    # And in the Upgrade Command.
    $OldNode.action = $OldNode.action -replace("[A-Z0-9]{3}[A-F0-9]{5}",$newPackageID)


    # Convert XML back to SMS_TaskSequencePackage WMI object
    $TaskSequenceResult = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "ImportSequence" -ArgumentList $TaskSequenceXML.OuterXml
 
    # Update SMS_TaskSequencePackage WMI object
    # Write-Output "Editing Tasksequence $TaskSequenceID in SCCM."
    Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "SetSequence" -ArgumentList @($TaskSequenceResult.TaskSequence, $TaskSequencePackage)



}

# Mount Target Directories.
MountDir -TargetPath $ExtractPath -User $User -Cred $Cred
MountDir -TargetPath $CopyTargetPath -User $User -Cred $Cred

Get-Childitem $SourcePath\*.iso | ForEach-Object{

    Write-Output "Found ISO: $_.Name"
    # Get the Name
    $Name = StringHandling -FileName $_.Name -desiredString ALL
    $Arch = StringHandling -FileName $_.Name -desiredString ARCH
    $Lang = StringHandling -FileName $_.Name -desiredString LANG

    # Extract the Iso and optionally copy it to another path.
    Extract -SourcePath $_.FullName -ExtractPath $ExtractPath -Name $Name

    # Copy Files for SetupScan.
    # CopyISO -SourceDirectory $CopySourcePath -TargetDirectory $CopyTargetPath -Name $Name

    # Add Image to SCCM
    $newPackageID = AddOsImage -Name $Name -Path $ExtractPath\$Name\sources\install.wim -Version 1.0

    # Add OS Upgrade Package to SCCM
    # TODO: The SCCM PS Cmdlet currently does not support this.
    # Note: Added to SCCM PS Cmdlet with TP 1701 - Should be available soon.

    # Update TaskSequence References
    # TODO: The SCCM PS Cmdlet currently does not support this.
    if($newPackageID) { 
        ModifyTS -SiteServer $SiteServer -SiteCode $SiteCode -Branch $Branch -Arch $Arch -Lang $Lang -TaskSequenceID $TaskSequenceID -newPackageID "$newPackageID"
    }
    Set-Location C:
}


if (Test-Path $ExtractPath) { net use $ExtractPath /delete }
if (Test-Path $CopyTargetPath) { net use $CopyTargetPath /delete }


Write-Output "Finished Proecessing all ISOs."