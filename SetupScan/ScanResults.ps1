# Requires -Version 3.0
# Searches for Errors in Setup XML Files and writes all Problems in one XML File

PARAM
(
    [Parameter(Mandatory=$true)][string] $strLogPath,
    [Parameter(Mandatory=$true)][string] $strDestPath,
    [Parameter(Mandatory=$true)][string] $strCred,
    [Parameter(Mandatory=$true)][string] $strUser
)

# Mount remote dir.
net use $strLogPath $strCred /USER:$strUser

# Test LogPath
if(!(Test-Path $strLogPath)){
    Write-Host "Please Provide a valid Log Path"
    exit 1
    }

    # XML Data will be overwritten!
    [xml]$XMLDocument ='<scanresult description="offenders">
        </scanresult>'

# Scan all Folders in Logpath        
Get-ChildItem $strLogPath | ForEach-Object{
    $strComputerName=($_.Name)
    $strLogDestination = "$strLogPath\$strComputerName" 
    # Does Panther Folder exists? If so there must have been an Error.
    if (Test-Path "$strLogDestination\Panther\"){
        # Check all XML Documents
        Get-ChildItem "$strLogDestination\Panther\" -Filter CompatData*.xml | ForEach-Object{
            # Get the Current File
            [XML]$XMLData = (Get-Content $_.FullName)
            # Select Migration Nodes (BlockingType = HARD)
            $XMLOffenders=$XMLData.SelectNodes('//*[@BlockingType="Hard"]').ParentNode
            # Go Through all Selected Migration Nodes
            if ($XMLOffenders -ne $null){
                # Create Target Node
                $addElm = $XMLDocument.CreateElement("Computer")
                $addAtr = $XMLDocument.CreateAttribute("name")
                $addAtr.value = $strComputerName
                $addElm.Attributes.Append($addAtr)
                $XMLDocument.scanresult.AppendChild($addElm)
                # Select Target
                $XMLTarget=$XMLDocument.SelectSingleNode('//*[@name="'+$strComputerName+'"]')
                foreach($var in $XMLOffenders){
                    # Append all Nodes as Children of Scanresult
                    $XMLTarget.appendChild($XMLDocument.ImportNode($var,$true))
                }
            }
        }
    }
}
$XMLDocument.Save("$strDestPath\ScanResults.xml")
