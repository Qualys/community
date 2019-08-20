/*
 * LICENSE
 * =======
 *
 * THIS SCRIPT IS PROVIDED TO YOU "AS IS." TO THE EXTENT PERMITTED BY LAW, 
 * QUALYS HEREBY DISCLAIMS ALL WARRANTIES AND LIABILITY FOR THE PROVISION 
 * OR USE OF THIS SCRIPT. IN NO EVENT SHALL THESE SCRIPTS BE DEEMED TO BE 
 * SUPPORTED PRODUCTS/SERVICES AS PROVIDED BY QUALYS.
 * 
 */

pipeline {
	agent {label 'master'}

	stages {

		stage ('Checkout') {
			steps {
				sh "mkdir -p checkout_dir"
				dir("checkout_dir") {
					git branch: "master", url: "https://github.com/pmgupte/webmon.git"
				}
			}
		}

		stage ('Build') {
			steps {
				dir("checkout_dir") {
					sh "docker build -t prabhasgupte/webmon:latest . > docker_output"
				}
			}
		}

		stage ('Extract Image Id') {
			steps {
				script {
					def IMAGE_ID = sh(script: "docker images | grep -E '^prabhasgupte/webmon.*latest' | head -1 | awk '{print \$3}'", returnStdout: true).trim()
					echo "Image Id extracted: ${IMAGE_ID}"
					env.DOCKER_IMAGE_ID = IMAGE_ID
				}
			}
		}

		stage ('Validate with Qualys') {
			steps {
				echo "Image Id to validate: ${env.DOCKER_IMAGE_ID}"
				script {
					sh(script: "./validate_image.sh ${QUALYS_API_SERVER} ${USERNAME} ${PASSWORD} ${env.DOCKER_IMAGE_ID}")
				}
			}
		}
	}
}
