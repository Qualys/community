#!/bin/bash

################################################################################
# License
# =======
#
# THIS SCRIPT IS PROVIDED TO YOU "AS IS." TO THE EXTENT PERMITTED BY LAW, 
# QUALYS HEREBY DISCLAIMS ALL WARRANTIES AND LIABILITY FOR THE PROVISION OR 
# USE OF THIS SCRIPT. IN NO EVENT SHALL THESE SCRIPTS BE DEEMED TO BE SUPPORTED 
# PRODUCTS/SERVICES AS PROVIDED BY QUALYS.
#
################################################################################

set -e

if [[ $# -lt 4 ]]; then
	echo "All required arguments not provided."
	echo "Syntax:"
	echo "validate_image.sh <Qualys API Server> <Username> <Password> <ImageId>"
	exit 1
fi

CURL=$(which curl)
JQ=$(which jq)
QUALYS_API_SERVER=$1
USERNAME=$2
PASSWORD=$3
IMAGE_ID=$4

echo "IMAGE ID is ${IMAGE_ID}"

GET_IMAGE_VULNS_URL="${QUALYS_API_SERVER}/csapi/v1.1/images/${IMAGE_ID}"

get_result () {
	echo "Getting result for ${IMAGE_ID}"
	CURL_COMMAND="$CURL -s -X GET ${GET_IMAGE_VULNS_URL} -u ${USERNAME}:${PASSWORD} -L -w\\n%{http_code} -o ${IMAGE_ID}.json"
	HTTP_CODE=$($CURL_COMMAND | tail -n 1)
	echo "HTTP Code: ${HTTP_CODE}"
	if [[ "$HTTP_CODE" == "200" ]]; then
		check_vulns
	fi
}

check_vulns () {
	echo "Checking if vulns reported on ${IMAGE_ID}"
	VULNS_ABSENT=$($JQ '.vulnerabilities==null' ${IMAGE_ID}.json)
	if [[ "$VULNS_ABSENT" == "true" ]]; then
		VULNS_AVAILABLE=false
	else
		VULNS_AVAILABLE=true
	fi
	echo "Vulns Available: ${VULNS_AVAILABLE}"
}

echo "Temporarily tagging image ${IMAGE_ID} with qualys_scan_target:${IMAGE_ID}"
echo "Qualys Sensor will untag it after scanning. In case this is the only tag present, Sensor will not remove it."
`docker tag ${IMAGE_ID} qualys_scan_target:${IMAGE_ID}`

get_result

while [ "$HTTP_CODE" -ne "200" -o "$VULNS_AVAILABLE" != true ]
do
	echo "Retrying after 10 seconds..."
	sleep 10
	get_result
done

EVAL_RESULT=$(jq -f jq_filter.txt ${IMAGE_ID}.json)
echo $EVAL_RESULT

