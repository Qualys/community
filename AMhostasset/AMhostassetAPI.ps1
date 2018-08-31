# Set your Qualys username & password
$QualysUsername = 'username'
$QualysPassword = 'password'

# Change the Folder to which you want to save the XML results.

$location = "C:\Users\sdutta\Desktop\Accenture script\script"

# Change the limit to number to the number of results that needs to be fetched in a XML file, Maximum can be 1000.

$limit = '10'



# Qualys US POD 1 base URL
$QualysPlatform = 'qualysapi.qualys.com'
$num = '1'





# This section forms a string with the username & password in the 'Basic Authentication' standard format
$BasicAuthString = [System.text.Encoding]::UTF8.GetBytes("$QualysUsername`:$QualysPassword")
$BasicAuthBase64Encoded = [System.Convert]::ToBase64String($BasicAuthString)
$BasicAuthFormedCredential = "Basic $BasicAuthBase64Encoded"


# Form a key/value hashable with the HTTP headers we'll be sending in the HTTP request
$HttpHeaders = @{'Authorization' = $BasicAuthFormedCredential; 
                 'content-type'='text/xml'}




# Set the URL
$URL = "https://$QualysPlatform/qps/rest/2.0/search/am/hostasset"

# Passing the XML post request in body variable.

$body = @"
<ServiceRequest> 
<filters> 
<Criteria field="tagName" operator="EQUALS">Cloud Agent</Criteria>
</filters>
<preferences>
 <limitResults>$limit</limitResults>
 </preferences>
</ServiceRequest>
"@

# Enabling TLS 1.2 as by default Powershell will connect using TLS v1 which is not supported.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12



$shubh = Invoke-WebRequest -Method POST -Uri $URL -Body $body -Headers $HttpHeaders -outfile "$location\$num-asset.xml"

$Job = Start-Job -ScriptBlock {$shubh}



while ($job.state -ne 'Completed' )

{


}

#Fetch the value the XML file in $path variable and then fetch the value of lastId.


$xml = [xml](get-content "$location\$num-asset.xml")

#$path = "$location\$num-asset.xml"
#$XMLDocument=New-Object System.XML.XMLDocument
#$XMLDocument.Load($path)

#$lastId = $XMLDocument.ServiceResponse.lastId

$lastId = $xml.ServiceResponse.lastId

write-host Done_generating_XML_file_for_lastId_$lastId

function Get-QualysVMReport {
While ( ($lastId -gt 1))
{

$bodyinf = @"
<ServiceRequest> 
<filters>
<Criteria field="tagName" operator="EQUALS">Cloud Agent</Criteria>
<Criteria field="id" operator="GREATER">$lastid</Criteria>
</filters>
<preferences>
 <limitResults>$limit</limitResults>
 </preferences>
</ServiceRequest>
"@

$shubh1 = Invoke-WebRequest -Method POST -Uri $URL -Body $bodyinf -Headers $HttpHeaders -outfile "$location\$lastId-asset.xml"


$Job1 = Start-Job -ScriptBlock {$shubh1}



while ($job1.state -ne 'Completed' )

{


}

$xml = [xml](get-content "$location\$lastid-asset.xml")



$lastId = $xml.ServiceResponse.lastId


#$path = "$location\$lastId-asset.xml"
#$XMLDocument=New-Object System.XML.XMLDocument
#$XMLDocument.Load($path)

#$lastId = $XMLDocument.ServiceResponse.lastId

#return QualysVMReport
write-host Done_generating_XML_file_for_lastId_$lastId


}


}

get-QualysVMReport


