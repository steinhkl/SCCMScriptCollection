# Add Computer to SCCM
# Imports Computer from CSV File into SCCM and adds predefined variables.
# Creates Backup of CSV and writes logs.
# Run this script as a scheduled task on your site-server
# Version 1.1 - Uses CM PS-Cmdlet and allows for "Domain Join Only" Computers
# Author: Klaus Steinhauer
# Contact: contact@steinhkl.de
# Date: 11.02.2018
# USE AT YOUR OWN RISK!

Import-Module "E:\Program Files\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1" -Force -ErrorAction Stop

# Base Vars
$SiteCode = "CMG"
$filepath="F:\SCCM_Import\CSVImport\"
$backuppath="F:\SCCM_Import\CSVImportBackup\"
$WMInamespace = "root\sms\site_CMG"
$SiteServer = "s0001.yourdomain.com"

$runtime=Get-Date -Format yyyyMMddHHmm
$logfile=$backuppath+$runtime+".log"
$resource = $false
$DefaultCollection = "YOUR-DEFAULT-COLLECTION"

# Check CSV file format.
function checkFormat ($importfile){
    $checks=get-content $importfile.fullname

    foreach ($check in $checks)
    {
        # Is it a CSV?
        if (!$check.split(",")) {
            Write-Error "$($_.fullname) is not a CSV File"
            return $false
        }
        else {
            $check=$check.split(",")
            # Do we have all parameters?
            if ($check.count -ne 8 -or $check[1].length -ne 17) {
                Write-Error "$($_.fullname) is not formated correctly."
                return $false
            }
        }
        Write-Information "$($_.fullname) was checked. Format Okay."
        return $true
    }

}
# find existing clients
function searchClient($name,$mac){
    $resource = $false
    # search by name
    $resource = Get-CMDevice -Name "$name"
    if (!$resource){
        Write-Information "Device Name $name not found."
        Write-Information "Searching for MAC-Address."
        # search by MAC. WMI Only.
        $resourceID = (Get-WmiObject -Class SMS_R_SYSTEM -Namespace $WMInamespace -ComputerName $SiteServer | Where-Object {$_.MACAddresses -eq "$mac"}).ResourceID
        # get resource by ID
        if ($resourceID){
            $resource = Get-CMDevice -ResourceId $resourceID
        }else{
            Write-Information "MAC-Address $mac not found."
            Write-Information "Object doesn't seem to exist yet."
        }
    }
    return $resource
}

function addVarToClient($resource,$varname,$varvalue){
    New-CMDeviceVariable -InputObject $resource -VariableName "$varname" -VariableValue "$varvalue" -IsMask 0 | Out-Null
    Write-Information "The Variable $varname was set to $varvalue ."
}

# Get all CSV Files
$importfiles= get-childitem -path $filepath -filter *.csv
# Exit if none are found
if (!$importfiles) { exit }
# Start logging
Start-Transcript $logfile -IncludeInvocationHeader

# Switch to SMS Drive
If((Get-Location).Drive.Name -ne $SiteCode){
        Try{Set-Location -path $SiteCode":" -ErrorAction Stop}
        Catch{Throw "Unable to connect to Site $SiteCode. Ensure that the Site Code is correct and that you have access."}
      }

$importfiles| ForEach-Object {
    Write-Information "Starting Processing of CSV File $_.name"
    # Copy files to backuppath
    Copy-Item $_.fullname $backuppath -Force
    Write-Information "$($_.fullname) was copied"

    # Check format and begin processing
    if (checkFormat $_){
        # Header format of the CSV file.
        $header = "Computername", "MACAddress", "Collection", "SMSTSOSArchitecture", "SMSTSOsVersion", "SMSTSNetwork", "SMSTSOSLanguage", "TypID"
        # Write to Array
        $array = Import-Csv $_.fullname -Header $header

        # For each line in CSV
        $array | ForEach-Object{
            Write-Information "Searching for existing Device."
            Write-Information "Computername: $($_.Computername) Mac-Address: $($_.MACAddress)"
            # Search for existing client
            $resource = searchClient -name "$($_.Computername)" -mac "$($_.MACAddress)"

            #####################################################
            # $Domain-Join #      $resource    #  !$resouce     #
            #####################################################
            #     YES      #       vars          # create, vars #
            #     NO       #  del, create, vars  # create, vars #
            #####################################################

            # $Domain-Join -eq NO
            if ($_.Collection -ne "AIO-PostDeployment"){
                if($resource){
                    #delete old client
                    Remove-CMDevice -InputObject $resource -Force
                    Write-Information "Client $($_.Computername) gelöscht"
                    # Wait for Device to be removed to avoid race condition (which causes a lot of weird errors!)
                    Start-Sleep -s 20
                }

                # add client
                Write-Information "Importing Computer into SCCM"
                Import-CMComputerInformation -ComputerName "$($_.Computername)" -MacAddress "$($_.MACAddress)" -CollectionName $DefaultCollection -ErrorAction Stop
                Write-Information "Client $($_.Computername) with Mac-Address $($_.MACAddress) was created."
                # give it some time.
                while (!$ResourceID)
                {
	                $ResourceID = $(get-cmdevice -Name "$($_.Computername)").ResourceID
	                Start-Sleep -Seconds 5
                }
            }
            # $Domain-Join -eq YES
            else {
                # !$resource
                if(!$resource){
                    # add client
                    Write-Information "Importing Computer into SCCM"
                    Import-CMComputerInformation -ComputerName "$($_.Computername)" -MacAddress "$($_.MACAddress)" -CollectionName $DefaultCollection -ErrorAction Stop
                    Write-Information "Client $($_.Computername) with Mac-Address $($_.MACAddress) was created."
                    # give it some time.
                    while (!$ResourceID)
                    {
	                    $ResourceID = $(get-cmdevice -Name "$($_.Computername)").ResourceID
	                    Start-Sleep -Seconds 5
                    }
                }
            }
            # Find the newly created Client
            $resource = searchClient -name "$($_.Computername)" -mac "$($_.MACAddress)"

            # Add Vars
            # This could be made prettier if you included the header in the CSV file and created a loop here
            addVarToClient -resource $resource -varname "SMSTSOSArchitecture" -varvalue "$($_.SMSTSOSArchitecture)"
            addVarToClient -resource $resource -varname "SMSTSOsVersion" -varvalue "$($_.SMSTSOsVersion)"
            addVarToClient -resource $resource -varname "SMSTSNetwork" -varvalue "$($_.SMSTSNetwork)"
            addVarToClient -resource $resource -varname "SMSTSOSLanguage" -varvalue "$($_.SMSTSOSLanguage)"
            addVarToClient -resource $resource -varname "TypID" -varvalue "$($_.TypID)"

            # Add Client to Collection
            $collection = Get-CMDeviceCollection -Name "$($_.Collection)"

            # check existing collection membership
            $collectionmembership = Get-CMDeviceCollectionDirectMembershipRule -CollectionId $collection.CollectionID -Resource $resource
            # if var is empty, computer is not in collection.
            if (!$collectionmembership){
                Add-CMDeviceCollectionDirectMembershipRule -CollectionId $collection.CollectionID -Resource $resource
            }


        }
        Write-Information "$($_.fullname) was processed and is being deleted."
        Remove-Item $_.fullname
    }
    else{
        Write-Error "Format Error in $_.fullname"
        exit
    }
}

Stop-Transcript
