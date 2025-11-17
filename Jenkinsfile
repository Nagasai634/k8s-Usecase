pipeline {
  agent any

  environment {
    // Replace these with values for your project
    PROJECT_ID      = ""
    REGION          = "us-central1"                     // Artifact Registry region and cluster region
    REPO            = "my-repo"                         // Artifact Registry repo name
    IMAGE_NAME      = "my-java-app"                     // image name
    TAG             = "${env.BUILD_NUMBER ?: 'v1'}"     // use build number or custom tag
    K8S_DIR         = "k8s"                             // directory with manifests
    IMAGE_PLACEHOLDER = "IMAGE_PLACEHOLDER"             // placeholder text in k8s manifests
    DEPLOYMENT_NAME = "your-deployment-name"           // k8s deployment to wait for
    FULL_IMAGE      = "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:${TAG}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build (Maven)') {
      steps {
        // run maven build inside maven image
        script {
          docker.image('maven:3.8.8-openjdk-17').inside {
            sh 'mvn -B clean package -DskipTests'   // adjust as needed
          }
        }
      }
    }

    stage('Build & Push Container Image') {
      steps {
        // Use google/cloud-sdk for gcloud + docker auth
        withCredentials([file(credentialsId: 'GCP_SA_KEY', variable: 'GCP_KEY_FILE')]) {
          script {
            docker.image('google/cloud-sdk:slim').inside('--entrypoint=""') {
              sh """
                set -e
                # authenticate to GCP
                gcloud auth activate-service-account --key-file=${GCP_KEY_FILE} --project=${PROJECT_ID}
                gcloud config set project ${PROJECT_ID}
                gcloud --quiet components update

                # ensure Artifact Registry repo exists (idempotent; ignore error if already exists)
                gcloud artifacts repositories create ${REPO} --repository-format=docker --location=${REGION} || echo "repo may already exist"

                # configure docker to authenticate to Artifact Registry
                gcloud auth configure-docker ${REGION}-docker.pkg.dev -q

                # build image (docker must be available on the agent for this to work)
                # If your Jenkins agent does not have docker daemon, consider using Cloud Build instead.
                docker build -t ${FULL_IMAGE} .

                # push
                docker push ${FULL_IMAGE}
              """
            }
          }
        }
      }
    }

    stage('Update Manifests') {
      steps {
        // Replace IMAGE_PLACEHOLDER in all YAMLs in K8S_DIR. If you prefer kubectl set image, see below.
        sh """
          if [ -d "${K8S_DIR}" ]; then
            sed -i "s|${IMAGE_PLACEHOLDER}|${FULL_IMAGE}|g" ${K8S_DIR}/*.yaml || true
            git --no-pager diff -- ${K8S_DIR} || true
          else
            echo "K8S dir ${K8S_DIR} not found; skipping manifest update"
          fi
        """
      }
    }

    stage('Deploy to GKE') {
      steps {
        withCredentials([file(credentialsId: 'GCP_SA_KEY', variable: 'GCP_KEY_FILE')]) {
          script {
            docker.image('google/cloud-sdk:slim').inside('--entrypoint=""') {
              sh """
                set -e
                gcloud auth activate-service-account --key-file=${GCP_KEY_FILE} --project=${PROJECT_ID}
                gcloud config set project ${PROJECT_ID}

                # get cluster credentials (Autopilot cluster)
                gcloud container clusters get-credentials YOUR_CLUSTER_NAME --region YOUR_CLUSTER_REGION --project=${PROJECT_ID}

                # apply manifests (or patch via kubectl set image)
                kubectl apply -f ${K8S_DIR}/

                # wait for rollout
                kubectl rollout status deployment/${DEPLOYMENT_NAME} --timeout=3m || kubectl rollout status deployment/${DEPLOYMENT_NAME} --timeout=5m
              """
            }
          }
        }
      }
    }

    stage('Smoke Test') {
      steps {
        // quick check - list pods & services
        sh 'kubectl get pods,svc -o wide'
      }
    }
  }

  post {
    failure {
      echo "Build or deploy failed. Check console output."
    }
    success {
      echo "Deployment completed: ${FULL_IMAGE}"
    }
  }
}
