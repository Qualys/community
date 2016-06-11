import os
import base64
import urllib
import urllib2
import urlparse
from datetime import datetime
from threading import current_thread
from threading import Thread, ThreadError, Lock
try:
	import xml.etree.cElementTree as ET
except ImportError:
	import xml.etree.ElementTree as ET

'''
Some global variables needed for this script
'''
server_root = 'https://qualysapi.qg2.apps.qualys.com'
output_dir = './output'
api_username = 'XXXXXX'
api_password = 'YYYYYY'

'''
Some settings for this script to function
'''
num_asset_threads = 10
num_detection_threads = 10

settings = {
	'download_assets': True,
	'download_detections': True
}

def build_headers():
	'''
	This method builds the HTTP headers required by client function.
	'''
	auth = "Basic " + base64.urlsafe_b64encode("%s:%s" % (api_username, api_password))
	headers = {
		'User-Agent': 'Python',
		'X-Requested-With': 'python script',
		'Authorization': auth
	}
	return headers
# end of build_headers

def build_request(api_route, params):
	'''
	This method builds the urllib2 request object with complete url, parameters and headers.
	'''
	data = urllib.urlencode(params)
	return urllib2.Request(api_route, data=data, headers=build_headers())
# end of build_request

def call_api(api_route, params):
	'''
	This method does the actual API call. Returns response or raises error.
	'''
	print "[%s] Calling %s with %s" % (current_thread().getName(), api_route, params)

	req = build_request(api_route, params)
	
	try:
		response = urllib2.urlopen(req, timeout=100)

		if response.getcode() != 200:
			print "[%s] Got unexpected response from API: %s" % (current_thread().getName(), response.read)
			raise Exception("API request failed: %s" % response.read)
		# end of if

		print "[%s] Got response from API..." % current_thread().getName()
		return response.read()
	except urllib2.URLError, ue:
		print "[%s] Error during request to %s: [%s] %s" % (current_thread().getName(), api_route, ue.errno, ue.reason)
		raise Exception("Error during request to %s: [%s] %s" % (api_route, ue.errno, ue.reason))
# end of call_api

def write_response(response, filename):
	'''
	This method writes given response into given file.
	If complete path to file does not exist, it will create it.
	'''
	if not os.path.exists(os.path.dirname(filename)):
		try:
			os.makedirs(os.path.dirname(filename))
		except OSError as exc:
			print "[%s] Error while creating output directory." % current_thread().getName()
			raise
	# end of if

	fp = open(filename, 'w')
	fp.write(response)
	fp.close()
# end of write_response

def get_asset_ids():
	'''
	This method will fetch all the host ids in single API call.
	'''
	action = 'list'
	details = 'None'
	api_route = '/api/2.0/fo/asset/host/'
	params = {'action': action, 'details': details, 'truncation_limit': 0}
	asset_ids = []
	print "[%s] Fetching asset ids..." % current_thread().getName()
	response = call_api(server_root + api_route, params)
	filename = output_dir + "/assets/asset_ids_%s_%s.xml" % (os.getpid(), current_thread().getName())
	write_response(response, filename)
	print "[%s] Wrote API response to %s" % (current_thread().getName(), filename)
	print "[%s] Parsing IDs..." % current_thread().getName()
	tree = ET.parse(filename)
	root = tree.getroot()
	# root = ET.fromstring(response)
	response_element = root.find('RESPONSE')
	if response_element is None:
		print "[%s] RESPONSE tag not found" % current_thread().getName()
	id_set = response_element.find('ID_SET')
	if id_set is None:
		print "[%s] ID_SET not found" % current_thread().getName()
	else:
		for id_element in id_set.findall('ID'):
			asset_ids.append(id_element.text)
		# end of for loop
	# end of if-else
	return asset_ids
# end of get_asset_ids

def get_params_from_url(url):
	return dict(urlparse.parse_qsl(urlparse.urlparse(url).query))
# end of get_params_from_url

def download_host_detections(ids):
	'''
	This method will invoke call_api method for asset/host/vm/detection/ API.
	'''
	action = 'list'
	show_tags = 1
	show_igs = 1
	truncation_limit = 500
	echo_request = 1
	output_format = 'XML' # 'CSV_NO_METADATA'
	suppress_duplicated_data_from_csv='0'
	api_route = '/api/2.0/fo/asset/host/vm/detection/'

	params = {
		'action': action,
		'echo_request': echo_request,
		'show_tags': show_tags,
		'show_igs': show_igs,
		'truncation_limit': truncation_limit,
		'output_format': output_format,
		'ids': ids,
		# 'suppress_duplicated_data_from_csv': suppress_duplicated_data_from_csv
	}

	batch = 1

	print "[%s] Downloading VM detections for ids %s" % (current_thread().getName(), ids)
	
	keep_running = True

	file_extension = 'xml'
	if output_format != 'XML':
		file_extension = 'csv'
		params['truncation_limit'] = 0 # I found it difficult to paginate when output format is CSV. So setting this to 0.

	while(keep_running):
		response = call_api(server_root + api_route, params)

		filename = output_dir + "/vm_detections/vm_detections_range_%s_proc%s_%s_batch%d.%s" % (ids, os.getpid(), current_thread().getName(), batch, file_extension)
		write_response(response, filename)
		print "[%s] Wrote API response to %s" % (current_thread().getName(), filename)

		if output_format == 'XML':
			print "[%s] Parsing response XML..." % current_thread().getName()
			tree = ET.parse(filename)
			root = tree.getroot()
			response_element = root.find('RESPONSE')

			if response_element is None:
				print "[%s] RESPONSE tag not found in %s. Please check the file." % (current_thread().getName(), filename)
				keep_running = False
			
			# HOST_LIST' tag will have list of hosts and inside that, DETECTION_LIST will have detections on that host 
			warning_element = response_element.find('WARNING')
			if warning_element is None:
				print "[%s] End of pagination for ids %s" % (current_thread().getName(), ids)
				keep_running = False
			else:
				next_page_url = warning_element.find('URL').text
				params = get_params_from_url(next_page_url)
				batch += 1
			# end of if-else
		# end of if
	# end of while
# end of download_host_detections

def download_assets(ids):
	'''
	This method will invoke call_api method for asset/host API.
	'''
	action = 'list'
	details = 'All/AGs'
	truncation_limit = 5000
	echo_request = 1
	api_route = '/api/2.0/fo/asset/host/'
	params = {'action': action, 'echo_request': echo_request, 'details': details, 'ids': ids, 'truncation_limit': truncation_limit}

	batch = 1

	print "[%s] Downloading assets..." % current_thread().getName()

	keep_running = True

	while(keep_running):
		response = call_api(server_root + api_route, params)

		filename = output_dir + "/assets/assets_range_%s_proc%s_%s_batch%d.xml" % (ids, os.getpid(), current_thread().getName(), batch)
		write_response(response, filename)
		print "[%s] Wrote API response to %s" % (current_thread().getName(), filename)
		
		print "[%s] Parsing response XML..." % current_thread().getName()
		tree = ET.parse(filename)
		root = tree.getroot()
		response_element = root.find('RESPONSE')
		
		if response_element is None:
			print "[%s] RESPONSE tag not found in %s. Please check the file." % (current_thread().getName(), filename)
			keep_running = False
		
		host_list = response_element.find('HOST_LIST')
		warning_element = response_element.find('WARNING')
		
		if warning_element is None:
			print "[%s] End of pagination for ids %s" % (current_thread().getName(), ids)
			keep_running = False
		else:
			next_page_url = warning_element.find('URL').text
			params = get_params_from_url(next_page_url)
			batch += 1
		# end of if-else
	# end of while
# end of download_assets

def chunk_id_set(id_set, num_asset_threads):
	for i in xrange(0, len(id_set), num_asset_threads):
		yield id_set[i:i + num_asset_threads]
	# end of for loop
# end of chunk_id_set

def main():
	if settings['download_assets'] == False and settings['download_detections'] == False:
		print "Please set at least one of the settings below to True."
		print settings
		exit()
	# end of if

	id_chunks = []

	id_set = get_asset_ids()
	num_ids = len(id_set)
	print "[%s] Got %d asset ids..." % (current_thread().getName(), num_ids)

	num_chunks = num_ids / num_asset_threads
	
	if num_ids % num_asset_threads != 0:
		num_chunks += 1
	chunks = chunk_id_set(id_set, num_chunks)

	workers = []

	for id_chunk in chunks:
		id_range = "%s-%s" % (id_chunk[0], id_chunk[-1])

		if settings['download_assets'] == True:
			print "[%s] Calling download_assets for id range %s" % (current_thread().getName(), id_range)
			asset_thread = Thread(target=download_assets, args=(id_range,))
			asset_thread.setDaemon(True)
			asset_thread.start()
			workers.append(asset_thread)

		if settings['download_detections'] == True:
			print "[%s] Calling download_host_detections for id range %s" % (current_thread().getName(), id_range)
			detection_thread = Thread(target=download_host_detections, args=(id_range,))
			detection_thread.setDaemon(True)
			detection_thread.start()
			workers.append(detection_thread)
	# end of for loop

	for worker in workers:
		worker.join()
# end of main

if __name__ == "__main__":
	start_time = datetime.now()
	main()
	end_time = datetime.now()
	total_run_time = end_time - start_time
	print total_run_time
