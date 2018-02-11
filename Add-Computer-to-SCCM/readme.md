**Function**

The script is for the following scenario: You have created (or plan to create) an All-In-One OSD Task Sequence which utilizes CfgMgr Device Variables to allow for different machines to be deployed with the same Task Sequence. Because you have to support more configurations than you would like maintaining all those task seuqeunces has become very painfull.

**This script deletes existing Computer Objects from SCCM by default before recreating them. This means your Computer will lose all Collection memberships!**

The Script assumes the following supported variants:
* Different Architecture (x86, x64)
* Different OS Version (CB, CBB, LTSB for Windows 10 [now called differently but the same applies])
* Different Networks (Join Domain / Join Workgroup)
* Different Languages

Each of these Variants is saved in a Computer Variable in SCCM:

* Architecture -  "SMSTSOSArchitecture"
* OS Version - "SMSTSOsVersion"
* Network - "SMSTSNetwork"
* Language - "SMSTSOSLanguage"

and as an added bonus we also add a variable for driver installation: "TypID" - Which can be used to reliably determine the correct driver Package.

Instead of having to maintain upwards of 10 Task Sequences you now only have to update and maintain one.


**Usage**

* Adjust Base Variables to your site.
* Create a Directory where CSV files can be put by your OSD Crew and share it on your network.
* Create a tool for you OSD Crew to easily create CSV Data of the following structure:

      "Computername", "MACAddress", "Collection", "SMSTSOSArchitecture", "SMSTSOsVersion", "SMSTSNetwork", "SMSTSOSLanguage", "TypID"
* Create a Scheduled Task to execute the import script every 5 minutes.


**Support**

You can reach me at contact@steinhkl.de for support.

**Additional Note**

This script supports an edge case: Making manually installed computers run a task sequence when joining the domain in order to ensure compliance. It is yet to be documented.
See DomainJoin Folder.
