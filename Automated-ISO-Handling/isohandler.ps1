# Requires -Version 3.0
# Requires -Modules ConfigurationManager
#  Please Note: This is currently BETA Software and should not be used in Production before doing some extensive testing.
#  Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
#  
# Fully Automated Windows 10 Iso Handling (once you downloaded them)
# GitHub Version
#
# Version: 0.2
# Author: Klaus Steinhauer
# Contact: klaus.steinhauer@gmail.com
# 
# What it does:
# - Extract ISOs according to Naming Schema
# - Copy ISO content to a seperate Directory
# - Add Operating System Images to SCCM
# - Modify your TS to update the Image used
#
# TODO:
# - Add Operating System Update Images to SCCM - Currently not supported (AFAIK)
# - TEST: Modify Task Sequences
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
#  Please also Note:
#  Your Apply Operating System Step Must be Named as follows:
#
#       [BRANCH] [ARCHITECTURE] [LANG]
#       Example: "CBB x64 DE"
#
#  Please **mind the whitespaces**!
#
#  As usual your milage may vary and you may want to **edit the StringHandling/ModifyTS function accordingly**!
#  PS: If anyone finds a way to detect the Branch please let me know.
#
# Sample Call:
# .\isohandler.ps1 -strSourcePath "C:\WindowsImages" -strBranch CBB -doExtract -strExtractPath "\\SERVER\SCCM_SRC\OSD" -doCopy -strCopySourcePath "\\SERVER\SCCM_SRC\OSD" -strCopyTargetPath "\\SERVER2\!OSD" -strUser DMN\USER -strCred PASSWORD -doAddOSImage -

[CmdletBinding(DefaultParameterSetName="default")]
PARAM
(
    # Source
    [Parameter(ParameterSetName="default", Mandatory=$true, Position = 0, Helpmessage = "Please enter the Source Path where your ISO files are located.")]
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 0)]
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 0)]
    [ValidateNotNullOrEmpty()] [string] $strSourcePath,
    # Branch
    [Parameter(ParameterSetName="default", Mandatory=$true, Position = 1, Helpmessage = "Please enter the Branch of your ISO Files.")]
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 1)]
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 1)]
    [Parameter(ParameterSetName="OSPackage", Mandatory=$true, Position = 1)] 
    [Parameter(ParameterSetName="TSMod", Mandatory=$true, Position = 1)] 
    [ValidateSet("CB","CBB","LTSB", IgnoreCase = $true)] [string] $strBranch,

    # Extract ISO
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 2, Helpmessage = "Please specify wether you want to extract the isos.")]
    [switch] $doExtract,
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 3, Helpmessage = "Please enter the location where the ISO files are to be extracted (must be SCCM Readable for Import).")]
    [Parameter(ParameterSetName="OSPackage", Mandatory=$true, Position = 4)]
    [ValidateNotNullOrEmpty()] [string] $strExtractPath,    

    # Copy ISO
    [Parameter(ParameterSetName="copy", Mandatory=$false, Position = 4, Helpmessage = "Please specify wether you want to copy the ISO content to another folder.")]
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 4)]
    [switch] $doCopy,
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 5, Helpmessage = "Please enter the path of your extracted ISO.")]
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 5)]
    [ValidateNotNullOrEmpty()] [string] $strCopySourcePath,   
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 6, Helpmessage = "Please enter the path where the content should be copied to.")]
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 6)]
    [ValidateNotNullOrEmpty()] [string] $strCopyTargetPath,   

     
    # Credentials
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 6, Helpmessage = "Please enter the useraccount with which I should transfer the files (DOMAIN\USER).")] 
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 6)]
    [ValidateNotNullOrEmpty()] [string] $strUser,
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 7, Helpmessage = "Please enter the password of the useraccount.")]
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 7)]
    [ValidateNotNullOrEmpty()] [string] $strCred,

    # Add OS Package to SCCM
    [Parameter(ParameterSetName="OSPackage", Mandatory=$false, Position = 2, Helpmessage = "Please specify wether you want to add the extracted images to SCCM.")]
    [switch] $doAddOSImage,

    # Update Task Sequence
    [Parameter(ParameterSetName="TSMod", Mandatory=$false, Position = 9, Helpmessage = "Please specify wether you want to modify your SCCM OSD Task Sequence")]
    [switch] $DoModifyTS,
    [Parameter(ParameterSetName="TSMod", Mandatory=$true, Position = 10, Helpmessage = "Please enter the FQDN of your SCCM Site Server.")]
    [ValidateNotNullOrEmpty()] [string] $SiteServer,
    [Parameter(ParameterSetName="TSMod", Mandatory=$true, Position = 12, Helpmessage = "Please enter your SiteCode.")]
    [ValidateNotNullOrEmpty()] [string] $SiteCode,
    [Parameter(ParameterSetName="TSMod", Mandatory=$true, Position = 13, Helpmessage = "Please enter your Task Sequence ID.")]
    [ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] [string] $TaskSequenceID,
    [Parameter(ParameterSetName="TSMod", Mandatory=$false, Position = 14, Helpmessage = "Please enter your OS Image ID.")]
    [ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] [string] $OSImagePackageID
)

function checkvars{
    # Powershell ParameterSets are a bit weird.
    # I have not yet found a way to make params mandatory based on a switch independant of its set without also making it mandatory when the switch is not active.
    # Example: 
    # 
    #     [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 5, Helpmessage = "Please enter the path of your extracted ISO.")]
    #     [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 5)]
    #     [ValidateNotNullOrEmpty()] [string] $strCopySourcePath,   
    # 
    #  If you enter the PARAMs -doExtract -strExtractPath C:\test you will have to enter strCopySourcePath.
    #  If you set:
    #     [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 5)]
    #
    #  You can enter the PARAMS -doExtract -strExtractPath C:\test BUT of course $strCopySourcePath is no longer mandatory and this breaks the script in case -doCopy is called without dependant parameters.
    #
    # So in conclusion Powershell is weird. I will do some ugly stuff here.
    #

    if ($doExtract -and (!$strExtractPath)){
        Write-Host "I detected an invalid combination of Parameters!"
        Write-Host "Please use the following Parameters: "
        Write-Host "-strExtractPath <String>"
        Exit 0
    }

    if ($doCopy -and (!$strCopySourcePath -or !$strCopyTargetPath)){
        Write-Host "I detected an invalid combination of Parameters!"
        Write-Host "Please use the following Parameters: "
        Write-Host "-strCopySourcePath <String>"
        Write-Host "-strCopyTargetPath <String>"
        Exit 0
    }

    if ($DoModifyTS -and (!$SiteServer -or !$SiteCode -or !$TaskSequenceID)){
        Write-Host "I detected an invalid combination of Parameters!"
        Write-Host "Please use the following Parameters: "
        Write-Host "-SiteServer <String>"
        Write-Host "-SiteCode <String>"
        Write-Host "-TaskSequenceID <String>"
        Exit 0
    }

    if ($DoModifyTS -and !$doAddOSImage -and !$OSImagePackageID){
        Write-Host "I detected an invalid combination of Parameters!"
        Write-Host "Please use the following Parameters: "
        Write-Host "-OSImagePackageID <String>"
        Exit 0
    }

}

function MountDir{
    PARAM(
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the ISO files are to be extracted (must be SCCM Readable for Import).")]
        [ValidateNotNullOrEmpty()] [string] $TargetPath,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the useraccount with which I should transfer the files (DOMAIN\USER).")] 
        [ValidateNotNullOrEmpty()] [string] $strUser,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the password of the useraccount.")]
        [ValidateNotNullOrEmpty()] [string] $strCred
    )

    # mount target directory
    net use $TargetPath $strCred /USER:$strUser
}

function StringHandling{
    # Hier wirds hässlich, aufgrund unserer Namenskonvention vs der von MS
    PARAM(
        [Parameter(Mandatory = $true, HelpMessage = "Please enter the filename")]
        [ValidateNotNullOrEmpty()] [string] $strFileName,
        [Parameter(Mandatory = $true, HelpMessage = "Tell me what you want.")]
        [ValidateSet("ALL","ARCH","LANG", IgnoreCase = $true)] [string] $desiredString
    )

    $strBase = $strFileName 
    $strVersion = $strBase.Split("_")[5].Insert(2,".")
    # Language
    $strLang = $strBase.Split("_")[7]
    if ($strLang -eq "English") {$strLang = "EN"} else {$strLang = "DE"}
    # Architecture
    $strArch = $strBase.Split("_")[6].Split("BIT")[0]
    if ($strArch -eq "32"){$strArch = "86"}

    
    Switch ($desiredString){
        ALL  { return "Windows10_"+$strVersion+"_"+$strBranch+"_x"+$strArch+"_"+$strLang }
        ARCH { return $strArch }
        LANG { return $strLang }
    }


}

function Extract{
    PARAM(
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the Source Path where your ISO files are located.")]
        [ValidateScript({ Test-Path $_ })] [string] $strSourcePath,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the ISO files are to be extracted (must be SCCM Readable for Import).")]
        [ValidateScript({ Test-Path $_ })] [string] $strExtractPath, 
        [Parameter(Mandatory = $true, HelpMessage = "Please enter the File Name")]
        [ValidateNotNullOrEmpty()] [string] $Name
    )

    #Create Target Folder
    New-Item -ItemType directory -Force -Path $strExtractPath\$Name | Out-Null 
    # Mount Iso Image
    $Mount = Mount-DiskImage -PassThru -ImagePath $strSourcePath 
    # Get Driveletter
    $driveletter = (Get-Volume -DiskImage $Mount).driveletter
    # Write-Host "Copying Files from Image " $strSourcePath " to " $strExtractPath\$Name
    # Copy Files
    Copy-Item $driveletter":\" -Destination $strExtractPath\$Name -Recurse -Force 
    # Write-Host "Dismounting Image."
    # Dismount Image
    Dismount-DiskImage $Mount.ImagePath
}

function CopyISO{
    PARAM(
        # Source DIR is where the ISO was extracted.
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the files will be copied from.")]
        #[ValidateScript({ Test-Path $_ })] 
        [string] $strSourceDirectory,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the files will be copied to.")]
        #[ValidateScript({ Test-Path $_ })] 
        [string] $strTargetDirectory, 
        [Parameter(Mandatory = $true, HelpMessage = "Please enter the File Name")]
        [ValidateNotNullOrEmpty()] [string] $Name
    )

    # Create Target Directory
    New-Item -ItemType directory -Force -Path $strCopyPath\$Name | Out-Null 
    # Write-Host "Copying Files from Image " $strSourcePath " to " $strCopyPath
    # Copy Files
    Copy-Item $strExtractPath\$Name -Destination $strCopyPath -Recurse -Force 

}

Function AddOSImage{
    # http://cm12sdk.net/?p=1696
    PARAM(
        [Parameter(Mandatory = $True, HelpMessage = "Please enter OS Image Name")]
        [ValidateNotNullOrEmpty()] [string] $Name,
        [Parameter(Mandatory = $True, HelpMessage = "Please enter OS Image WIM location")]
        [ValidateScript({ Test-Path $_ })] [string] $Path,
        [Parameter(Mandatory = $False, HelpMessage = "Please enter OS Image version")]
        [ValidateNotNullOrEmpty()] [string] $Version
        <#
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the FQDN of your SCCM Site Server.")]
        [ValidateNotNullOrEmpty()] [string] $SiteServer,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter your SiteCode.")]
        [ValidateNotNullOrEmpty()] [string] $SiteCode
        #>
    )
    Write-Host "Adding Image " $Name " to SCCM"
    # Requires Testing!
    Write-Host "Currently Disabled. Please do not test this in production!"
    Write-Host "Enable in Line 267/268!"
    # New-CMOperatingSystemImage -Name $Name -Path $Path -Version 1.0 -Description $Name -ErrorAction STOP 
    # return (Get-CMOperatingSystemImage -Name $Name).PackageID
    
    <# We probably won't need this anymore.
    Try{
        $Arguments = @{
            Name = $Name;
            PkgSourceFlag = 2;
            PkgSourcePath = $Path;
            Version = $Version
        }
        Set-WmiInstance -Namespace "Root\SMS\Site_$SiteCode" -Class 'SMS_ImagePackage' -Arguments $Arguments -ComputerName $SiteServer -ErrorAction STOP
    }
    Catch{
        $_.Exception.Message
    }
    #>



}

function modifyTS{
PARAM(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()] [string] $SiteServer,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()] [string] $SiteCode,
    [Parameter(Mandatory=$true)]
    [ValidateSet("CB","CBB","LTSB", IgnoreCase = $true)] [string] $strBranch,
    [Parameter(Mandatory=$true)]
    [ValidateSet("x86","x64", IgnoreCase = $true)] [string] $strArch,
    [Parameter(Mandatory=$true)]
    [ValidateSet("DE","EN","LTSB", IgnoreCase = $false)] [string] $strLang,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] [string] $TaskSequenceID,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] [string] $newPackageID
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
    $OldNode = $TaskSequenceXML.SelectSingleNode("//step[contains(@name,'$strBranch $strArch $strLang')]")
    # Replace Package ID in Variable List
    $OldNode.LastChild.ChildNodes.Item(1)."#text" = $newID
    # And in the Upgrade Command.
    $OldNode.action = $OldNode.action -replace("[A-Z0-9]{3}[A-F0-9]{5}",$newID)


    # Convert XML back to SMS_TaskSequencePackage WMI object
    $TaskSequenceResult = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "ImportSequence" -ArgumentList $TaskSequenceXML.OuterXml
 
    # Update SMS_TaskSequencePackage WMI object
    Write-Host "This is where I would update my Task Sequence but I will not do this in production!"
    Write-Host "Modify in line 333"
    # Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "SetSequence" -ArgumentList @($TaskSequenceResult.TaskSequence, $TaskSequencePackage)



}


<#
# DEBUGGING!
Write-Host ""
Write-Host "PARAM:"
Write-Host "strSourcePath" $strSourcePath
Write-Host "strBranch" $strBranch
Write-Host "doExtract" $doExtract
Write-Host "strExtractPath" $strExtractPath
Write-Host "doCopy" $doCopy
Write-Host "strCopySourcePath" $strCopySourcePath
Write-Host "strCopyTargetPath" $strCopyTargetPath
Write-Host "strUser" $strUser
Write-Host "strCred" $strCred
Write-Host "doAddOSImage" $doAddOSImage
Write-Host "SiteServer" $SiteServer
Write-Host "SiteCode" $SiteCode

#Exit 0

# /DEBUGGING!
#>

checkvars

gci $strSourcePath\*.iso | foreach{

    Write-Host "Found ISO: " $_.Name
    # Get the Name
    $Name = StringHandling -strFileName $_.Name -desiredString ALL
    $Arch = StringHandling -strFileName $_.Name -desiredString ARCH
    $Lang = StringHandling -strFileName $_.Name -desiredString LANG

    # Extract the Iso and optionally copy it to another path.
    if ($doExtract){ 
        MountDir -TargetPath $strExtractPath -strUser $strUser -strCred $strCred
        Extract -strSourcePath $_.FullName -strExtractPath $strExtractPath -Name $Name
    }

    if ($doCopy){
        # Mount Copy Destination
        MountDir -TargetPath $strCopyTargetPath -strUser $strUser -strCred $strCred
        # Copy Files
        CopyISO -strSourceDirectory $strCopySourcePath -strTargetDirectory $strCopyTargetPath -Name $Name
    }

    # Add Image to SCCM
    if ($doaddOSImage){ 
        $newPackageID = AddOsImage -Name $Name -Path $strExtractPath\$Name\sources\install.wim -Version 1.0  
    }

    # Add OS Upgrade Package to SCCM
    # TODO: The SCCM PS Cmdlet currently does not support this.

    # Update TaskSequence References
    if($DoModifyTS){
        if($doaddOSImage) { $OSImagePackageID = $newPackageID }
        ModifyTS -SiteServer $SiteServer -SiteCode $SiteCode -TaskSequenceID $TaskSequenceID -strBranch $strBranch -strArch $Arch -strLang $Lang -TaskSequenceID $TaskSequenceID -newPackageID $OSImagePackageID
    }


    if ($doExtract -or $doCopy){
        if (Test-Path $strExtractPath) { net use $strExtractPath /delete }
        if (Test-Path $strCopyTargetPath) { net use $strCopyTargetPath /delete }
    }

}
Write-Host "Finished Proecessing all ISOs."