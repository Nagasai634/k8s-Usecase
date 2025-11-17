pipeline {
  agent any

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

    stage('Install kubectl') {
      steps {
        sh '''
          mkdir -p ${WORKSPACE}/bin
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x ./kubectl
          mv ./kubectl ${WORKSPACE}/bin/
          export PATH="${WORKSPACE}/bin:${PATH}"
          kubectl version --client
        '''
      }
    }

    stage('Setup GCP') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}
            gcloud auth configure-docker ${GAR_HOST} --quiet
          '''
        }
      }
    }

    stage('Build Version 1 (Blue)') {
      steps {
        sh '''
          cd k8s-Usecase/java-gradle
          echo "=== Building Version 1 (Blue) ==="
          
          # Create version 1 with blue theme
          cat > src/main/resources/templates/version.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Java App - Version 1.0</title>
    <style>
        body { 
            background-color: #1e3a8a; 
            color: white; 
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
        }
        .container { 
            background: rgba(255,255,255,0.1); 
            padding: 30px; 
            border-radius: 10px;
            margin: 20px auto;
            max-width: 600px;
        }
        h1 { color: #60a5fa; }
        .feature { background: #3b82f6; padding: 10px; margin: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Java Gradle Application</h1>
        <h2>Version 1.0 - BLUE DEPLOYMENT</h2>
        <p>Build: ${BUILD_NUMBER}</p>
        <p>Environment: Production</p>
        <div class="feature">
            <h3>Features in v1.0:</h3>
            <ul style="text-align: left;">
                <li>Basic CRUD Operations</li>
                <li>REST API Endpoints</li>
                <li>Health Check</li>
                <li>Blue Color Theme</li>
            </ul>
        </div>
        <p><strong>Deployment Strategy: Rolling Update</strong></p>
    </div>
</body>
</html>
EOF

          ./gradlew clean build --no-daemon
          docker build -t ${GAR_IMAGE_V1} .
          docker push ${GAR_IMAGE_V1}
          echo "Version 1 (Blue) pushed: ${GAR_IMAGE_V1}"
        '''
      }
    }

    stage('Build Version 2 (Green)') {
      steps {
        sh '''
          cd k8s-Usecase/java-gradle
          echo "=== Building Version 2 (Green) ==="
          
          # Create version 2 with green theme and new features
          cat > src/main/resources/templates/version.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Java App - Version 2.0</title>
    <style>
        body { 
            background-color: #065f46; 
            color: white; 
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
        }
        .container { 
            background: rgba(255,255,255,0.1); 
            padding: 30px; 
            border-radius: 10px;
            margin: 20px auto;
            max-width: 600px;
        }
        h1 { color: #34d399; }
        .feature { background: #10b981; padding: 10px; margin: 10px; border-radius: 5px; }
        .new-badge { background: #f59e0b; color: black; padding: 5px 10px; border-radius: 15px; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎯 Java Gradle Application</h1>
        <h2>Version 2.0 - GREEN DEPLOYMENT <span class="new-badge">NEW</span></h2>
        <p>Build: ${BUILD_NUMBER}</p>
        <p>Environment: Production</p>
        <div class="feature">
            <h3>🚀 New Features in v2.0:</h3>
            <ul style="text-align: left;">
                <li>Advanced Analytics Dashboard <span class="new-badge">NEW</span></li>
                <li>Real-time Notifications <span class="new-badge">NEW</span></li>
                <li>Enhanced Security Features <span class="new-badge">NEW</span></li>
                <li>Performance Optimizations <span class="new-badge">IMPROVED</span></li>
                <li>All v1.0 Features</li>
            </ul>
        </div>
        <p><strong>Deployment Strategy: Canary Release</strong></p>
        <p style="color: #fbbf24;">⭐ This is the latest version with exciting new features!</p>
    </div>
</body>
</html>
EOF

          ./gradlew clean build --no-daemon
          docker build -t ${GAR_IMAGE_V2} .
          docker push ${GAR_IMAGE_V2}
          echo "Version 2 (Green) pushed: ${GAR_IMAGE_V2}"
        '''
      }
    }

    stage('Deploy Version 1 (Initial)') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            export PATH="${WORKSPACE}/bin:${PATH}"
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            
            # Get cluster credentials (using legacy auth to avoid plugin issues)
            gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID} --internal-ip
            
            # Create namespace
            kubectl create namespace java-app --dry-run=client -o yaml | kubectl apply -f -
            
            # Deploy Version 1 initially
            echo "=== Deploying Version 1 (Blue) as Initial Release ==="
            kubectl apply -f k8s-Usecase/k8s/ -n java-app
            
            # Wait for initial deployment
            kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s
            
            echo "Version 1 deployed successfully!"
          '''
        }
      }
    }

    stage('Test Version 1') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          echo "=== Testing Version 1 ==="
          kubectl get pods -n java-app -l app=java-gradle-app
          echo "Version 1 is running with Blue theme"
        '''
      }
    }

    stage('Rollout Version 2 (Canary)') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          echo "=== Rolling out Version 2 (Green) - Canary Deployment ==="
          
          # Start rollout to Version 2
          kubectl set image deployment/java-gradle-app java-app=${GAR_IMAGE_V2} -n java-app --record
          
          # Watch the rollout progress
          echo "Rollout in progress... You should see both versions during transition"
          kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s --watch
          
          echo "Version 2 rollout completed!"
        '''
      }
    }

    stage('Verify Version 2') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          echo "=== Verifying Version 2 ==="
          kubectl get pods -n java-app -l app=java-gradle-app
          kubectl get deployment java-gradle-app -n java-app -o wide
          
          # Get the service IP
          echo "=== Application Access ==="
          IP=$(kubectl get ingress -n java-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not assigned yet")
          echo "Access your application at: http://$IP"
          echo "You should see the GREEN Version 2 interface"
        '''
      }
    }

    stage('Rollback to Version 1 (If Needed)') {
      steps {
        input {
          message "Do you want to rollback to Version 1?"
          ok "Yes, Rollback to Blue"
          parameters {
            booleanParam(name: 'ROLLBACK', defaultValue: false, description: 'Rollback to Version 1?')
          }
        }
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          if [ "$ROLLBACK" = "true" ]; then
            echo "=== Initiating Rollback to Version 1 (Blue) ==="
            
            # Check current revision
            echo "Current deployment history:"
            kubectl rollout history deployment/java-gradle-app -n java-app
            
            # Perform rollback
            kubectl rollout undo deployment/java-gradle-app -n java-app
            kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s
            
            echo "Rollback to Version 1 completed!"
            echo "You should see the BLUE Version 1 interface again"
          else
            echo "Rollback skipped - Version 2 remains deployed"
          fi
        '''
      }
    }
  }

  post {
    always {
      sh '''
        export PATH="${WORKSPACE}/bin:${PATH}"
        echo "=== Final Deployment Status ==="
        kubectl get deployments,svc,pods -n java-app
        
        echo "=== Deployment History ==="
        kubectl rollout history deployment/java-gradle-app -n java-app
        
        IP=$(kubectl get ingress -n java-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not assigned")
        echo "Final Application URL: http://$IP"
      '''
    }
  }
}