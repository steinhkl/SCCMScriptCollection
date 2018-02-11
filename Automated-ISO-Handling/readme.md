**WARNING: DO NOT USE THIS ON PRODUCTION TS WITHOUT PRIOR TESTING. Then again if you are smart enough to do so...**


This script is meant to automate all steps after downloading new Windows 10 ISOs from VLSC:
* Extract ISO Files to given Location
* Import Extracted Files into SCCM as "Operating System Image" and "Operating System Upgrade Package"
* Modify your AIO Install Task Sequence and your AIO IPU Task Sequence

**Naming Conventions**

The folders containing the files will be named as follows:

    Windows10_[RELEASE]_[BRANCH]_[ARCHITECTURE]_[LANGUAGE]

Example : 

    Windows10_16.07_CB_x64_EN

The Script also assumes you will use the Languages English and German.
Accordingly, when downloaded with German Locale, this is what the Isos are named like:

    SW_DVD5_WIN_ENT_10_1607_64BIT_English_MLF_X21-07102.ISO

As of 16.07CBB Microsoft has Changed the Name of the ISO file to:

    SW_DVD5_WIN_ENT_10_1607.1_64BIT_English_MLF_X21-27030.ISO

Either Rename the ISO or expect the new OS Images in SCCM to be named as such:

    Windows10_16.07.1_CB_x64_EN

Please also Note:
Your Apply Operating System Step(s) / Install Upgrade Package Step(s) Must be Named as follows:

    [BRANCH] [ARCHITECTURE] [LANG]
    Example: "CBB x64 DE"

**Support**

You can reach me at contact@steinhkl.de for support.
