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
          # Create health endpoint
          mkdir -p src/main/java/com/example/demo
          cat > src/main/java/com/example/demo/HealthController.java << 'EOF'
package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
    
    @GetMapping("/health")
    public String health() {
        return "OK";
    }
    
    @GetMapping("/")
    public String home() {
        return "<!DOCTYPE html><html><head><title>Java App</title><style>body{font-family:Arial,sans-serif;text-align:center;padding:50px}</style></head><body><h1>Welcome to Java Application</h1><p>Application is running successfully!</p></body></html>";
    }
}
EOF
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
          
          # Clean up any existing resources
          kubectl delete ingress java-app-ingress -n java-app --ignore-not-found=true
          kubectl delete service java-gradle-service -n java-app --ignore-not-found=true
          kubectl delete backendconfig java-app-backend-config -n java-app --ignore-not-found=true
          sleep 10
          
          # Apply infrastructure resources
          kubectl apply -f k8s-Usecase/configmap.yaml -n java-app
          kubectl apply -f k8s-Usecase/backendconfig.yaml -n java-app
          kubectl apply -f k8s-Usecase/service.yaml -n java-app
          kubectl apply -f k8s-Usecase/ingress.yaml -n java-app
          
          echo "Waiting for infrastructure to stabilize..."
          sleep 30
        '''
      }
    }

    stage('Execute User Requested Action') {
      steps {
        script {
          def action
          def version
          
          if (env.BUILD_NUMBER == '1') {
            action = 'ROLLOUT'
            version = 'v1.0'
            echo "First build: Automatically deploying v1.0"
          } else {
            action = params.DEPLOYMENT_ACTION
            version = params.VERSION
            echo "USER REQUESTED ACTION: ${action}"
            echo "SELECTED VERSION: ${version}"
          }
          
          def imageTag = (version == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          
          sh """
            export PATH="${WORKSPACE}/bin:${PATH}"
            export KUBECONFIG=${KUBECONFIG}
            
            if [ "${action}" = "ROLLOUT" ]; then
              echo "EXECUTING: Rolling out ${version}"
              
              echo "Using image: ${imageTag}"
              
              cp k8s-Usecase/deployment.yaml /tmp/deployment-${version}.yaml
              sed -i "s|IMAGE_PLACEHOLDER|${imageTag}|g" /tmp/deployment-${version}.yaml
              sed -i "s|VERSION_PLACEHOLDER|${version}|g" /tmp/deployment-${version}.yaml
              
              kubectl apply -f /tmp/deployment-${version}.yaml -n java-app --validate=false
              
              echo "Waiting for pods to be ready..."
              # Wait for pods to be created first
              sleep 30
              
              echo "Waiting for rollout to complete (timeout: 10 minutes)..."
              if kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s; then
                echo "✅ Rollout completed successfully"
                
                # Test internal service connectivity
                echo "Testing internal service connectivity..."
                kubectl run test-pod --image=curlimages/curl -n java-app --rm -i --restart=Never -- curl -s http://java-gradle-service:80/health || echo "Internal service test failed"
                
              else
                echo "❌ Rollout failed or timed out. Debugging information:"
                echo "=== Deployment Details ==="
                kubectl describe deployment java-gradle-app -n java-app
                echo "=== Pod Status ==="
                kubectl get pods -n java-app -o wide
                echo "=== Pod Logs ==="
                for POD in \$(kubectl get pods -l app=java-gradle-app -n java-app -o name); do
                  echo "--- Logs for \${POD} ---"
                  kubectl logs \${POD} -n java-app --tail=100 || echo "No logs available"
                done
                echo "=== Service Endpoints ==="
                kubectl get endpoints java-gradle-service -n java-app
                echo "=== Events ==="
                kubectl get events -n java-app --sort-by=.lastTimestamp | tail -30
                exit 1
              fi
              
            else
              echo "EXECUTING: Rolling back"
              if kubectl rollout undo deployment/java-gradle-app -n java-app; then
                kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s
                echo "Rollback completed successfully"
              else
                echo "Rollback failed"
                exit 1
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
          
          echo "Service Details:"
          kubectl get service java-gradle-service -n java-app -o wide
          
          echo "Service Endpoints:"
          kubectl get endpoints java-gradle-service -n java-app
          
          echo "Ingress Details:"
          kubectl get ingress java-app-ingress -n java-app -o wide
          
          # Wait for ingress IP to be assigned (longer wait for GCP LB)
          echo "Waiting for Ingress IP assignment (this can take 5-10 minutes)..."
          IP=""
          for i in {1..60}; do
            IP=$(kubectl get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ ! -z "$IP" ] && [ "$IP" != "null" ]; then
              echo "✅ IP assigned: $IP"
              break
            fi
            echo "Waiting for IP... (attempt $i/60 - ~$((i*1)) minutes)"
            sleep 60
          done
          
          if [ ! -z "$IP" ] && [ "$IP" != "null" ]; then
            echo "Application URL: http://$IP"
            echo "Testing application endpoint (this can take a few minutes after IP assignment)..."
            
            # Wait for application to be reachable through LB
            for i in {1..30}; do
              if curl -f -s --connect-timeout 10 http://$IP/health > /dev/null; then
                echo "✅ Application is responding successfully through Load Balancer!"
                echo "=== Application Content ==="
                curl -s http://$IP/ | grep -E "(Welcome|Version|BLUE|GREEN)" | head -5 || echo "Content retrieved successfully"
                break
              else
                echo "Waiting for application to be reachable through Load Balancer... (attempt $i/30)"
                sleep 30
              fi
            done
            
            # Final test
            if curl -f -s --connect-timeout 10 http://$IP/health; then
              echo "🎉 SUCCESS: Application is fully operational!"
              echo "🌐 Access your application at: http://$IP"
            else
              echo "❌ Application not reachable through Load Balancer after waiting"
              echo "Debugging information:"
              kubectl describe ingress java-app-ingress -n java-app
              echo "=== Backend Services ==="
              gcloud compute backend-services list --format="table(name, protocol, loadBalancingScheme)"
              exit 1
            fi
          else
            echo "❌ IP address not assigned after 60 minutes. Check ingress configuration."
            echo "Debugging information:"
            kubectl describe ingress java-app-ingress -n java-app
            echo "=== GCP Load Balancer Status ==="
            gcloud compute forwarding-rules list --format="table(name, IPAddress, target.scope())"
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
  }
}
