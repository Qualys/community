# Sample scripts for Qualys Container Security

This directory will contain sample scripts, that can be referred to/used in CI/CD pipeline job.

## List of scripts
1. [CI/CD: A typical Jenkins pipeline job using Qualys plugin's global configuration](https://github.com/Qualys/community/blob/master/containerSecurity/sample_Jenkinsfile.groovy)
2. [CI/CD: Validate docker image without plugin](#validate-docker-image-without-plugin)

## Validate docker image without plugin

### Prerequisites

1. [jq](https://stedolan.github.io/jq/)
2. curl
3. docker
4. Qualys Container Security CI/CD Sensor setup correctly

### Script and Input file

1. [validate_image.sh](https://github.com/Qualys/community/blob/master/containerSecurity/validate_image.sh)
2. [jq_filter.txt](https://github.com/Qualys/community/blob/master/containerSecurity/jq_filter.txt)

### How to use this script

This script demonstrates how Qualys Container Security API can be used to validate docker image in CI/CD pipeline. 

Usually, in CI/CD pipeline, your workflow would be as follows:

1. Checkout and build the code
2. Build a docker image
3. Push the image to registry

It is recommended to use this script **just before step 3**. This will help you make sure, all the docker images pushed to registry are always free from serious vulnerabilities. 

#### Setting jq filter to validate image

First thing first. Decide a criteria to evaluate your docker image. It could be based on vulnerability severity. Then, prepare a jq filter for your criteria. You might want to refer [jq manual](https://stedolan.github.io/jq/manual/) for that. There is a sample filter provided in [this file](https://github.com/Qualys/community/blob/master/containerSecurity/jq_filter.txt).

#### Executing script

The script requires 4 arguments:

1. Qualys API Server URL
2. Qualys API Username
3. Qualys API Password
4. Image Id/Image Name

In CI/CD pipeline, execute this script with correct arguments **after** you build your docker image, and **before** you push it to registry. Make sure you aren't deleting the image before this script executes.

`./validate_image.sh ${QUALYS_API_SERVER} ${USERNAME} ${PASSWORD} ${DOCKER_IMAGE_ID}`

OR

`./validate_image.sh ${QUALYS_API_SERVER} ${USERNAME} ${PASSWORD} ${DOCKER_IMAGE_NAME}`

***It is recommended that you set those arguments as build/environment variables.*** A [sample Jenkinsfile](https://github.com/Qualys/community/blob/master/containerSecurity/Jenkinsfile_validate_image_without_plugin.groovy) is provided as well for your reference.

### What does this script do

The high-level workflow of this script is as follows. 

1. Tag the image with a predefined tag, so that Qualys CI/CD Sensor scans it. (Sensor will untag it after scanning. If this is the only tag present on the image, it is not untagged to avoid image deletion.)
2. Periodically, poll for processed vulnerability data. 
3. Once the processed vulnerability data is available, apply jq filter and evaluate the image. 
4. The jq filter will cause an error if the image does not fit in criteria (configured as jq filter). Otherwise, no error is raised.

## How to contribute

1. Fork this repository in your account. 
2. Add your changes/new contents. 
3. Please make sure you have tested your contributions.
4. Open a PR on this repository. Explain the change (and need of it) in the PR description. 
5. On successful review, your PR will be merged.
