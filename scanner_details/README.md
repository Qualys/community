scanner_details
===============

Output the complete scanner details as they are available in the GUI.  The IP and VLAN info will be included. 

The XML output of the script will look like this:

    <APPLIANCE>
        <ID>75414</ID>
        <NAME>Scanner</NAME>
        <NETWORK_ID>0</NETWORK_ID>
        <SOFTWARE_VERSION></SOFTWARE_VERSION>
        <RUNNING_SCAN_COUNT>0</RUNNING_SCAN_COUNT>
        <STATUS>Offline</STATUS>
        <MODEL_NUMBER>cvscanner</MODEL_NUMBER>
        <SERIAL_NUMBER>0</SERIAL_NUMBER>
        <ACTIVATION_CODE>20XXXXXXXXXX</ACTIVATION_CODE>
        <INTERFACE_SETTINGS>
          <INTERFACE>lan</INTERFACE>
          <IP_ADDRESS></IP_ADDRESS>
          <NETMASK>128.0.0.0</NETMASK>
          <GATEWAY>128.0.0.0</GATEWAY>
          <LEASE>Static</LEASE>
          <IPV6_ADDRESS></IPV6_ADDRESS>
          <SPEED></SPEED>
          <DUPLEX>Unknown</DUPLEX>
          <DNS>
            <DOMAIN></DOMAIN>
            <PRIMARY>128.0.0.0</PRIMARY>
            <SECONDARY>128.0.0.0</SECONDARY>
          </DNS>
        </INTERFACE_SETTINGS>
        <INTERFACE_SETTINGS>
          <SETTING>Disabled</SETTING>
          <INTERFACE>wan</INTERFACE>
          <IP_ADDRESS></IP_ADDRESS>
          <NETMASK>128.0.0.0</NETMASK>
          <GATEWAY>128.0.0.0</GATEWAY>
          <LEASE>Static</LEASE>
          <SPEED></SPEED>
          <DUPLEX>Unknown</DUPLEX>
          <DNS>
            <PRIMARY>128.0.0.0</PRIMARY>
            <SECONDARY>128.0.0.0</SECONDARY>
          </DNS>
        </INTERFACE_SETTINGS>
        <PROXY_SETTINGS>
          <SETTING>Disabled</SETTING>
          <PROXY>
            <TYPE>primary</TYPE>
            <IP_ADDRESS>128.0.0.0</IP_ADDRESS>
            <PORT></PORT>
            <USER></USER>
          </PROXY>
          <PROXY>
            <TYPE>secondary</TYPE>
            <IP_ADDRESS>128.0.0.0</IP_ADDRESS>
            <PORT></PORT>
            <USER></USER>
          </PROXY>
        </PROXY_SETTINGS>
        <VLANS>
          <SETTING>Disabled</SETTING>
        </VLANS>
        <STATIC_ROUTES />
        <ML_LATEST></ML_LATEST>
        <ML_VERSION updated="yes"></ML_VERSION>
        <VULNSIGS_LATEST></VULNSIGS_LATEST>
        <VULNSIGS_VERSION updated="yes"></VULNSIGS_VERSION>
        <ASSET_GROUP_COUNT>0</ASSET_GROUP_COUNT>
 
Modify the script to use your username, password and API endpoint.