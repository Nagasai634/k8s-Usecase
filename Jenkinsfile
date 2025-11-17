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
        '''
      }
    }

    stage('Install Required Tools') {
      steps {
        sh '''
          echo "=== Installing Required Tools ==="
          # Install kubectl
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
          kubectl version --client
          
          # Install docker if not present
          which docker || (sudo apt-get update && sudo apt-get install -y docker.io)
          sudo usermod -aG docker jenkins || true
        '''
      }
    }

    stage('Fix Permissions') {
      steps {
        sh '''
          echo "=== Fixing Permissions ==="
          cd k8s-Usecase/java-gradle
          chmod 755 ./gradlew
          ls -la gradlew
        '''
      }
    }

    stage('Setup GCP and Create Artifact Registry') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            # Authenticate gcloud
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}
            
            # Enable required APIs
            gcloud services enable container.googleapis.com artifactregistry.googleapis.com cloudresourcemanager.googleapis.com --quiet
            
            # Create Artifact Registry repository if it doesn't exist
            gcloud artifacts repositories describe ${GAR_REPO} --location=${REGION} || \
            gcloud artifacts repositories create ${GAR_REPO} \
              --repository-format=docker \
              --location=${REGION} \
              --description="Docker repository for Java application"
            
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
          ./gradlew clean build --no-daemon --stacktrace
        '''
      }
    }

    stage('Build & Push Docker image') {
      steps {
        sh '''
          cd k8s-Usecase/java-gradle
          echo "Building Docker image: ${GAR_IMAGE}"
          
          # Build the image
          docker build -t ${GAR_IMAGE} .
          
          # Push to Artifact Registry
          docker push ${GAR_IMAGE}
          
          echo "Image successfully pushed to Artifact Registry"
        '''
      }
    }

    stage('Setup GKE Access') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            # Get kubeconfig for the cluster
            gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}
            
            # Verify cluster access
            kubectl cluster-info
            kubectl get nodes
          '''
        }
      }
    }

    stage('Deploy to GKE') {
      steps {
        sh '''
          echo "=== Deploying to GKE ==="
          
          # Create namespace if not exists
          kubectl create namespace java-app --dry-run=client -o yaml | kubectl apply -f -
          
          # Apply all Kubernetes manifests
          kubectl apply -f k8s-Usecase/k8s/ -n java-app
          
          # Update deployment with new image
          kubectl set image deployment/java-gradle-app java-app=${GAR_IMAGE} -n java-app --record
          
          # Wait for rollout
          kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s
          
          echo "Deployment completed successfully"
        '''
      }
    }

    stage('Verify Deployment') {
      steps {
        sh '''
          echo "=== Deployment Verification ==="
          kubectl get deployments,svc,pods,hpa,ingress -n java-app
          
          # Get the external IP
          echo "=== Load Balancer IP ==="
          kubectl get ingress -n java-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' || echo "IP not yet assigned"
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
        echo "=== Build Failed ==="
        # Don't attempt rollback if deployment didn't happen
        kubectl get deployment java-gradle-app -n java-app && \
        kubectl rollout undo deployment/java-gradle-app -n java-app --timeout=300s || \
        echo "No deployment to rollback"
      '''
    }
  }
}