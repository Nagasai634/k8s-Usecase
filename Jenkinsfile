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
        sh '''
          # Repo is already checked out via SCM; no need to clean or clone
          cd java-gradle
          # Remove problematic files if they exist
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
              cd java-gradle
              echo "Building v1.0 using existing Dockerfile and static files..."
              ./gradlew clean build --no-daemon
              docker build -t ${GAR_IMAGE_V1} .
              docker push ${GAR_IMAGE_V1}
              echo "v1.0 build and push completed"
            '''
          }
        }
        stage('Build v2.0') {
          steps {
            sh '''
              cd java-gradle
              echo "Building v2.0 using existing Dockerfile and static files..."
              ./gradlew clean build --no-daemon
              docker build -t ${GAR_IMAGE_V2} .
              docker push ${GAR_IMAGE_V2}
              echo "v2.0 build and push completed"
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
            export KUBECONFIG=${KUBECONFIG}
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}
            
            CLUSTER_ENDPOINT=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(endpoint)")
            CLUSTER_CA=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(masterAuth.clusterCaCertificate)" | base64 -d | base64 -w 0)
            
            TOKEN=$(gcloud auth print-access-token)
            
            mkdir -p ${WORKSPACE}/.kube
            cat > ${KUBECONFIG} <<EOF
apiVersion: v1
kind: Config
current-context: ${CLUSTER_NAME}
contexts:
- name: ${CLUSTER_NAME}
  context:
    cluster: ${CLUSTER_NAME}
    user: ${CLUSTER_NAME}
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: https://${CLUSTER_ENDPOINT}
users:
- name: ${CLUSTER_NAME}
  user:
    token: ${TOKEN}
EOF
            
            if ! kubectl cluster-info --kubeconfig=${KUBECONFIG}; then
              echo "ERROR: Kubeconfig validation failed"
              exit 1
            fi
            echo "Kubeconfig created and validated"
          '''
        }
      }
    }

    stage('Deploy Infrastructure') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          export KUBECONFIG=${KUBECONFIG}
          
          echo "Creating namespace and deploying infrastructure..."
          kubectl create namespace java-app --dry-run=client -o yaml | kubectl apply -f -
          
          kubectl apply -f configmap.yaml -n java-app
          kubectl apply -f service.yaml -n java-app
          kubectl apply -f ingress.yaml -n java-app
          
          echo "Waiting for infrastructure to stabilize..."
          sleep 30
        '''
      }
    }

    stage('Execute User Requested Action') {
      steps {
        script {
          def action = params.DEPLOYMENT_ACTION ?: 'ROLLOUT'
          def version = params.VERSION ?: 'v1.0'
          
          echo "USER REQUESTED ACTION: ${action}"
          echo "SELECTED VERSION: ${version}"
          
          def imageTag = (version == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          
          sh """
            export PATH="${WORKSPACE}/bin:${PATH}"
            export KUBECONFIG=${KUBECONFIG}
            
            if [ "${action}" = "ROLLOUT" ]; then
              echo "EXECUTING: Rolling out ${version}"
              echo "Using image: ${imageTag}"
              
              cp deployment.yaml /tmp/deployment-${version}.yaml
              sed -i "s|IMAGE_PLACEHOLDER|${imageTag}|g" /tmp/deployment-${version}.yaml
              sed -i "s|VERSION_PLACEHOLDER|${version}|g" /tmp/deployment-${version}.yaml
              
              kubectl apply -f /tmp/deployment-${version}.yaml -n java-app --validate=false
              
              echo "Waiting for pods to be ready..."
              sleep 30
              
              echo "Checking rollout status (shortened timeout: 5 minutes)..."
              if kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s; then
                echo "Rollout completed successfully"
              else
                echo "WARNING: Rollout timed out or failed, but continuing pipeline. Check logs below for details."
                echo "=== Deployment Details ==="
                kubectl describe deployment java-gradle-app -n java-app
                echo "=== Pod Status ==="
                kubectl get pods -n java-app -o wide
                echo "=== ReplicaSet Status ==="
                kubectl get replicaset -n java-app -o wide
                echo "=== Pod Logs (first container each pod) ==="
                for POD in \$(kubectl get pods -l app=java-gradle-app -n java-app -o name); do
                  echo "--- Logs for \${POD} ---"
                  kubectl logs \${POD} -n java-app --tail=50 || echo "No logs available"
                done
                echo "=== Events ==="
                kubectl get events -n java-app --sort-by=.lastTimestamp | tail -30
              fi
              
            else
              echo "EXECUTING: Rolling back"
              if kubectl rollout undo deployment/java-gradle-app -n java-app; then
                kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s
                echo "Rollback completed successfully"
              else
                echo "Rollback failed"
              fi
            fi
          """
        }
      }
    }

    stage('Verify Deployment') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          export KUBECONFIG=${KUBECONFIG}
          
          echo "=== DEPLOYMENT VERIFICATION ==="
          echo "Deployment Status:"
          kubectl get deployment java-gradle-app -n java-app -o wide
          
          echo "Pod Status:"
          kubectl get pods -l app=java-gradle-app -n java-app -o wide
          
          echo "ReplicaSet Status:"
          kubectl get replicaset -l app=java-gradle-app -n java-app -o wide
          
          echo "Service Details:"
          kubectl get service java-gradle-service -n java-app -o wide
          
          echo "Ingress Details:"
          kubectl get ingress java-app-ingress -n java-app -o wide
          
          IP=$(kubectl get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
          echo "Application URL: http://$IP"
          
          if [ "$IP" != "Pending" ] && [ ! -z "$IP" ]; then
            echo "Testing application endpoint..."
            RESPONSE=$(curl -v --connect-timeout 5 --max-time 10 http://$IP 2>&1)
            if echo "$RESPONSE" | grep -q "200 OK"; then
              echo "Application is responding"
              echo "Application content:"
              echo "$RESPONSE" | grep -o "Version [0-9]\\.[0-9] - [A-Z]*" | head -1 || echo "Content check failed"
            else
              echo "ERROR: Application not responding. Debugging info:"
              echo "Curl response: $RESPONSE"
              echo "=== Pod Readiness ==="
              kubectl get pods -l app=java-gradle-app -n java-app -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
              echo "=== Service Endpoints ==="
              kubectl get endpoints java-gradle-service -n java-app
              echo "=== Pod Logs (last 20 lines) ==="
              for POD in $(kubectl get pods -l app=java-gradle-app -n java-app -o name); do
                echo "--- Logs for $POD ---"
                kubectl logs $POD -n java-app --tail=20 || echo "No logs available"
              done
              echo "=== Events ==="
              kubectl get events -n java-app --sort-by=.lastTimestamp | tail -10
              exit 1  # Fail the pipeline if app doesn't respond
            fi
          else
            echo "IP address not yet available. Ingress may still be provisioning."
            exit 1
          fi
        '''
      }
    }
  }

  post {
    always {
      script {
        def currentResult = currentBuild.result ?: 'SUCCESS'
        sh """
          echo "=== PIPELINE EXECUTION SUMMARY ==="
          echo "Action Requested: ${params.DEPLOYMENT_ACTION ?: 'N/A'}"
          echo "Version Selected: ${params.VERSION ?: 'N/A'}"
          echo "Build Number: ${BUILD_NUMBER}"
          echo "Status: ${currentResult}"
        """
        
        sh '''
          rm -f /tmp/deployment-v1.0.yaml /tmp/deployment-v2.0.yaml 2>/dev/null || true
        '''
      }
    }
    success {
      script {
        echo "Pipeline executed successfully!"
        echo "Deployment action '${params.DEPLOYMENT_ACTION ?: 'ROLLOUT'}' for version '${params.VERSION ?: 'v1.0'}' completed."
      }
    }
    failure {
      script {
        echo "Pipeline failed during '${params.DEPLOYMENT_ACTION ?: 'ROLLOUT'}' for version '${params.VERSION ?: 'v1.0'}'"
        echo "Check the detailed logs above for troubleshooting information."
      }
    }
    unstable {
      script {
        echo "Pipeline marked as unstable"
      }
    }
  }
}
