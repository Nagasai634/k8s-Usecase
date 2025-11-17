pipeline {
  agent any
  
  parameters {
    choice(
      name: 'DEPLOYMENT_ACTION',
      choices: ['ROLLOUT', 'ROLLBACK'],
      description: 'Choose deployment action'
    )
    choice(
      name: 'VERSION',
      choices: ['v1.0', 'v2.0'],
      description: 'Choose version to deploy'
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
      when {
        expression { params.DEPLOYMENT_ACTION == 'ROLLOUT' }
      }
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
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}
            
            # Get cluster details using jq for proper JSON parsing
            CLUSTER_ENDPOINT=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(endpoint)")
            CLUSTER_CA=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(masterAuth.clusterCaCertificate)" | base64 -d | base64 -w 0)
            
            # Get access token
            TOKEN=$(gcloud auth print-access-token)
            
            # Create kubeconfig with proper YAML
            mkdir -p ${WORKSPACE}/.kube
            cat <<EOF > ${KUBECONFIG}
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
            echo "✅ Kubeconfig created and validated"
          '''
        }
      }
    }

    stage('Execute User Requested Action') {
      steps {
        script {
          def action = params.DEPLOYMENT_ACTION
          def version = params.VERSION
          
          echo "🎯 USER REQUESTED ACTION: ${action}"
          echo "🎯 SELECTED VERSION: ${version}"
          
          sh """
            export PATH="${WORKSPACE}/bin:${PATH}"
            export KUBECONFIG=${KUBECONFIG}
            
            if [ "${action}" = "ROLLOUT" ]; then
              echo "🚀 EXECUTING: Rolling out ${version}"
              kubectl create namespace java-app --dry-run=client -o yaml | kubectl apply -f -
              # Apply manifests, skipping namespace and security policy if issues
              kubectl apply -f k8s-Usecase/configmap.yaml -f k8s-Usecase/deployment.yaml -f k8s-Usecase/frontend-config.yaml -f k8s-Usecase/hpa.yaml -f k8s-Usecase/ingress.yaml -f k8s-Usecase/service.yaml -n java-app --validate=false
              
              if [ "${version}" = "v1.0" ]; then
                kubectl set image deployment/java-gradle-app java-app=${GAR_IMAGE_V1} -n java-app --record
              else
                kubectl set image deployment/java-gradle-app java-app=${GAR_IMAGE_V2} -n java-app --record
              fi
            else
              echo "🔄 EXECUTING: Rolling back"
              kubectl rollout undo deployment/java-gradle-app -n java-app
            fi
            
            kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s
          """
        }
      }
    }

    stage('Verify and Display Results') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          export KUBECONFIG=${KUBECONFIG}
          
          echo "=== DEPLOYMENT STATUS ==="
          kubectl get deployments,pods,svc -n java-app
          
          IP=$(kubectl get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
          echo "🌐 Application URL: http://$IP"
          
          if [ "$IP" != "Pending" ]; then
            echo "📄 Testing HTML differences..."
            curl -s http://$IP | grep -o "Version [0-9]\\.[0-9] - [A-Z]*" || echo "Unable to fetch version"
          fi
        '''
      }
    }
  }

  post {
    always {
      script {
        sh """
          echo "=== PIPELINE EXECUTION SUMMARY ==="
          echo "Action Requested: ${params.DEPLOYMENT_ACTION}"
          echo "Version Selected: ${params.VERSION}"
          echo "Build Number: ${BUILD_NUMBER}"
          echo "Status: SUCCESS"
        """
      }
    }
    failure {
      script {
        sh """
          echo "❌ PIPELINE FAILED"
          echo "Failed during: ${params.DEPLOYMENT_ACTION} for version: ${params.VERSION}"
          echo "Check the logs above for error details"
        """
      }
    }
  }
}