<?php
$username=“ENTER_YOUR_USERNAME”; 
$password=“ENTER_YOUR_PASSWORD”; 
$ch = curl_init();
$cookieJar = dirname(__FILE__) . '/cookie.txt';
curl_setopt($ch, CURLOPT_URL, "https://qualysapi.qualys.com/api/2.0/fo/session/"); 
curl_setopt($ch, CURLOPT_HTTPHEADER, array('X-Requested-With: Jonas'));
curl_setopt($ch, CURLOPT_COOKIEJAR, $cookieJar);
curl_setopt($ch, CURLOPT_POST, 1);
curl_setopt($ch, CURLOPT_POSTFIELDS, "action=login&username=$username&password=$password");
$result = curl_exec ($ch) or die(curl_error($ch)); 
echo $result; 
echo curl_error($ch); 
$ch = curl_init ("https://qualysapi.qualys.com/api/2.0/fo/appliance/");
curl_setopt($ch, CURLOPT_HTTPHEADER, array('X-Requested-With: Jonas'));
curl_setopt ($ch, CURLOPT_COOKIEFILE, $cookieJar); 
curl_setopt ($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, 1);
curl_setopt($ch, CURLOPT_POSTFIELDS, "action=list&output_mode=full");
$output = curl_exec ($ch);
echo $output;
curl_close ($ch);
?>


