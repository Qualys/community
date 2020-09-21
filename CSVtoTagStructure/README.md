# csvtotagstructure.py #

This script will read a CSV file and construct a Qualys Asset Tag structure.  The CSV may contain any number of columns,
 each denoting a level of the hierarchical tag structure.  The depth of the structure is specified in the configuration 
 file (see below).  The final column in the CSV must be an IP address or CIDR range. An example CSV file is provided in 
 example.csv.

The configuration file contains information about the CSV and target tags.  Multiple configuration sections may exist in
 the configuration file.  Each section may define separate configuration parameters.  An example configuration file is 
 provided in config.ini

The script requires an API Username and the password for that username.  These are used to authenticate to the Qualys 
API service.  The API service used is determined by the POD on which your subscription is hosted. If you do not know 
which POD your subscription is hosted on, use the following guide based on the URL used to access the Qualys UI.

```text
POD         URL
US01        https://qualysguard.qualys.com
US02        https://qualysguard.qg2.apps.qualys.com
US03        https://qualysguard.qg3.apps.qualys.com
EU01        https://qualysguard.qualys.eu
EU02        https://qualysguard.qg2.apps.qualys.eu
IN01        https://qualysguard.qg1.apps.qualys.in
``` 

## Configuration
The configuration file requires the following lines

* Section Header (e.g. [DEFAULT])
* CSVDepth: Depth of tag structure (e.g. 3)
* TagColour: Default tag colour in #RGB format (e.g. #FF0000)

### Colouring Tags
By default tags will be created with the default colour specified by the TagColour value.  In addition, tags colours may 
also be defined within the configuration file by specifying the Root Tag Name (column 1 in the CSV file) as the parameter 
and the colour as an #RGB value.

```text
RootTag1 = #FF0000
RootTag2 = #FF0011
```

All child tags will be coloured the same as its root tag

### Example Configuration File (included as config.ini)
The following example file is provided together with the CSV files referenced by the configuration.
```text
[DEFAULT]
CSVFile = example-3deep.csv
CSVDepth = 3
TagColour = #FF0000
RootTag1 = #00FF00
RootTag2 = #0000FF

[2deep]
CSVFile = example-2deep.csv
CSVDepth = 2
TagColour = #FF0000
RootTag1 = #00FF00
RootTag2 = #0000FF

[3deep]
CSVFile = example-3deep.csv
CSVDepth = 3
TagColour = #FF0000
RootTag1 = #00FF00
RootTag2 = #0000FF

[4deep]
CSVFile = example-4deep.csv
CSVDepth = 4
TagColour = #FF0000
RootTag1 = #00FF00
RootTag2 = #0000FF
```

## Usage
```text
$ python3.7 csvtotagstruture.py -h
usage: csvtotagstruture.py [-h] [-f CONFIGFILE] [-p] [-u PROXYURL] [-a APIURL]
                           [-c CONFIGSECTION] [-d] [-s] [-e]
                           [--deleteandreplace]
                           username password qualyspod

positional arguments:
  username              API Username
  password              API User Password
  qualyspod             Location of Qualys Subscription
                        [US01|US02|US03|EU01|EU02|IN01|PCP]

optional arguments:
  -h, --help            show this help message and exit
  -f CONFIGFILE, --configfile CONFIGFILE
                        Relative path to configuration file (default:
                        config.ini
  -p, --proxyenable     Use HTTPS Proxy (required -u or --proxyurl
  -u PROXYURL, --proxyurl PROXYURL
                        Proxy URL (requires -p or --proxyenable)
  -a APIURL, --apiurl APIURL
                        API URL for Qualys PCP Subscriptions.
  -c CONFIGSECTION, --configsection CONFIGSECTION
                        Section of configuration file to use (default:
                        'DEFAULT')
  -d, --debug           Enable debug output
  -s, --simulate        Simulate tag creation, output XML to consoleand do not
                        make API calls
  -e, --evaluate        Re-evaluate all Asset Tags after creation
  --deleteandreplace    Delete existing Root tags of the same name and replace
                        them with the generated tags. WARNING: THIS IS A
                        DESTRUCTIVE OPERATION
```

Run the script in the following way to output the XML structure based on the example configuration and CSV files without
creating them in your subscription.

```commandline
$ python3.7 csvtotagstruture.py username password EU01 -f config.ini -c DEFAULT -s
```