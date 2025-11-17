pipeline {
  agent any

  environment {
    PROJECT_ID = 'planar-door-476510-m1'
    REGION = 'us-central1'
    GAR_REPO = 'java-app'
    IMAGE_NAME = "java-app"
    IMAGE_TAG = "${env.BUILD_NUMBER ?: 'manual'}"
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    GAR_IMAGE = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
    CLUSTER_NAME = "my-autopilot-cluster"
  }

  stages {
    stage('Checkout and Setup') {
      steps {
        cleanWs()
        sh '''
          git clone https://github.com/Nagasai634/k8s-Usecase.git
          cd k8s-Usecase
          ls -la
          pwd
        '''
      }
    }

    stage('Fix Permissions') {
      steps {
        sh '''
          echo "=== Fixing Permissions ==="
          cd k8s-Usecase/java-gradle
          pwd
          ls -la
          chmod 755 ./gradlew
          ls -la gradlew
          chown -R jenkins:jenkins /var/lib/jenkins/workspace/first-job/k8s-Usecase/ || true
        '''
      }
    }

    stage('Setup gcloud') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            # Authenticate gcloud
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}
            
            # Enable required APIs
            gcloud services enable container.googleapis.com artifactregistry.googleapis.com cloudresourcemanager.googleapis.com --quiet || true
            
            # Configure docker auth
            gcloud auth configure-docker ${GAR_HOST} --quiet
          '''
        }
      }
    }

    stage('Build (Gradle)') {
      steps {
        sh '''
          cd k8s-Usecase/java-gradle
          echo "Current directory: $(pwd)"
          echo "Java version:"
          java -version
          echo "Gradle wrapper permissions:"
          ls -la gradlew
          ./gradlew clean build --no-daemon --stacktrace
        '''
      }
    }

    stage('Build & Push Docker image') {
      steps {
        sh '''
          cd k8s-Usecase/java-gradle
          echo "Building Docker image: ${GAR_IMAGE}"
          docker build -t ${GAR_IMAGE} .
          docker push ${GAR_IMAGE}
        '''
      }
    }

    stage('Deploy to GKE') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            # Get kubeconfig
            gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}

            # Create namespace if not exists
            kubectl create namespace java-app --dry-run=client -o yaml | kubectl apply -f -

            # Apply all manifests
            kubectl apply -f k8s-Usecase/k8s/ -n java-app

            # Update deployment with new image
            kubectl set image deployment/java-gradle-app java-app=${GAR_IMAGE} -n java-app --record

            # Wait for rollout
            kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s
          '''
        }
      }
    }

    stage('Verify Deployment') {
      steps {
        sh '''
          echo "=== Deployment Verification ==="
          kubectl get deployments -n java-app
          kubectl get pods -n java-app -l app=java-gradle-app
          kubectl get services -n java-app
          kubectl get ingress -n java-app
          kubectl get hpa -n java-app
          
          echo "=== Cloud Armor Policy ==="
          kubectl get securitypolicy -n java-app
        '''
      }
    }
  }

  post {
    always {
      sh '''
        echo "=== Cleaning up ==="
        docker system prune -f || true
      '''
    }
    failure {
      sh '''
        echo "=== Build Failed - Attempting Rollback ==="
        kubectl rollout undo deployment/java-gradle-app -n java-app --timeout=300s || true
      '''
    }
  }
}