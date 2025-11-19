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
    stage('Clean Workspace') {
      steps {
        cleanWs()
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
              
              # Create v1.0 HTML content
              cat > src/main/resources/static/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>V1.0</title>
    <style>
        body {
            background: #1e3a8a;
            color: white;
            text-align: center;
            padding: 50px;
            font-family: Arial, sans-serif;
        }
        .container {
            background: rgba(255,255,255,0.1);
            padding: 30px;
            border-radius: 10px;
            margin: auto;
            max-width: 600px;
        }
        h1 {
            color: #60a5fa;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Version 1.0 - BLUE</h1>
        <p>Simple Java Application</p>
        <p>Build: ${BUILD_NUMBER}</p>
    </div>
</body>
</html>
EOF

              echo "Building v1.0..."
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
              
              # Create v2.0 HTML content
              cat > src/main/resources/static/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>V2.0</title>
    <style>
        body {
            background: #065f46;
            color: white;
            text-align: center;
            padding: 50px;
            font-family: Arial, sans-serif;
        }
        .container {
            background: rgba(255,255,255,0.1);
            padding: 30px;
            border-radius: 10px;
            margin: auto;
            max-width: 600px;
        }
        h1 {
            color: #34d399;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎯 Version 2.0 - GREEN</h1>
        <p>Enhanced Java Application</p>
        <p>Build: ${BUILD_NUMBER}</p>
    </div>
</body>
</html>
EOF

              echo "Building v2.0..."
              ./gradlew clean build --no-daemon
              
              docker build -t ${GAR_IMAGE_V2} .
              docker push ${GAR_IMAGE_V2}
              echo "✅ v2.0 build and push completed"
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
          
          # Apply infrastructure resources
          kubectl apply -f configmap.yaml -n java-app
          kubectl apply -f service.yaml -n java-app
          kubectl apply -f ingress.yaml -n java-app
          
          echo "Waiting for infrastructure to stabilize..."
          sleep 10
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
              
              # Create deployment with proper health checks
              cat > /tmp/deployment-${version}.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-gradle-app
  namespace: java-app
  labels:
    app: java-gradle-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: java-gradle-app
  template:
    metadata:
      labels:
        app: java-gradle-app
    spec:
      containers:
      - name: java-app
        image: ${imageTag}
        ports:
        - containerPort: 8080
          name: http
        envFrom:
        - configMapRef:
            name: app-config
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
            ephemeral-storage: "1Gi"
          limits:
            memory: "1Gi"
            cpu: "1"
            ephemeral-storage: "1Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
EOF
              
              kubectl apply -f /tmp/deployment-${version}.yaml -n java-app --validate=false
              
              echo "Waiting for rollout to complete (timeout: 5 minutes)..."
              if kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s; then
                echo "✅ Rollout completed successfully"
              else
                echo "❌ Rollout failed or timed out. Debugging information:"
                echo "=== Pod Status ==="
                kubectl get pods -n java-app -o wide
                echo "=== Pod Logs ==="
                for POD in \$(kubectl get pods -l app=java-gradle-app -n java-app -o name); do
                  echo "--- Logs for \${POD} ---"
                  kubectl logs \${POD} -n java-app --tail=50 || echo "No logs available"
                done
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
          echo "Pod Status:"
          kubectl get pods -l app=java-gradle-app -n java-app -o wide
          
          echo "Service Details:"
          kubectl get service java-gradle-service -n java-app -o wide
          
          echo "Ingress Details:"
          kubectl get ingress java-app-ingress -n java-app -o wide
          
          # Get Ingress IP
          IP=$(kubectl get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
          
          if [ ! -z "$IP" ] && [ "$IP" != "null" ]; then
            echo "Application URL: http://$IP"
            echo "Testing application endpoint..."
            
            # Wait for application to be reachable
            for i in {1..10}; do
              if curl -f -s --connect-timeout 10 http://$IP/health > /dev/null; then
                echo "✅ Application is responding successfully!"
                echo "=== Application Content ==="
                curl -s http://$IP/ | head -10
                break
              else
                echo "Waiting for application to be reachable... (attempt $i/10)"
                sleep 10
              fi
            done
          else
            echo "IP address not yet assigned. Ingress may still be provisioning."
            echo "You can check later with: kubectl get ingress java-app-ingress -n java-app"
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
        
        // Cleanup temp files
        sh '''
          rm -f /tmp/deployment-v1.0.yaml /tmp/deployment-v2.0.yaml 2>/dev/null || true
        '''
      }
    }
  }
}
