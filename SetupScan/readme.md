The Script SetupScan.ps1 uses the Windows Setup built in Scan capabilities to scan a computer for conflicting Applications, Hardware, Drivers and other.

- If an error occurs it will copy the resulting \~Panther files to a destination of your choosing.
- It creates a Log file containing the Computer name as well as the Setup exit code.

**Usage:**

The Script relies on a naming scheme for the extracted ISOs of Windows 10 which should look like this:

Windows10_[RELEASE]_[BRANCH]_[ARCHITECTURE]_[LANGUAGE]

Example: Windows10_16.07_CB_x64_EN

**Parameters:**  
strLogPath : Where the logfiles will be copied (This should be an UNC Path if you plan to run the script on multiple Computers)  
strRootSetupPath: Where you store the extracted ISOs of Windows 10  
strOSVersion: Which Release you wish to scan against  
strCred: The Credentials of your Domain Account to copy the logfiles to strLogPath  
strUser: The Login of your Domain Account to copy the logfiles to strLogPath  

**Note:** $strUser has to contain your Domain Name. Eg. DOMAIN\SCCM-Scripts

**Deploying the Script with SCCM**  
*Create a package*  
1. Create a package containing the SetupScan.ps1 Script using "Do not create a program"  
2. Edit the Package and change the Data Source to the location of your Script  
3. Distribute the content of your package  
*Create a Task Sequence*  
1. Create a new custom Task Sequence  
2. Add a Sequence Step to "Run Powershell Script"  
3. Select your newly created Package  
4. Set the Script name: "SetupScan.ps1"  
5. Set your Parameters:  -strUser DOMAIN\SCCM-Script  -strCred XXXX -strLogPath "\\UNC\OSD\!Logfiles" -strRootSetupPath "\\UNC\!OSD" -strOsVersion "Windows10_16.07_CB"  
6. Deploy the Script to a collection  

**Using the Script in your In-Place-Upgrade Task Sequence**  
If you want to use this script in your IPU TS, simply copy the above created "Run Powershell Script" into your TS and make sure to add the following condition before running the next step:  
TS Variable "_SMSTSLastActionRetCode" equals "0".
