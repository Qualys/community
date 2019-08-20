# Sample scripts for Qualys Container Security

This directory will contain sample scripts, that can be referred to/used in CI/CD pipeline job.

## List of scripts
1. [Jenkins: A typical pipeline job using Qualys plugin's global configuration](https://github.com/Qualys/community/blob/master/containerSecurity/sample_Jenkinsfile.groovy)
2. [CI/CD: Validate docker image without plugin](https://github.com/Qualys/community/blob/master/containerSecurity/validate_image.sh)

## Validate docker image without plugin

### Prerequisites

1. [jq](https://stedolan.github.io/jq/)
2. Qualys Container Security Sensor setup correctly

### How to use this script

This script demonstrates how Qualys Container Security API can be used to validate docker image in CI/CD pipeline. 

#### Setting jq filter to validate image

First thing first. Decide a criteria to evaluate your docker image. It could be based on vulnerability severity. Then, prepare a jq filter for your criteria. You might want to refer [jq manual](https://stedolan.github.io/jq/manual/) for that. There is a sample filter provided in [this file](https://github.com/Qualys/community/blob/master/containerSecurity/jq_filter.txt).

#### Executing script

The script requires 4 arguments:

1. Qualys API Server URL
2. Qualys API Username
3. Qualys API Password
4. Image Id

In CI/CD pipeline, *after* you build your docker image, execute this script with correct arguments.

`./validate_image.sh ${QUALYS_API_SERVER} ${USERNAME} ${PASSWORD} ${DOCKER_IMAGE_ID}`

It is recommended that you set those arguments as build/environment variables. A [sample Jenkinsfile](https://github.com/Qualys/community/blob/master/containerSecurity/Jenkinsfile_validate_image_without_plugin.groovy) is provided as well for your reference.
