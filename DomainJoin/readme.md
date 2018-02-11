**Function**

This script is used to allow your helpdesk / OSD people to manually install "unusual" Hardware and then join the domain ensuring compliance by running a SCCM Task Sequence.

**Usage**

This script is for usage with the Add-Computer-to-SCCM Script.

* Create a Secure String from the password of your service account:  **replace the Key value!**

      $my_secure_password = read-host -assecurestring
      $my_encrypted_string = convertfrom-securestring $my_secure_password -Key (31, 2, 14, 123, 47, 231, 13, 5, 7, 8, 32, 3, 4, 5, 123, 2, 111, 121, 52, 18, 23, 11, 63, 22)


* Paste the String and Key into the script
* Make a copy of the SCCM Client accessible to all users
* Replace Placeholder Variables in script

**Support**

You can reach me at contact@steinhkl.de for support.
