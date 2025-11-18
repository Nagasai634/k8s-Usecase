pipeline {
  agent any
  
  parameters {
    choice(
      name: 'DEPLOYMENT_ACTION',
      choices: ['ROLLOUT', 'ROLLBACK'],
      description: 'Choose deployment action (only used for builds after the first)'
    )
    choice(
      name: 'VERSION',
      choices: ['v1.0', 'v2.0'],
      description: 'Choose version to deploy (only used for builds after the first)'
    )
  }

  environment {
    PROJECT_ID = 'planar-door-476510-m1'
    REGION = 'us-central1'
    GAR_REPO = 'java-app'
    IMAGE_NAME = "java-app"
    V1_TAG = "v1.0-${env.BUILD_NUMBER}"
    V2_TAG = "v2.0-${env.BUILD_NUMBER}"
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V1_TAG}"
    GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V2_TAG}"
    CLUSTER_NAME = "autopilot-demo"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
  }

  stages {
    stage('Clean Project') {
      steps {
        cleanWs()
        sh '''
          git clone https://github.com/Nagasai634/k8s-Usecase.git || true
          cd k8s-Usecase/java-gradle
          # Remove problematic files
          rm -f src/main/java/com/example/demo/VersionController.java 2>/dev/null || true
          chmod +x ./gradlew
        '''
      }
    }

    stage('Setup Tools') {
      steps {
        sh '''
          mkdir -p ${WORKSPACE}/bin
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x ./kubectl
          mv ./kubectl ${WORKSPACE}/bin/
          export PATH="${WORKSPACE}/bin:${PATH}"
        '''
      }
    }

    stage('Build Versions') {
      parallel {
        stage('Build v1.0') {
          steps {
            sh '''
              cd k8s-Usecase/java-gradle
              mkdir -p src/main/resources/static
              echo '<!DOCTYPE html><html><head><title>V1.0</title><style>body{background:#1e3a8a;color:white;text-align:center;padding:50px}.container{background:rgba(255,255,255,0.1);padding:30px;border-radius:10px;margin:auto;max-width:600px}h1{color:#60a5fa}.feature{background:#3b82f6;padding:10px;margin:10px;border-radius:5px}</style></head><body><div class="container"><h1>🚀 Version 1.0 - BLUE</h1><p>Simple Java Application</p></div></body></html>' > src/main/resources/static/index.html
              ./gradlew clean build --no-daemon
              docker build -t ${GAR_IMAGE_V1} .
              docker push ${GAR_IMAGE_V1}
            '''
          }
        }
        stage('Build v2.0') {
          steps {
            sh '''
              cd k8s-Usecase/java-gradle
              mkdir -p src/main/resources/static
              echo '<!DOCTYPE html><html><head><title>V2.0</title><style>body{background:#065f46;color:white;text-align:center;padding:50px}.container{background:rgba(255,255,255,0.1);padding:30px;border-radius:10px;margin:auto;max-width:600px}h1{color:#34d399}.feature{background:#10b981;padding:10px;margin:10px;border-radius:5px}</style></head><body><div class="container"><h1>🎯 Version 2.0 - GREEN</h1><p>Enhanced Java Application</p></div></body></html>' > src/main/resources/static/index.html
              ./gradlew clean build --no-daemon
              docker build -t ${GAR_IMAGE_V2} .
              docker push ${GAR_IMAGE_V2}
            '''
          }
        }
      }
    }

    stage('Setup GKE Access') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            export PATH="${WORKSPACE}/bin:${PATH}"
            export KUBECONFIG=${KUBECONFIG}  # Explicitly export for safety
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}
            
            # Get cluster details using jq for proper JSON parsing
            CLUSTER_ENDPOINT=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(endpoint)")
            CLUSTER_CA=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(masterAuth.clusterCaCertificate)" | base64 -d | base64 -w 0)
            
            # Get access token
            TOKEN=$(gcloud auth print-access-token)
            
            # Create kubeconfig with proper YAML (indentation removed for reliability)
            mkdir -p ${WORKSPACE}/.kube
            cat > ${KUBECONFIG} <<EOF
apiVersion: v1
kind: Config
current-context: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${CLUSTER_NAME}
  name: ${CLUSTER_NAME}
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: https://${CLUSTER_ENDPOINT}
  name: ${CLUSTER_NAME}
users:
- name: ${CLUSTER_NAME}
  user:
    token: ${TOKEN}
EOF
            
            # Validate kubeconfig
            if ! kubectl cluster-info --kubeconfig=${KUBECONFIG}; then
              echo "ERROR: Kubeconfig validation failed"
              exit 1
            fi
            echo "Kubeconfig created and validated"
          '''
        }
      }
    }

    stage('Clean Existing Deployment') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin
