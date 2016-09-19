This Script uses the Windows Setup built in Scan capabilities to scan a computer for conflicting Applications.

- It will copy the resulting \~Panther files to a destination of your choosing.
- It creates a Log file containing the Computername as well as the Setup exit code.
- If the exit code is "0xC1900208" (Incompatibility) it will create an XML File in the Computer Directory containing the offending entry.

You could Deploy this to your all Systems Collection to get a glimpse at what will go wrong when you try upgrading to Windows 10 without the User actually noticing.
