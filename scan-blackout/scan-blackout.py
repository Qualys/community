import QualysAPI

import configparser
import xml.etree.ElementTree as ET
from datetime import datetime
from time import sleep


def createapi(user,passw, svr,proxy, enableProxy, debug):
    """Create a QualysAPI object for interaction with the Qualys API
    Returns the QualysAPI object"""

    api = QualysAPI.QualysAPI(svr=svr, usr=user, passwd=passw, proxy=proxy, enableProxy=enableProxy, debug=debug)

    return api


def readconfig(configfile='config.ini'):
    """Read configuration file"""
    lconfig=configparser.ConfigParser()
    lconfig.read(configfile)
    return lconfig


def getscanjobs(api: QualysAPI.QualysAPI, debug=False):
    """getscanjobs
    Get a list of running and queued scan jobs from the subscription
        api:    a QualysAPI object, used to make the API call
        debug:  if True, will output debug information to stdout

    Returns a list of scan refs"""

    scanlist = []
    response: ET.Element

    url = "%s/api/2.0/fo/scan/?action=list&state=Running,Queued" % api.server
    if debug:
        print("getscanjobs: URL to use = %s" % url)
    response = api.makeCall(url=url)

    for ref in response.findall('.//REF'):
        scanlist.append(ref.text)

    return scanlist


def pausescan(scanref, api: QualysAPI.QualysAPI, debug=False):
    """pausescan
    Pause a running or queued scan job
        scanref:    Scan reference for job to pause
        api:        a QualysAPI object, used to make the API call
        debug:      if True, will output debug information to stdout

    Returns nothing"""
    url = 'https://%s/api/2.0/fo/scan/?action=pause&scan_ref=%s' % (api.server, scanref)
    oldDebug = False

    if debug:
        oldDebug = api.debug
        api.debug = True
    api.makeCall(url=url)
    if debug:
        api.debug = oldDebug


def resumescan(scanref, api: QualysAPI.QualysAPI, debug=False):
    """unpausescan
    Unpause a previously paused scan job
        scanref:    Scan reference for job to unpause
        api:        a QualysAPI object, used to make the API call
        debug:      if True, will output debug information to stdout

    Returns nothing"""
    url = 'https://%s/api/2.0/fo/scan/?action=resume&scan_ref=%s' % (api.server, scanref)
    oldDebug = False

    if debug:
        oldDebug = api.debug
        api.debug = True
    response = api.makeCall(url=url)
    if debug:
        api.debug = oldDebug


def recordaction(action, logfile, debug=False):
    """recordaction
    Record an action to a log file
        action:     string value containing action to record
        logfile:    location of the file to record actions to
        debug:      if True, will output debug information to stdout"""

    if debug:
        print("recordaction: Opening %s for appending" % logfile)
    log = open(logfile, 'a')
    actiontext = '%s: %s' % (datetime.now().strftime('%a %d-%m-%Y %H:%M:%S'), action)
    if debug:
        print("recordaction: Writing %s to %s" % (actiontext, logfile))
    log.write(actiontext)

# This is the script entry point
if __name__ == '__main__':
    print("scan-blackout: Startup")

    configfile = 'config.ini'

    config = readconfig(configfile)

    endhour = config['DEFAULT']['EndHour']
    endmin = config['DEFAULT']['EndMin']
    pollinterval = int(config['DEFAULT']['PollInterval'])
    logfile = config['DEFAULT']['LogFile']

    apiserver = config['DEFAULT']['APIServer']
    apiuser = config['DEFAULT']['APIUser']
    apipass = config['DEFAULT']['APIPass']
    proxy = config['DEFAULT']['ProxyAddress']
    useproxy = config['DEFAULT']['UseProxy']

    if useproxy == "True" or useproxy == "Yes":
        enableproxy = True
    else:
        enableproxy = False

    debug = config['DEFAULT']['DebugOutput']
    if debug == "True" or debug == "Yes":
        enabledebug = True
    else:
        enabledebug = False

    masterlist = []

    recordaction(logfile=logfile, action='Script Starting', debug=enabledebug)

    api = QualysAPI.QualysAPI(svr=apiserver, usr=apiuser, passwd=apipass, proxy=proxy, enableProxy=enableproxy,
                              debug=enabledebug)

    scanlist = getscanjobs(api, enabledebug)
    if enabledebug:
        print("scan-blackout: Found %s scan jobs running or queued" % str(len(scanlist)))
    for scan in scanlist:
        pausescan(scanref=scan, api=api, debug=enabledebug)
        recordaction(action='Paused Scan %s' % scan, logfile=logfile, debug=enabledebug)
        if enabledebug:
            print("scan-blackout: Adding %s to master scan list" % scan)
        masterlist.append(scan)

    nowdate = datetime.now().strftime("%Y-%m-%d")
    enddate = datetime.strptime("%s %s:%s" % (nowdate, endhour, endmin), "%Y-%m-%d %H:%M")
    if enabledebug:
        print("scan-blackout: Setting end date/time to %s" % enddate.strftime("%Y-%m-%d %H:%M"))

    while datetime.now() < enddate:
        scanlist = getscanjobs(api, enabledebug)
        if enabledebug:
            print("scan-blackout: Found %s scan jobs running or queued while polling" % str(len(scanlist)))
        for scan in scanlist:
            pausescan(scanref=scan, api=api, debug=enabledebug)
            if scan in masterlist:
                recordaction(action='Previously paused scan found as running/queued (%s).  Attempting to pause again' %
                                    scan, logfile=logfile, debug=enabledebug)
            else:
                recordaction(action='Paused Scan %s' % scan, logfile=logfile, debug=enabledebug)
                masterlist.append(scan)
        sleep(120)

    for scan in masterlist:
        resumescan(scanref=scan, api=api, debug=enabledebug)
        recordaction(action='Unpaused Scan %s' % scan, logfile=logfile, debug=enabledebug)

    recordaction(action='Script Terminated', logfile=logfile, debug=enabledebug)
    exit(0)
