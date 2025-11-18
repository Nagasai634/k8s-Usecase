pipeline {
  agent any

  // PARAMETERS: action, version, and ingress whitelist CIDR
  parameters {
    choice(name: 'DEPLOYMENT_ACTION',
           choices: ['ROLLOUT', 'ROLLBACK'],
           description: 'Choose deployment action (ignored on first run; first run auto-deploys v1.0)')
    choice(name: 'VERSION',
           choices: ['v1.0', 'v2.0'],
           description: 'Choose version to deploy (ignored on first run)')
    string(name: 'ALLOWED_IP_CIDR',
           defaultValue: '203.0.113.5/32',
           description: 'CIDR to whitelist on the ingress (change per-run)')
  }

  environment {
    // EDIT for your environment: set your GCP project / cluster / region here
    PROJECT_ID = 'planar-door-476510-m1'
    REGION = 'us-central1'
    CLUSTER_NAME = 'autopilot-demo'
    GAR_REPO = 'java-app'
    IMAGE_NAME = 'java-app'

    // Derived variables
    WORKSPACE_BIN = "${env.WORKSPACE}/bin"
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    V1_TAG = "v1.0-${env.BUILD_NUMBER}"
    V2_TAG = "v2.0-${env.BUILD_NUMBER}"
    GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V1_TAG}"
    GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V2_TAG}"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"

    // Safe-mode defaults (conservative to avoid quota issues)
    DEFAULT_DESIRED_REPLICAS = "3"
    SAFE_REPLICAS = "1"
    SAFE_REQUEST_CPU = "100m"
    SAFE_LIMIT_CPU = "500m"
    SAFE_REQUEST_MEM = "256Mi"
    SAFE_LIMIT_MEM = "512Mi"
  }

  stages {

    stage('Clean & Checkout') {
      steps {
        cleanWs()
        sh '''
          set -e
          git clone https://github.com/Nagasai634/k8s-Usecase.git || true
          cd k8s-Usecase/java-gradle || true
          chmod +x ./gradlew || true
        '''
      }
    }

    stage('Ensure Tools') {
      steps {
        sh '''
          set -e
          mkdir -p "${WORKSPACE_BIN}"
          if [ ! -x "${WORKSPACE_BIN}/kubectl" ]; then
            KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
            curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o "${WORKSPACE_BIN}/kubectl"
            chmod +x "${WORKSPACE_BIN}/kubectl"
          fi
          echo "kubectl (client):"
          "${WORKSPACE_BIN}/kubectl" version --client || true

          if command -v docker >/dev/null 2>&1; then
            docker --version || true
          else
            echo "WARNING: docker not found on agent. Build/push will fail unless agent has docker or use remote builder."
          fi

          gcloud --version || true
        '''
      }
    }

    stage('Build & Push Images (v1 + v2)') {
      steps {
        // Requires a Jenkins file credential with the SA JSON; credentialId used below
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
            gcloud config set project ${PROJECT_ID}
            gcloud auth configure-docker ${GAR_HOST} --quiet_
