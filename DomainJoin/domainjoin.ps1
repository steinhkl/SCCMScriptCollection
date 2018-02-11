#requires -version 5.0
#requires -runasadministrator
$DomainName = "your.domain.com"
$CMClientLocation = "\\YOUR-CLIENT-LOCATION\Client"
$CMServer = "CFGMGR.SERVER.YOURDOMAIN.COM"
$CMSiteCode = "CMG"

function GetCreds{
  # Replace with Service Account!
	$secureString = "YOURSECURESTRING"
	$userName = "DOMAIN\ACCOUNT"
	$key = ("YOUR KEY!") # REPLACE ME!
	$Password = ConvertTo-SecureString -String $secureString -Key $key
	$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $userName, $Password
	return $cred
}

Start-Transcript "C:\Windows\Logs\domainjoin.log"
Write-Information "Getting local Data for Import"

# There should really only be one active interface. If there is not we will select the first address.
# This might cause problems so simply only use one interface!
# $mac = (Get-NetAdapter | where Status -eq "up").MacAddress[0].replace("-",":")
$mac = (Get-WmiObject win32_networkadapter -Filter "netconnectionstatus = 2").MacAddress
# this should work unless you have 18 interfaces...
if ($mac.Length -ne 17){$mac = $mac[0]}
$computername = $env:COMPUTERNAME
# Language will be determined by the current Culture settings. Make sure you apply them before running.
$language = (Get-Culture).Name.Split("-")[1]
# Get Arch
$arch = @{$true = 'x86'; $false = 'x64' }[[System.Environment]::Is64BitOperatingSystem -eq $False]
$csvstring = "$computername,$mac,AIO-PostDeployment,$arch,CBB,MRZ,$language,PostInstall"

Write-Information "Gathered Data: $csvstring"
$cred = GetCreds

Write-Information "Adding Computer to Domain"
Add-Computer -DomainName $DomainName -Credential $cred

Write-Information "Running SCCM Client Setup. Please stand by"
New-PSDrive -Name "ClientDir" -PSProvider "FileSystem" -Root "$CMClientLocation" -Credential $cred
Start-Process -FilePath "$CMClientLocation\ccmsetup.exe" -ArgumentList "/mp:$CMServer SMSSITECODE=$CMSiteCode" -Passthru -NoNewWindow -Wait

Write-Information "Writing Import information"
New-PSDrive -Name "CSVImport" -PSProvider "FileSystem" -Root "\\$CMServer\CSVImport" -Credential $cred
$csvstring | Out-File "\\$CMServer\CSVImport\$(Get-Date -UFormat "%Y-%m-%d-%H-%M-%S").csv"

Stop-Transcript
