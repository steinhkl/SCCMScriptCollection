
# SetupScan.ps1
# Author      : Klaus Steinhauer
# Version     : 0.1.3
# Function    : This Script Utilizes the Windows 10 Setup's ability to Scan a Computer for Compability.
#               It writes the resulting LogData to a specified Location and informs you of the outcome.
#               You can use a Task Sequence to Deploy this Script to any collection you want to scan before 
#               running an In Place Upgrade to Windows 10.
#               The resulting LogFiles should take up ~15 MB per Computer.
# Directories : Win10v1607CBx64 / Win10v1607CBx86
# Contact     : klaus.steinhauer@gmail.com
# Changelog   : 0.1 Initial Version.
#               0.1.1 Added XML Parsing
#               0.1.2 Write actual XML
#               0.1.3 Save all XML Data in one file for filtering etc.
# #####################################
# Modify these Variables to your needs.
# Root LogPath
$strLogPath = "\\LOGSERVER\IPU-Logs"
# Root Directory where you store your Install Medias:
$strRootSetupPath = "\\FILESERVER\Steinhauer.Klaus"
# OS Version 
$strOSVersion = "Win10v1607CB"
# Do not Modify below this line
# #####################################

# Get Computername
$strComputerName = $env:COMPUTERNAME
# Get Current Architecture
$strArch = (Get-WmiObject Win32_OperatingSystem -ComputerName $strComputerName).OSArchitecture
# where we will copy the Logs
$strLogDestination = "$strLogPath\$strComputerName"

# Create Directory in Logging Path
New-Item -ItemType directory -Force -Path $strLogDestination | Out-Null 

# Select Setup based on Architecture
if ($strArch -eq "64-Bit"){
    $strSetupPath = "$strRootSetupPath\$strOSVersion" + "x64\sources\setupprep.exe"
    }
    else{
    $strSetupPath = "$strRootSetupPath\$strOSVersion" + "x86\sources\setupprep.exe"
    }

# Start the Scan
Start-Process -FilePath "$strSetupPath" -ArgumentList "/Auto Upgrade /noreboot /DynamicUpdate Enable /quiet /copylogs $strLogDestination /compat ScanOnly" -Wait

# Get the relevant Line from LogFile
$strResult = Get-Content $strLogDestination\Panther\setupact.log | ? {($_ | Select-String "0xC19002") -and ($_ | Select-String "SetupHost::Execute")}
# Get The Exit Code
$exitCode = $strResult.Substring(85)

# Note: I'm not sure this will always work. Just in Case an ugly Backup.
<#
if ($strResult -like '*210'){
    $exitCode = "0xC1900210"
    }
    elif ($strResult -like '*208'){
    $exitCode = "0xC1900208"
    }
    elif ($strResult -like '*20E'){
    $exitCode = "0xC190020E"
    }
    elif ($strResult -like '*204'){
    $exitCode = "0xC1900204"
    }
#>

Write-Host $exitCode
# Generate Logfile ouput and write it to file.
$strOutput = "$(Get-Date),$strComputerName,$exitCode" 
$strOutput >> "$strLogPath\ScanResults.log"



# If there was an Error
if ($exitCode -eq "0xC1900208"){
    
    # XML Data will be overwritten!
    [xml]$XMLDocument ='<scanresult description="offenders">
        </scanresult>'
        
    # Create new Computer Element
    $addElm = $XMLDocument.CreateElement("Computer")
    $addAtr = $XMLDocument.CreateAttribute("name")
    $addAtr.value = $strComputerName
    $addElm.Attributes.Append($addAtr)
    $XMLDocument.scanresult.AppendChild($addElm)

    # Open all CompatData XML Files
    Get-ChildItem "$strLogDestination\Panther\" -Filter CompatData*.xml |
    ForEach-Object{ 
        # Get the Current File
        [XML]$XMLData = (Get-Content $_.FullName)
        # Select Target Node
        $XMLTarget=$XMLDocument.SelectSingleNode('//*[@name="'+$strComputerName+'"]')
        # Select Migration Nodes
        $XMLOffenders=$XMLData.SelectNodes('//*[@BlockingType="Hard"]').ParentNode
        # Go Through all Selected Migration Nodes
        foreach($var in $XMLOffenders){
            # Append all Nodes as Children of Scanresult
            $XMLTarget.appendChild($XMLDocument.ImportNode($var,$true))
        }
        # Save resulting XML File
        $XMLDocument.Save("$strLogDestination\ScanResults.xml")
    }
}