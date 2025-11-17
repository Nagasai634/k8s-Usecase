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
    CLUSTER_NAME = "autopilot-demo"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
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

    stage('Install Required Tools (No Sudo)') {
      steps {
        sh '''
          echo "=== Installing Required Tools Without Sudo ==="
          
          # Install kubectl to local workspace (no sudo required)
          mkdir -p ${WORKSPACE}/bin
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x ./kubectl
          mv ./kubectl ${WORKSPACE}/bin/
          export PATH="${WORKSPACE}/bin:${PATH}"
          
          # Verify kubectl installation
          ${WORKSPACE}/bin/kubectl version --client
          
          # Check if docker is available
          which docker || echo "Docker might need setup"
          docker --version || echo "Docker not available"
        '''
      }
    }

    stage('Fix Permissions') {
      steps {
        sh '''
          echo "=== Fixing Permissions ==="
          cd k8s-Usecase/java-gradle
          chmod +x ./gradlew
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
            if ! gcloud artifacts repositories describe ${GAR_REPO} --location=${REGION}; then
              gcloud artifacts repositories create ${GAR_REPO} \
                --repository-format=docker \
                --location=${REGION} \
                --description="Docker repository for Java application"
            fi
            
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
            # Set PATH to include our local kubectl
            export PATH="${WORKSPACE}/bin:${PATH}"
            
            # Get kubeconfig for the cluster
            gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}
            
            # Verify cluster access
            ${WORKSPACE}/bin/kubectl cluster-info
            ${WORKSPACE}/bin/kubectl get nodes
          '''
        }
      }
    }

    stage('Deploy to GKE') {
      steps {
        sh '''
          echo "=== Deploying to GKE ==="
          export PATH="${WORKSPACE}/bin:${PATH}"
          
          # Create namespace if not exists
          ${WORKSPACE}/bin/kubectl create namespace java-app --dry-run=client -o yaml | ${WORKSPACE}/bin/kubectl apply -f -
          
          # Apply all Kubernetes manifests
          ${WORKSPACE}/bin/kubectl apply -f k8s-Usecase/k8s/ -n java-app
          
          # Update deployment with new image
          ${WORKSPACE}/bin/kubectl set image deployment/java-gradle-app java-app=${GAR_IMAGE} -n java-app --record
          
          # Wait for rollout
          ${WORKSPACE}/bin/kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s
          
          echo "Deployment completed successfully"
        '''
      }
    }

    stage('Verify Deployment') {
      steps {
        sh '''
          echo "=== Deployment Verification ==="
          export PATH="${WORKSPACE}/bin:${PATH}"
          ${WORKSPACE}/bin/kubectl get deployments,svc,pods,hpa,ingress -n java-app
          
          # Get the external IP
          echo "=== Load Balancer IP ==="
          ${WORKSPACE}/bin/kubectl get ingress -n java-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "IP not yet assigned - may take a few minutes"
        '''
      }
    }
  }

  post {
    always {
      sh '''
        echo "=== Build Completed ==="
        echo "Workspace: ${WORKSPACE}"
        ls -la ${WORKSPACE}/bin/ 2>/dev/null || echo "No bin directory"
      '''
    }
    failure {
      sh '''
        echo "=== Build Failed ==="
        export PATH="${WORKSPACE}/bin:${PATH}"
        # Attempt rollback only if deployment exists
        if ${WORKSPACE}/bin/kubectl get deployment java-gradle-app -n java-app 2>/dev/null; then
          echo "Attempting rollback..."
          ${WORKSPACE}/bin/kubectl rollout undo deployment/java-gradle-app -n java-app --timeout=300s
        else
          echo "No deployment to rollback"
        fi
      '''
    }
  }
}