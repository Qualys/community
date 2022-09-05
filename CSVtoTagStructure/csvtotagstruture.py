import QualysAPI
import configparser
import argparse
import xml.etree.ElementTree as ET
import sys
import csv
from os import path
import xml.dom.minidom


def createTagSearchServiceRequest(tagName: str):
    criteria: ET.Element
    sr = ET.Element('ServiceRequest')
    filters = ET.SubElement(sr, 'filters')
    criteria = ET.SubElement(filters, 'Criteria')
    criteria.set('field', 'name')
    criteria.set('operator', 'EQUALS')
    criteria.text = tagName
    return sr


def createFilteredServiceRequest():
    criteria: ET.Element
    sr = ET.Element('ServiceRequest')
    filters = ET.SubElement(sr, 'filters')
    criteria = ET.SubElement(filters, 'Criteria')
    criteria.set('field', 'ruleType')
    criteria.set('operator', 'EQUALS')
    criteria.text = 'NETWORK_RANGE'
    return sr


def createServiceRequest(tagName, tagColour: str = None):
    sr = ET.Element('ServiceRequest')
    data = ET.SubElement(sr, 'data')
    tag = ET.SubElement(data, 'Tag')
    name = ET.SubElement(tag, 'name')
    name.text = tagName
    if tagColour is not None:
        tcolour = ET.SubElement(tag, 'color')
        tcolour.text = tagColour
    children = ET.SubElement(tag, 'children')
    set = ET.SubElement(children, 'set')
    return sr


def createStaticTag(tagName: str, tagColour: str = None):
    tag = ET.Element('Tag')
    tname = ET.SubElement(tag, 'name')
    tname.text = tagName
    if tagColour is not None:
        tcolour = ET.SubElement(tag, "color")
        tcolour.text = tagColour
    children = ET.SubElement(tag, 'children')
    set = ET.SubElement(children, 'set')

    return tag


def createLeafTag(tagName: str, rule: str, tagColour: str = None):
    tag = ET.Element('Tag')
    name = ET.SubElement(tag, 'name')
    name.text = tagName
    if tagColour is not None:
        tcolour = ET.SubElement(tag, "color")
        tcolour.text = tagColour
    rtype = ET.SubElement(tag, 'ruleType')
    rtype.text = 'NETWORK_RANGE'
    rtext = ET.SubElement(tag, 'ruleText')
    rtext.text = rule

    return tag

def podPicker(pod: str):
    switcher = {
        'US01': 'https://qualysapi.qualys.com',
        'US02': 'https://qualysapi.qg2.apps.qualys.com',
        'US03': 'https://qualysapi.qg3.apps.qualys.com',
        'EU01': 'https://qualysapi.qualys.eu',
        'EU02': 'https://qualysapi.qg2.apps.qualys.eu',
        'IN01': 'https://qualysapi.qg1.apps.qualys.in',
        'UK01': 'https://qualysapi.qg1.apps.qualys.co.uk'
    }
    return switcher.get(pod, "invalid")


if __name__ == '__main__':
    # Setup script arguments parser using argparser
    parser = argparse.ArgumentParser()
    parser.add_argument('username', help='API Username')
    parser.add_argument('password', help='API User Password')
    parser.add_argument('qualyspod', help='Location of Qualys Subscription [US01|US02|US03|EU01|EU02|IN01|PCP]')
    parser.add_argument('-f', '--configfile', help='Relative path to configuration file (default: config.ini')
    parser.add_argument('-p', '--proxyenable', action='store_true', help='Use HTTPS Proxy (required -u or --proxyurl')
    parser.add_argument('-u', '--proxyurl', help='Proxy URL (requires -p or --proxyenable)')
    parser.add_argument('-a', '--apiurl', help='API URL for Qualys PCP Subscriptions.')
    parser.add_argument('-c','--configsection', help='Section of configuration file to use (default: \'DEFAULT\')')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-s', '--simulate', action='store_true', help='Simulate tag creation, output XML to console'
                                                                      'and do not make API calls')
    parser.add_argument('-e', '--evaluate', action='store_true', help='Re-evaluate all Asset Tags after creation')
    parser.add_argument('--deleteandreplace', action='store_true', help='Delete existing Root tags of the same name '
                                                                          'and replace them with the generated tags.\n'
                                                                          'WARNING: THIS IS A DESTRUCTIVE OPERATION')
    args = parser.parse_args()

    # Set the API URL
    url = ""
    if args.qualyspod == 'PCP':
        if args.pcpurl is None:
            print('FATAL: qualyspod is PCP but pcpurl not specified')
            sys.exit(1)
        url = args.pcpurl
    else:
        url = podPicker(args.qualyspod)
        if url == 'invalid':
            print('FATAL: qualyspod \'%s\' not recognised' % args.qualyspod)
            print('       Select one of US01, US02, US03, EU01, EU02, IN01, PCP')
            sys.exit(2)

    # Setup the API handler
    api = QualysAPI.QualysAPI(svr=url, usr=args.username, passwd=args.password, enableProxy=args.proxyenable,
                              proxy=args.proxyurl, debug=args.debug)

    # Set the HTTPS Proxy URL if required
    enableproxy = False
    proxyurl: str
    if args.proxyenable:
        enableproxy = True
        if args.proxyurl is None or args.proxyurl == '':
            print('FATAL: -p or --proxyenable specified without -u or --proxyurl, or with empty URL')
        else:
            proxyurl = args.proxyurl

    # Read the configuration file
    if args.configfile is not None:
        configfile = args.configfile
    else:
        configfile = "config.ini"

    config = configparser.ConfigParser()
    if not path.exists(args.configfile):
        print('FATAL: configfile %s does not exist' % args.configfile)
        sys.exit(3)
    config.read(args.configfile)

    # Validate the configuration file
    section = 'DEFAULT'
    if args.configsection is not None:
        if args.configsection in config.keys():
            section = args.configsection
        else:
            print('FATAL: Configuration section \'%s\' does not exist in %s' % (args.configsection, args.configfile))
            sys.exit(4)

    if 'CSVDepth' not in config[section]:
        print('FATAL: CSVDepth missing from %s section of configuration file' % section)
        sys.exit(5)

    if 'CSVFile' not in config[section]:
        print('FATAL: CSVFile missing from %s section of configuration file' % section)
        sys.exit(5)
    inputfile = config[section]['CSVFile']
    if not path.exists(inputfile):
        print('FATAL: CSVFile %s does not exist' % inputfile)
        sys.exit(5)

    # First Pass - create ServiceRequests for each root tag
    #              and store them in a dictionary object with the tag name as the key
    servicerequests = {}

    # Read CSV file and create tag structure dict
    with open(inputfile, newline='') as csvfile:
        rowreader = csv.reader(csvfile, delimiter=',', quotechar='"')

        for row in rowreader:

            # Set c to be the colour value as defined in the configuration file
            # This will the tag-specific value defined by the Root Tag name or the default defined by TagColour
            if row[0] in config[section]:
                c = config[section][row[0]]
            else:
                c = config[section]['TagColour']
            if row[0] not in servicerequests.keys():
                sr = createServiceRequest(tagName=row[0], tagColour=c)
                servicerequests[row[0]] = sr

    csvfile.close()

    # Second Pass - iterate through CSV file and build tag hierarchy
    with open(inputfile, newline='') as csvfile:
        rowreader = csv.reader(csvfile, delimiter=',', quotechar='"')

        for row in rowreader:
            # Declare root and parent variables to be ElementTree.Element types
            root: ET.Element
            parent: ET.Element

            # Get the ServiceRequest XML for the root tag
            root = servicerequests.get(row[0])
            # Set the parent to be the 'set' element of the root XML for now
            parent = root

            # Set d to be the integer value of the defined CSV Depth from the configuration file
            d = int(config[section]['CSVDepth'])

            # Set c to be the colour value as defined in the configuration file
            # This will the tag-specific value defined by the Root Tag name or the default defined by TagColour
            if row[0] in config[section]:
                c = config[section][row[0]]
            else:
                c = config[section]['TagColour']

            # Start iterating through the columns in the row
            for i in range(1, d):
                if args.debug:
                    print("********************")
                    print("Current XML\n")
                    dom = xml.dom.minidom.parseString((ET.tostring(root, encoding='utf-8', method='xml')).decode())
                    print("%s" % dom.toprettyxml(indent='  '))
                    print("Current Root Tag : %s" % row[0])
                    print("Current Tag : %s (i=%s)" % (row[i], i))
                    print("********************")
                if i == d-1:
                    # This is the last column which defines a tag, therefore this is a leaf tag
                    if root.find(".//*[name='%s']" % row[i]) is None:
                        # We did not find an existing leaf tag so we create one and add it to the parent's 'set' element
                        tag = createLeafTag(tagName=row[i], tagColour=c, rule=row[d])
                        parent = parent.find('.//set')
                        parent.append(tag)
                    else:
                        # We found an existing leaf tag so we find the ruleText and add the IP to it
                        tag = root.find(".//*[name='%s']" % row[i])
                        ruleText = tag.find(".//ruleText")
                        ruleText.text = '%s,%s' % (ruleText.text, row[d])

                else:
                    if root.find(".//*[name='%s']" % row[i]) is None:
                        # We did not find the current tag name in the root, so we create a Tag and add it to the
                        # current parent
                        tag = createStaticTag(tagName=row[i], tagColour=c)
                        parent = parent.find('.//set')
                        parent.append(tag)
                        parent = tag
                    else:
                        # We did find the current tag name in the parent, so set the new parent to be this tag
                        tag = root.find(".//*[name='%s']" % row[i])
                        parent = tag
    csvfile.close()

    if args.simulate:
        print("================================================================================")
        for k in servicerequests.keys():
            sr: ET.Element

            print('Printing XML for %s' % k)
            sr = servicerequests.get(k)

            dom = xml.dom.minidom.parseString((ET.tostring(sr, encoding='utf-8', method='xml')).decode())
            print("%s" % dom.toprettyxml(indent='  '))
            print("--------------------------------------------------------------------------------")
    else:
        print("Starting API calls")

        for k in servicerequests.keys():
            sr: ET.Element
            resp: ET.Element

            if args.deleteandreplace:
                # First we have to find the ID of the root tag we want to delete
                print("Getting ID for tag %s : " % k, end='')
                sr = createTagSearchServiceRequest(k)
                fullurl = "%s/qps/rest/2.0/search/am/tag" % api.server
                resp = api.makeCall(url=fullurl, payload=(ET.tostring(sr, encoding='utf-8', method='xml')).decode())
                success = resp.find('.//responseCode')
                if success is None:
                    print("Failed\nFATAL: API Call failed, no <responseCode> received in reply")
                    if args.debug:
                        domxml = xml.dom.minidom.parseString(
                            (ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                        print("%s" % domxml.toprettyxml(indent='  '))
                    sys.exit(6)
                if success.text == "SUCCESS":
                    print("Success")
                else:
                    print("Failed")
                    if args.debug:
                        domxml = xml.dom.minidom.parseString(
                            (ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                        print("%s" % domxml.toprettyxml(indent='  '))
                    # When the find process fails, and delete-and-replace is activated, we cannot continue
                    # because we cannot find the tag to delete, therefore we cannot delete the tag, therefore we cannot
                    # create the new tag in its place.
                    print("Cannot continue, exiting")
                    sys.exit(7)
                # We have success, but that doesn't mean our search is over.  If the count is 0 then we have nothing
                # to do, but if the count is > 1 then we have to stop as we may inadvertently delete the wrong tag
                count = int(resp.find('.//count').text)
                if count == 0:
                    print("Search returned zero results")
                elif count > 1:
                    print("FATAL: Search returned more than one result, cannot continue")
                    sys.exit(7)
                else:
                    # Only 1 Tag found, grab the <id> from it
                    tagid = resp.find('.//id').text

                    # Now we delete the tag
                    print("Deleting tag with ID %s : " % tagid, end='')
                    fullurl = "%s/qps/rest/2.0/delete/am/tag/%s" % (api.server, tagid)
                    resp = api.makeCall(url=fullurl, payload='')
                    success = resp.find('.//responseCode')
                    if success is None:
                        print("Failed\nFATAL: API Call failed, no <responseCode> received in reply")
                        if args.debug:
                            domxml = xml.dom.minidom.parseString(
                                (ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                            print("%s" % domxml.toprettyxml(indent='  '))
                        sys.exit(6)
                    if success.text == "SUCCESS":
                        print("Success")
                    else:
                        print("Failed")
                        if args.debug:
                            domxml = xml.dom.minidom.parseString(
                                (ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                            print("%s" % domxml.toprettyxml(indent='  '))
                        # When the find process fails, and delete-and-replace is activated, we cannot continue
                        # because we cannot delete the tag, therefore we cannot create the new tag in its place.
                        print("Cannot continue, exiting")
                        sys.exit(7)

            fullurl = "%s/qps/rest/2.0/create/am/tag" % api.server
            sr = servicerequests.get(k)
            print("Creating %s : " % k, end='')
            resp = api.makeCall(url=fullurl, payload=(ET.tostring(sr, encoding='utf-8', method='xml')).decode())
            success = resp.find('.//responseCode')
            if success is None:
                print("Failed\nFATAL: API Call failed, no <responseCode> received in reply")
                if args.debug:
                    domxml = xml.dom.minidom.parseString((ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                    print("%s" % domxml.toprettyxml(indent='  '))
                sys.exit(6)
            if success.text == "SUCCESS":
                print("Success")
            else:
                print("Failed")
                if args.debug:
                    domxml = xml.dom.minidom.parseString((ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                    print("%s" % domxml.toprettyxml(indent='  '))

        if args.evaluate:
            print("Evaluating Tags : ", end='')
            evalSR = createFilteredServiceRequest()
            fullurl = "%s/qps/rest/2.0/evaluate/am/tag" % api.server
            resp = api.makeCall(url=fullurl, payload=(ET.tostring(evalSR, encoding='utf-8', method='xml')).decode())
            success = resp.find('.//responseCode')
            if success is None:
                print("FATAL: API Call failed, no <responseCode> received in reply")
                if args.debug:
                    domxml = xml.dom.minidom.parseString((ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                    print("%s" % domxml.toprettyxml(indent='  '))
                sys.exit(6)
            if success.text == "SUCCESS":
                count = resp.find('.//count').text
                print("Success, evaluation started for %s tags" % count)
            else:
                print("Failed")
                if args.debug:
                    domxml = xml.dom.minidom.parseString((ET.tostring(resp, encoding='utf-8', method='xml')).decode())
                    print("%s" % domxml.toprettyxml(indent='  '))
