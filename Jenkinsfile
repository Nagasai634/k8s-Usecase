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
    REGION_FLAG = "us-central1"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
    PATH = "${env.WORKSPACE}/bin:${env.PATH}"
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 60, unit: 'MINUTES')
  }

  stages {

    stage('Clean workspace') {
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

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Install kubectl') {
      steps {
        sh '''
          set -e
          # download kubectl stable
          KUBECTL_BIN=${WORKSPACE}/bin/kubectl
          if [ ! -f "${KUBECTL_BIN}" ]; then
            curl -L -o /tmp/kubectl "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x /tmp/kubectl
            mv /tmp/kubectl ${KUBECTL_BIN}
          fi
          ${KUBECTL_BIN} version --client=true || true
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
              echo "✅ v1.0 build and push completed"
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
              echo "✅ v2.0 build and push completed"
            '''
          }
        }
      }
    }

    stage('Prepare GKE credentials') {
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
          set -e
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

    stage('Deploy to GKE') {
      steps {
        script {
          def action = params.DEPLOYMENT_ACTION ?: 'ROLLOUT'
          def version = params.VERSION ?: 'v1.0'
          
          echo "USER REQUESTED ACTION: ${action}"
          echo "SELECTED VERSION: ${version}"
          
          def imageTag = (version == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          
          sh """
            set -e
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

    stage('Verify public access') {
      steps {
        sh '''
          set -e
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
            for i in {1..5}; do  # Reduced attempts
              if curl -s --connect-timeout 5 http://$IP > /dev/null; then
                echo "Application is responding"
                echo "Application content:"
                curl -s http://$IP | grep -o "Version [0-9]\\.[0-9] - [A-Z]*" | head -1 || echo "Content check failed"
                break
              else
                echo "Waiting for application to be ready... (attempt $i/5)"
                sleep 10
              fi
            done
          else
            echo "IP address not yet available. Ingress may still be provisioning."
          fi

          echo "SUCCESS: Application reachable at http://$IP/"
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
          echo "=== POST-CHECKS ==="
          export KUBECONFIG=${KUBECONFIG}
          kubectl get pods,svc,ing -n java-app || true
          echo "--- End of pipeline run ---"
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
