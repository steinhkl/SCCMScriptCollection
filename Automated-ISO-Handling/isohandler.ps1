# Requires -Version 3.0
# Requires -Modules ConfigurationManager
#  Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
#  GitHub Version
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
#  In order for the doModify Switch to work.
#  Please **mind the whitespaces**!
#
#  As usual your milage may vary and you may want to **edit the StringHandling/ModifyTS function accordingly**!
#  PS: If anyone finds a way to detect the Branch please let me know.
#

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
    - All of the above at once.

    Here is what the script will be able to do once there is a way to do it in PS:
    - Create a new Operating System Upgrade Image in SCCM
    - Modify a given (IPU) Task Sequence to use a differen Operating System Upgrade Package
    - All of the above.

    Please Note: I am by no means a PS expert and this script should be used with caution.

.NOTES
    File Name: isohandler.ps1
    Author: Klaus Steinhauer
    Version: 0.2.1

.PARAMETER SourcePath
    The Path where you stored your ISO files
.PARAMETER Branch
    The Branch of your ISO files [ CB, CBB, LTSB ]
.PARAMETER doExtract
    Switch to Extract ISO files
.PARAMETER ExtractPath
    The Path where your ISO files should be extracted to.
    Also used in:
        -doAddOSImage
.PARAMETER doCopy
    Switch to Copy extracted files to another location
.PARAMETER CopySourcePath
    The Path where your ISO files have been extracted ( e.g. same as ExtractPath )
.PARAMETER CopyTargetPath
    The Target Directory
.PARAMETER User
    The Domain\User used to access the target directory
    Required by:
        -doExtract
        -doCopy
.PARAMETER Cred
    The Password used to access the target directroy
    Required by:
        -doExtract
        -doCopy
.PARAMETER doAddOSImage
    Switch to add new Operating System Image to SCCM    
.PARAMETER doModifyTS
    Switch to modify a given Task Sequence in SCCM to use a new Operating System Image
.PARAMETER SiteServer
    Your SCCM Site Server FQDN
.PARAMETER SiteCode
    Your SCCM Site Code
.PARAMETER TaskSequenceID
    The PackageID of the Task Sequence you wish to Modify
.PARAMETER OSImagePackageID
    The PackageID of your Operating System Image
    Required if you did not use the doAddOSImage Switch

.EXAMPLE
 \\
Extract:
isohandler.ps1 -SourcePath C:\isos -Branch CB -doExtract -ExtractPath \\UNCPATH\DIR -User DMN\USER -Cred PASSWORD
Copy:
isohandler.ps1 -SourcePath C:\isos -Branch CB -doCopy -CopySourcePath \\UNCPATH\DIR -CopyTargetPath \\UNCPATH2\DIR -User DMN\USER -Cred PASSWORD
Both:
isohandler.ps1 -SourcePath C:\isos -Branch CB -doExtract -ExtractPath \\UNCPATH\DIR -doCopy -CopySourcePath \\UNCPATH\DIR -CopyTargetPath \\UNCPATH2\DIR -User DMN\USER -Cred PASSWORD
Extract, add SCCM OS Image and update a TS:
isohandler.ps1 -SourcePath C:\isos -Branch CB -doExtract -ExtractPath \\UNCPATH\DIR -User DMN\USER -Cred PASSWORD -doAddOSImage -doModifyTS -SiteServer PS01.local -SiteCode PS1 -TaskSequenceID PS10001A
#>

[CmdletBinding(DefaultParameterSetName="default")]
PARAM
(
    # Source
    [Parameter(ParameterSetName="default", Mandatory=$true, Position = 0, Helpmessage = "Please enter the Source Path where your ISO files are located.")]
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 0)]
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 0)]
    [ValidateNotNullOrEmpty()] [string] $SourcePath,
    # Branch
    [Parameter(ParameterSetName="default", Mandatory=$true, Position = 1, Helpmessage = "Please enter the Branch of your ISO Files.")]
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 1)]
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 1)]
    [Parameter(ParameterSetName="OSPackage", Mandatory=$true, Position = 1)] 
    [Parameter(ParameterSetName="TSMod", Mandatory=$true, Position = 1)] 
    [ValidateSet("CB","CBB","LTSB", IgnoreCase = $true)] [string] $Branch,

    # Extract ISO
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 2, Helpmessage = "Please specify wether you want to extract the isos.")]
    [switch] $doExtract,
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 3, Helpmessage = "Please enter the location where the ISO files are to be extracted (must be SCCM Readable for Import).")]
    [Parameter(ParameterSetName="OSPackage", Mandatory=$true, Position = 4)]
    [ValidateNotNullOrEmpty()] [string] $ExtractPath,    

    # Copy ISO
    [Parameter(ParameterSetName="copy", Mandatory=$false, Position = 4, Helpmessage = "Please specify wether you want to copy the ISO content to another folder.")]
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 4)]
    [switch] $doCopy,
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 5, Helpmessage = "Please enter the path of your extracted ISO.")]
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 5)]
    [ValidateNotNullOrEmpty()] [string] $CopySourcePath,   
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 6, Helpmessage = "Please enter the path where the content should be copied to.")]
    [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 6)]
    [ValidateNotNullOrEmpty()] [string] $CopyTargetPath,   

     
    # Credentials
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 6, Helpmessage = "Please enter the useraccount with which I should transfer the files (DOMAIN\USER).")] 
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 6)]
    [ValidateNotNullOrEmpty()] [string] $User,
    [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 7, Helpmessage = "Please enter the password of the useraccount.")]
    [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 7)]
    [ValidateNotNullOrEmpty()] [string] $Cred,

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
    [Parameter(ParameterSetName="TSMod", Mandatory=$true, Position = 13, Helpmessage = "Please enter your Task Sequence Packgage ID.")]
    [ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] [string] $TaskSequenceID,
    [Parameter(ParameterSetName="TSMod", Mandatory=$false, Position = 14, Helpmessage = "Please enter your (new) OS Image Package ID.")]
    [ValidatePattern('[A-Z0-9]{3}[A-F0-9]{5}')] [string] $OSImagePackageID
)

function checkvars{
# Powershell ParameterSets are a bit weird.
# I have not yet found a way to make params mandatory based on a switch independant of its set without also making it mandatory when the switch is not active.
# Example: 
# 
#     [Parameter(ParameterSetName="copy", Mandatory=$true, Position = 5, Helpmessage = "Please enter the path of your extracted ISO.")]
#     [Parameter(ParameterSetName="extract", Mandatory=$true, Position = 5)]
#     [ValidateNotNullOrEmpty()] [string] $CopySourcePath,   
# 
#  If you enter the PARAMs -doExtract -ExtractPath C:\test you will have to enter CopySourcePath.
#  If you set:
#     [Parameter(ParameterSetName="extract", Mandatory=$false, Position = 5)]
#
#  You can enter the PARAMS -doExtract -ExtractPath C:\test BUT of course $CopySourcePath is no longer mandatory and this breaks the script in case -doCopy is called without it's dependant parameters.
#
# So in conclusion Powershell is weird. I will do some ugly stuff here.
#

if ($doExtract -and (!$ExtractPath)){
    Write-Host "I detected an invalid combination of Parameters!"
    Write-Host "Please use the following Parameters: "
    Write-Host "-ExtractPath <String>"
    Exit 0
}

if ($doCopy -and (!$CopySourcePath -or !$CopyTargetPath)){
    Write-Host "I detected an invalid combination of Parameters!"
    Write-Host "Please use the following Parameters: "
    Write-Host "-CopySourcePath <String>"
    Write-Host "-CopyTargetPath <String>"
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
}


}

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

    
    Switch ($desiredString){
        ALL  { return "Windows10_"+$Version+"_"+$Branch+"_x"+$Arch+"_"+$Lang }
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
    # Write-Host "Copying Files from Image " $SourcePath " to " $ExtractPath\$Name
    # Copy Files
    Copy-Item $driveletter":\" -Destination $ExtractPath\$Name -Recurse -Force 
    # Write-Host "Dismounting Image."
    # Dismount Image
    Dismount-DiskImage $Mount.ImagePath
}

function CopyISO{
    PARAM(
        # Source DIR is where the ISO was extracted.
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the files will be copied from.")]
        #[ValidateScript({ Test-Path $_ })] 
        [string] $SourceDirectory,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the location where the files will be copied to.")]
        #[ValidateScript({ Test-Path $_ })] 
        [string] $TargetDirectory, 
        [Parameter(Mandatory = $true, HelpMessage = "Please enter the Folder Name")]
        [ValidateNotNullOrEmpty()] [string] $Name
    )

    # Create Target Directory
    New-Item -ItemType directory -Force -Path $CopyPath\$Name | Out-Null 
    # Write-Host "Copying Files from Image " $SourcePath " to " $CopyPath
    # Copy Files
    Copy-Item $ExtractPath\$Name -Destination $CopyPath -Recurse -Force 

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
        <#
        [Parameter(Mandatory=$true, Helpmessage = "Please enter the FQDN of your SCCM Site Server.")]
        [ValidateNotNullOrEmpty()] [string] $SiteServer,
        [Parameter(Mandatory=$true, Helpmessage = "Please enter your SiteCode.")]
        [ValidateNotNullOrEmpty()] [string] $SiteCode
        #>
    )
    Write-Host "Adding Image " $Name " to SCCM"
    # https://gallery.technet.microsoft.com/scriptcenter/Display-the-source-98d77c8e
    If((Get-Location).Drive.Name -ne $SiteCode){ 
            Try{Set-Location -path "($SiteCode):" -ErrorAction Stop} 
            Catch{Throw "Unable to connect to Site $SiteCode. Ensure that the Site Code is correct and that you have access."} 
    # Requires Testing!
    Write-Host "Currently Disabled. Please do not test this in production!"
    Write-Host "Enable in Lines 332/333"
    # $OSImage = New-CMOperatingSystemImage -Name $Name -Path $Path -Version 1.0 -Description $Name -ErrorAction STOP 
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
    $OldNode = $TaskSequenceXML.SelectSingleNode("//step[contains(@name,'$Branch $Arch $Lang')]")
    # Replace Package ID in Variable List
    $OldNode.LastChild.ChildNodes.Item(1)."#text" = $newPackageID
    # And in the Upgrade Command.
    $OldNode.action = $OldNode.action -replace("[A-Z0-9]{3}[A-F0-9]{5}",$newPackageID)


    # Convert XML back to SMS_TaskSequencePackage WMI object
    $TaskSequenceResult = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "ImportSequence" -ArgumentList $TaskSequenceXML.OuterXml
 
    # Update SMS_TaskSequencePackage WMI object
    Write-Host "This is where I would update my Task Sequence but I will not do this in production!"
    Write-Host "Modify in line 396"
    # Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "SetSequence" -ArgumentList @($TaskSequenceResult.TaskSequence, $TaskSequencePackage)



}

checkvars

gci $SourcePath\*.iso | foreach{

    Write-Host "Found ISO: " $_.Name
    # Get the Name
    $Name = StringHandling -FileName $_.Name -desiredString ALL
    $Arch = StringHandling -FileName $_.Name -desiredString ARCH
    $Lang = StringHandling -FileName $_.Name -desiredString LANG

    # Extract the Iso and optionally copy it to another path.
    if ($doExtract){ 
        MountDir -TargetPath $ExtractPath -User $User -Cred $Cred
        Extract -SourcePath $_.FullName -ExtractPath $ExtractPath -Name $Name
    }

    if ($doCopy){
        # Mount Copy Destination
        MountDir -TargetPath $CopyTargetPath -User $User -Cred $Cred
        # Copy Files
        CopyISO -SourceDirectory $CopySourcePath -TargetDirectory $CopyTargetPath -Name $Name
    }
    # Add Image to SCCM
    if ($doaddOSImage){ 
        $newPackageID = AddOsImage -Name $Name -Path $ExtractPath\$Name\sources\install.wim -Version 1.0  
    }

    # Add OS Upgrade Package to SCCM
    # TODO: The SCCM PS Cmdlet currently does not support this.

    # Update TaskSequence References
    # TODO: The SCCM PS Cmdlet currently does not support this.
    if($DoModifyTS){
        if($doaddOSImage) { $OSImagePackageID = $newPackageID }
        ModifyTS -SiteServer $SiteServer -SiteCode $SiteCode -TaskSequenceID $TaskSequenceID -Branch $Branch -Arch $Arch -Lang $Lang -TaskSequenceID $TaskSequenceID -newPackageID $OSImagePackageID
    }

}

if ($doExtract -or $doCopy){
    if (Test-Path $ExtractPath) { net use $ExtractPath /delete }
    if (Test-Path $CopyTargetPath) { net use $CopyTargetPath /delete }
}

Write-Host "Finished Proecessing all ISOs."