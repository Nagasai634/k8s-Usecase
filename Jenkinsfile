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

    stage('Clean Existing Deployment') {
      when {
        expression { params.DEPLOYMENT_ACTION == 'ROLLOUT' }
      }
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          export KUBECONFIG=${KUBECONFIG}
          
          echo "🧹 Cleaning up existing deployment resources..."
          
          # Delete existing deployment and replicasets
          kubectl delete deployment java-gradle-app -n java-app --ignore-not-found=true --timeout=30s
          kubectl delete replicaset -l app=java-gradle-app -n java-app --ignore-not-found=true --timeout=30s
          
          # Wait for cleanup to complete
          echo "⏳ Waiting for resources to be cleaned up..."
          sleep 20
          
          # Verify cleanup
          kubectl get deployment,replicaset,pod -n java-app --ignore-not-found=true
        '''
      }
    }

    stage('Execute User Requested Action') {
      steps {
        script {
          def action = params.DEPLOYMENT_ACTION
          def version = params.VERSION
          
          echo "🎯 USER REQUESTED ACTION: ${action}"
          echo "🎯 SELECTED VERSION: ${version}"
          
          // Determine the image tag in Groovy to avoid interpolation issues
          def imageTag
          if (version == 'v1.0') {
            imageTag = env.GAR_IMAGE_V1
          } else {
            imageTag = env.GAR_IMAGE_V2
          }
          
          sh """
            export PATH="${WORKSPACE}/bin:${PATH}"
            export KUBECONFIG=${KUBECONFIG}
            
            if [ "${action}" = "ROLLOUT" ]; then
              echo "🚀 EXECUTING: Rolling out ${version}"
              kubectl create namespace java-app --dry-run=client -o yaml | kubectl apply -f -
              
              echo "📦 Using image: ${imageTag}"
              
              # Apply base resources
              kubectl apply -f k8s-Usecase/configmap.yaml -f k8s-Usecase/frontend-config.yaml -f k8s-Usecase/hpa.yaml -f k8s-Usecase/ingress.yaml -f k8s-Usecase/service.yaml -n java-app --validate=false
              
              # Create deployment with the specific image tag and health checks
              cat > /tmp/deployment-${version}.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-gradle-app
  namespace: java-app
  labels:
    app: java-gradle-app
    version: ${version}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: java-gradle-app
  template:
    metadata:
      labels:
        app: java-gradle-app
        version: ${version}
    spec:
      containers:
      - name: java-app
        image: ${imageTag}
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: app-config
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        imagePullPolicy: Always
EOF
              
              kubectl apply -f /tmp/deployment-${version}.yaml
              
              # Wait for rollout with comprehensive debugging
              echo "⏳ Waiting for rollout to complete (timeout: 10 minutes)..."
              if kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s; then
                echo "✅ Rollout completed successfully"
              else
                echo "❌ Rollout failed or timed out. Debugging information:"
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
                exit 1
              fi
              
            else
              echo "🔄 EXECUTING: Rolling back"
              if kubectl rollout undo deployment/java-gradle-app -n java-app; then
                kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s
                echo "✅ Rollback completed successfully"
              else
                echo "❌ Rollback failed"
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
          echo "📊 Deployment Status:"
          kubectl get deployment java-gradle-app -n java-app -o wide
          
          echo "📦 Pod Status:"
          kubectl get pods -l app=java-gradle-app -n java-app -o wide
          
          echo "🔍 ReplicaSet Status:"
          kubectl get replicaset -l app=java-gradle-app -n java-app -o wide
          
          # Get service and ingress information
          echo "🌐 Service Details:"
          kubectl get service java-gradle-service -n java-app -o wide
          
          echo "🔗 Ingress Details:"
          kubectl get ingress java-app-ingress -n java-app -o wide
          
          IP=$(kubectl get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
          echo "🌐 Application URL: http://$IP"
          
          # Test application if IP is available
          if [ "$IP" != "Pending" ] && [ ! -z "$IP" ]; then
            echo "🧪 Testing application endpoint..."
            for i in {1..10}; do
              if curl -s --connect-timeout 5 http://$IP > /dev/null; then
                echo "✅ Application is responding"
                echo "📄 Application content:"
                curl -s http://$IP | grep -o "Version [0-9]\\.[0-9] - [A-Z]*" | head -1 || echo "Content check failed"
                break
              else
                echo "⏳ Waiting for application to be ready... (attempt $i/10)"
                sleep 10
              fi
            done
          else
            echo "⚠️  IP address not yet available. Ingress may still be provisioning."
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
          echo "Action Requested: ${params.DEPLOYMENT_ACTION}"
          echo "Version Selected: ${params.VERSION}"
          echo "Build Number: ${BUILD_NUMBER}"
          echo "Status: ${currentResult}"
        """
        
        // Clean up temporary files
        sh '''
          rm -f /tmp/deployment-v1.0.yaml /tmp/deployment-v2.0.yaml 2>/dev/null || true
        '''
      }
    }
    success {
      script {
        echo "🎉 Pipeline executed successfully!"
        echo "Deployment action '${params.DEPLOYMENT_ACTION}' for version '${params.VERSION}' completed."
      }
    }
    failure {
      script {
        echo "❌ Pipeline failed during '${params.DEPLOYMENT_ACTION}' for version '${params.VERSION}'"
        echo "Check the detailed logs above for troubleshooting information."
      }
    }
    unstable {
      script {
        echo "⚠️ Pipeline marked as unstable"
      }
    }
  }
}