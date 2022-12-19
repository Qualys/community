#!/bin/bash

################################################################################
# LICENSE
# =======
#
# THIS SCRIPT IS PROVIDED TO YOU "AS IS." TO THE EXTENT PERMITTED BY LAW, 
# QUALYS HEREBY DISCLAIMS ALL WARRANTIES AND LIABILITY FOR THE PROVISION OR 
# USE OF THIS SCRIPT. IN NO EVENT SHALL THESE SCRIPTS BE DEEMED TO BE SUPPORTED 
# PRODUCTS/SERVICES AS PROVIDED BY QUALYS.
#
################################################################################

cat << EOLICENSE
################################################################################
# LICENSE
# =======
#
# THIS SCRIPT IS PROVIDED TO YOU "AS IS." TO THE EXTENT PERMITTED BY LAW,
# QUALYS HEREBY DISCLAIMS ALL WARRANTIES AND LIABILITY FOR THE PROVISION OR
# USE OF THIS SCRIPT. IN NO EVENT SHALL THESE SCRIPTS BE DEEMED TO BE SUPPORTED
# PRODUCTS/SERVICES AS PROVIDED BY QUALYS.
################################################################################

EOLICENSE

set -e

if [ $# -lt 4 ]; then
	echo "All required arguments not provided."
	echo "Syntax:"
	echo "validate_image.sh <Qualys API Server> <Username> <Password> <Image Id|Name>"
	exit 1
fi


QUALYS_API_SERVER=$1
USERNAME=$2
PASSWORD=$3
IMAGE=$4
TIMEOUT=$5
: ${TIMEOUT:=600}

check_command_exists () {
	hash $1 2>/dev/null || { echo >&2 "This script requires $1 but it's not installed. Aborting."; exit 1; }
}

get_token() {
        echo "Generate Gateway Token for API Version:v1.3"  
	TOKEN=$($CURL -k -X POST ''${QUALYS_API_SERVER}'/auth' -d 'username='${USERNAME}'&password='${PASSWORD}'&token=true&permissions=true' -s)
	echo $TOKEN
}

get_result () {
	echo "Getting result for ${IMAGE_ID}"
	CURL_COMMAND=$($CURL -k -s -X GET ${QUALYS_API_SERVER}/csapi/v1.3/images/${IMAGE_ID} -H 'accept: application/json' -H 'Authorization: Bearer '${TOKEN} -o ${IMAGE_ID}.json -w "%{http_code}")
	HTTP_CODE=$CURL_COMMAND
	echo "HTTP Code: ${HTTP_CODE}"
	if [ "$HTTP_CODE" == "200" ]; then
		check_vulns
	fi
}

check_vulns () {
	  echo "Checking if vulns reported on ${IMAGE_ID}"
	  #VULNS_ABSENT=$($JQ '.vulnerabilities==null' ${IMAGE_ID}.json)
	  VULNS_ABSENT=$($JQ '.lastScanned==null' ${IMAGE_ID}.json)
	  if [[ "$VULNS_ABSENT" == "true" ]]; then
		VULNS_AVAILABLE=false
	   else
		VULNS_AVAILABLE=true
	 fi
	 echo "Vulns Available: ${VULNS_AVAILABLE}" 
}

check_image_input_type () {
	IMAGE_REGEX='^([A-Fa-f0-9]{12}|[A-Fa-f0-9]{64})$'
	IMAGE_INPUT_TYPE=''
	if [[ $1 =~ $IMAGE_REGEX ]]; then
		IMAGE_INPUT_TYPE='ID'
	else
		IMAGE_INPUT_TYPE='NAME'
	fi
	echo ${IMAGE_INPUT_TYPE}
}

get_image_id_from_name () {
	docker_command="$DOCKER inspect $1"
	IMAGE_ID=$($docker_command | grep Id | grep -Po '"Id": *\K"[^"]*"' | sed 's/"//g' | cut -d: -f2)

	if [[ "${IMAGE_ID}" == "IMAGE" ]]; then
		echo "Error! No image found by name $1"
		exit 2
	fi
}

###############################################################################
# Main execution starts here
###############################################################################

check_command_exists curl
check_command_exists jq
check_command_exists docker

CURL=$(which curl)
JQ=$(which jq)
DOCKER=$(which docker)

get_token

check_image_input_type ${IMAGE}

if [ "${IMAGE_INPUT_TYPE}" == "NAME" ]; then
	echo "Input (${IMAGE}) is image name. Script will now try to get the image id."
	get_image_id_from_name ${IMAGE}
	echo "Image sha belonging to ${IMAGE} is: ${IMAGE_ID}"
else
	IMAGE_ID=${IMAGE}
fi

echo "Image sha belonging to ${IMAGE} is: ${IMAGE_ID}"

echo "Temporarily tagging image ${IMAGE} with qualys_scan_target:${IMAGE_ID}"
echo "Qualys Sensor will untag it after scanning. In case this is the only tag present, Sensor will not remove it."
`docker tag ${IMAGE_ID} qualys_scan_target:${IMAGE_ID}`

echo -e "\n=-=-Configured TIME_OUT in second :$TIMEOUT-=-=-\n"
get_result
wait_period=0
while [ "${HTTP_CODE}" -ne "200" -o "${VULNS_AVAILABLE}" != true ] && [[ $wait_period -lt $TIMEOUT ]]
do
	echo "Retrying after 10 seconds..."
	sleep 10s
	wait_period=$(($wait_period+10))
	get_result
done
if [ $wait_period = $TIMEOUT ]
then
	echo "Vulnerabilities processing took  more time than configured time:$TIMEOUT second"
	echo "Please check the sensor logs OR QUALYS cloud platform status(https://status.qualys.com/)"
	exit 1
fi
EVAL_RESULT=$(jq -f jq_filter.txt ${IMAGE_ID}.json)
echo ${EVAL_RESULT}

