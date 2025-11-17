pipeline {
  agent any
  environment {
    PROJECT_ID = 'PROJECT_ID'               // replace
    LOCATION = 'us-central1'                // GAR region
    REPOSITORY = 'REPOSITORY'               // GAR repo
    IMAGE_NAME = 'java-gradle'
    IMAGE_TAG = 'v1'                        // or use ${env.BUILD_NUMBER}
    IMAGE_URI = "${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"
    K8S_NAMESPACE = 'java-gradle-ns'
    CLUSTER_NAME = 'CLUSTER_NAME'           // replace
    CLUSTER_ZONE = 'CLUSTER_ZONE'           // replace
  }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      steps {
        dir('/var/lib/jenkins/firstjob/java-gradle'){
          sh './gradlew clean build'
        }
      }
    }

    stage('Docker Build') {
      steps {
        sh "docker build -t ${IMAGE_URI} ."
      }
    }

    stage('Authenticate & Push to GAR') {
      steps {
        withCredentials([file(credentialsId: 'GCP_SA_KEY', variable: 'GCP_KEYFILE')]) {
          sh """
            gcloud auth activate-service-account --key-file=${GCP_KEYFILE}
            gcloud config set project ${PROJECT_ID}
            gcloud auth configure-docker ${LOCATION}-docker.pkg.dev -q
            docker push ${IMAGE_URI}
          """
        }
      }
    }

    stage('Get GKE credentials') {
      steps {
        withCredentials([file(credentialsId: 'GCP_SA_KEY', variable: 'GCP_KEYFILE')]) {
          sh """
            gcloud auth activate-service-account --key-file=${GCP_KEYFILE}
            gcloud config set project ${PROJECT_ID}
            gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${CLUSTER_ZONE} --project ${PROJECT_ID}
          """
        }
      }
    }

    stage('Deploy to GKE') {
      steps {
        sh """
          chmod +x scripts/deploy.sh
          scripts/deploy.sh ${K8S_NAMESPACE} ${IMAGE_URI}
        """
      }
    }

    stage('Verify') {
      steps {
        sh """
          kubectl -n ${K8S_NAMESPACE} get pods -l app=java-gradle -o wide
          kubectl -n ${K8S_NAMESPACE} get ingress java-gradle-ingress -o wide
        """
      }
    }
  }

  post {
    failure {
      echo "Pipeline failed. Check logs."
    }
  }
}
