
# Requires -Version 2.0
# SetupScan.ps1
# Author      : Klaus Steinhauer
# Version     : 0.1.4
# Function    : This Script Utilizes the Windows 10 Setup's ability to Scan a Computer for Compability.
#               It writes the resulting LogData to a specified Location and informs you of the outcome.
#               You can use a Task Sequence to Deploy this Script to any collection you want to scan before 
#               running an In Place Upgrade to Windows 10.
#               The resulting LogFiles should use up to ~15 MB per Computer.
# Directories : Windows10_16.07_CB_x64_DE / Windows10_16.07_CB_x64_EN etc.
# Contact     : klaus.steinhauer@gmail.com
# Changelog   : 0.1 Initial Version.
#               0.1.1 Added XML Parsing
#               0.1.2 Write actual XML
#               0.1.3 Save XML Data in a per Computer XML File for Parsing.
#               0.1.4 - XML Data is now parsed in a different script due to the required PS Version being > 2.0.
#                     - Added Parameters for calling from SCCM.
#                     - Logs are uploaded to a network destination. "net use" is required due to PS Version being 2.0 on Win7.
#                     - Logs are only uploaded if an Error occured.
#                     - Added various Exitcodes and changed successcode to Exit 0 so SCCM can parse it.
# #####################################
# Do not Modify below this line
# #####################################

PARAM
(
    [Parameter(Mandatory=$true)][string] $strLogPath,
    [Parameter(Mandatory=$true)][string] $strRootSetupPath,
    [Parameter(Mandatory=$true)][string] $strOSVersion,
    [Parameter(Mandatory=$true)][string] $strCred,
    [Parameter(Mandatory=$true)][string] $strUser

)

# pseudo-mount
net use $strLogPath $strCred /USER:$strUser

# Test Log Path
if(!(Test-Path $strLogPath)){
    Write-Host "Please Provide a valid Log Path"
    exit 1
    }

# Get Computername
$strComputerName = $env:COMPUTERNAME
# Get Current Architecture
$strArch = (Get-WmiObject Win32_OperatingSystem -ComputerName $strComputerName).OSArchitecture | %{ $_.Split("-")[0] }
if ($strArch -eq "32") { $strArch = "86"}
# Get Install Language
$strLang = (Get-WmiObject -Class Win32_OperatingSystem).MUILanguages| %{ $_.Split("-")[0].toUpper() }
# Select Path of Setup destination.
$strSetupPath = "$strRootSetupPath\$strOSVersion"+"_x"+"$strArch"+"_"+"$strLang\sources\setupprep.exe"

# where we will copy the Logs (locally)
$strLogDestination = "$env:temp\$strComputerName"

# Create Directory in Temp.
New-Item -ItemType directory -Force -Path $strLogDestination | Out-Null 

# Test Setup Path
if (!(Test-Path $strSetupPath)){
    Write-Host "Please Provide a valid Setup Path"
    exit 2
}

# Start the Scan
Start-Process -FilePath "$strSetupPath" -ArgumentList "/Auto Upgrade /noreboot /DynamicUpdate Enable /quiet /copylogs $strLogDestination /compat ScanOnly" -Wait -NoNewWindow

# Get the relevant Line from LogFile
$strResult = Get-Content C:\Windows\Logs\MoSetup\bluebox.log | ? {($_ | Select-String "0xC19002") -and ($_ | Select-String "MainHR: Error")}
# Get The Exit Code
$exitCode = $strResult.Substring(37)[-1]

Write-Host $exitCode
# Generate Logfile ouput and write it to file.
$strOutput = "$(Get-Date),$strComputerName,$exitCode" 
$strOutput >> "$strLogDestination\ScanResults.log"

# On Success
if ($exitCode -eq "0xC1900210"){
    # Create Remote Dir
    New-Item -ItemType directory -Force -Path $strLogPath\$strComputerName | Out-Null 
    # Copy only the logfile containing the exitcode.
    Copy-Item "$strLogDestination\ScanResults.log" -Destination $strLogPath\$strComputerName -Recurse -Force
    $exitCode = 0
}
else {
    # Copy all the logfiles!
    Copy-Item $strLogDestination -Destination $strLogPath -Recurse -Force 
}

net use $strLogPath /delete
exit $exitCode
