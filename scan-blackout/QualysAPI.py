import requests
import xml.etree.ElementTree as ET
from time import sleep

class QualysAPI:
    """Class to simplify the making and handling of API calls to the Qualys platform

    Class Members
    =============

    server          : String  : The FQDN of the API server (with https:// prefix)
    user            : String  : The username of an API user in the subscription
    password        : String  : The password of the API user
    proxy           : String  : The FQDN of the proxy server to be used for connections (with https:// prefix)
    debug           : Boolean : If True, will output debug information to the console during member function execution
    enableProxy     : Boolean : If True will force connections via the proxy defined in the 'proxy' class member
    callCount       : Integer : The number of API calls made during the life of the API object

    Class Methods
    =============

    __init__(svr, usr, passwd, proxy, enableProxy, debug)

        Called when an object of type QualysAPI is created

            svr         : String  : The FQDN of the API server (with https:// prefix).
                                    Default value = ""

            usr         : String  : The username of an API user in the subscription.
                                    Default value = ""

            passwd      : String  : The password of the API user.
                                   Default value = ""

            proxy       : String  : The FQDN of the proxy server to be used for connections (with https:// prefix)
                                    Default value = ""

            enableProxy : Boolean : If True, will force connections made via the proxy defined in the 'proxy' class
                                    member
                                    Default value = False

            debug       : Boolean : If True, will output debug information to the console during member function
                                    execution
                                    Default value = False

    makeCall(url, payload, headers, retryCount)

        Make a Qualys API call and return the response in XML format as an ElementTree.Element object

            url         : String  : The full URL of the API request, including any URL encoded parameters
                                    NO DEFAULT VALUE, REQUIRED PARAMETER

            payload     : String  : The payload (body) of the API request
                                    Default value = ""

            headers     : Dict    : HTTP Request headers to be sent in the API call
                                    Default value = None

            retryCount  : Integer : The number of times this call has been attempted.  Used in rate and concurrency
                                    limit handling, not intended for use by users
                                    Default value = 0

        Example :
            api = QualysAPI(svr='https://qualysapi.qualys.com',
                            usr='username',
                            passwd='password',
                            proxy='https://proxy.internal',
                            enableProxy = True,
                            debug=False)

            fullurl = '%s/full/path/to/api/call' % api.url

            api.makeCall(url=fullURL, payload='', headers={'X-Requested-With': 'python3'})

            """

    server: str
    user: str
    password: str
    proxy: str
    debug: bool
    enableProxy: bool
    callCount: int

    headers = {}

    sess: requests.Session

    def __init__(self, svr="", usr="", passwd="", proxy="", enableProxy=False, debug=False):
        # Set all member variables from the values passed in when object is created
        self.server = svr
        self.user = usr
        self.password = passwd
        self.proxy = proxy
        self.enableProxy = enableProxy
        self.debug = debug
        self.callCount = 0

        # Create a session object with the requests library
        self.sess = requests.session()
        # Set the authentication credentials for the session to be the (username, password) tuple
        self.sess.auth = (self.user, self.password)
        # Add a default X-Requested-With header (most API calls require it, it doesn't hurt to have it in all calls)
        self.headers = {'X-Requested-With': 'python3/requests'}

    def makeCall(self, url, payload="", headers=None, retryCount=0):
        # Get the headers from our own session object
        rheaders = self.sess.headers
        # If there are headers (meaning the __init__ method has been called and the api object was correctly created)
        if headers is not None:
            # copy each of the headers passed in via the 'headers' variable to the session headers so they are included
            #   in the request
            for h in headers.keys():
                rheaders[h] = headers[h]

        # Create a Request object using the requests library
        r = requests.Request('POST', url, data=payload, headers=rheaders)
        # Prepare the request for sending
        prepped_req = self.sess.prepare_request(r)
        # If the proxy is enabled, send via the proxy
        if self.enableProxy:
            resp = self.sess.send(prepped_req, proxies={'https': self.proxy})
        # Otherwise send direct
        else:
            resp = self.sess.send(prepped_req)

        if self.debug:
            print("QualysAPI.makeCall: Headers...")
            print("%s" % str(resp.headers))

        # Handle concurrency limit failures
        if 'X-Concurrency-Limit-Limit' in resp.headers.keys() and 'X-Concurrency-Limit-Running' in resp.headers.keys():
            climit = int(resp.headers['X-Concurrency-Limit-Limit'])
            crun = int(resp.headers['X-Concurrency-Limit-Running'])
            # If crun > climit then we have hit the concurrency limit.  We then wait for a number of seconds depending
            #   on how many retry attempts there have been
            if crun > climit:
                print("QualysAPI.makeCall: Concurrency limit hit.  %s/%s running calls" % (crun,climit))
                retryCount = retryCount + 1
                if retryCount > 15:
                    print("QualysAPI.makeCall: Retry count > 15, waiting 60 seconds")
                    waittime = 60
                elif retryCount > 5:
                    print("QualysAPI.makeCall: Retry count > 5, waiting 30 seconds")
                    waittime = 30
                else:
                    print("QualysAPI.makeCall: Waiting 15 seconds")
                    waittime = 15
                # Sleep here
                sleep(waittime)
                print("QualysAPI.makeCall: Retrying (retryCount = %s)" % str(retryCount))

                # Make a self-referential call to this same class method, passing in the retry count so the next
                #   iteration knows how many attempts have been made so far
                resp = self.makeCall(url=url, payload=payload,headers=headers, retryCount=retryCount)

        # Handle rate limit failures
        if 'X-RateLimit-ToWait-Sec' in resp.headers.keys():
            if resp.headers['X-RateLimit-ToWait-Sec'] > 0:
                # If this response header has a value > 0, we know we have to wait some time so first we increment
                #   the retryCount
                retryCount = retryCount + 1

                # Get the number of seconds to wait from the response header.  Add to this a number of seconds depending
                #   on how many times we have already tried this call
                waittime = int(resp.headers['X-RateLimit-ToWait-Sec'])
                print("QualysAPI.makeCall: Rate limit reached, suggested wait time: %s seconds" % waittime)
                if retryCount > 15:
                    print("QualysAPI.makeCall: Retry Count > 15, adding 60 seconds to wait time")
                    waittime = waittime + 60
                elif retryCount > 5:
                    print("QualysAPI.makeCall: Retry Count > 5, adding 30 seconds to wait time")
                    waittime = waittime + 30

                # Sleep here
                sleep(waittime)
                print("QualysAPI.makeCall: Retrying (retryCount = %s)" % str(retryCount))

                # Make a self-referential call to this same class method, passing in the retry count so the next
                #   iteration knows how many attempts have been made so far
                resp = self.makeCall(url=url, payload=payload, headers=headers, retryCount=retryCount)

        # Increment the API call count (failed calls are not included in the count)
        self.callCount = self.callCount + 1

        # Return the response as an ElementTree XML object
        return ET.fromstring(resp.text)