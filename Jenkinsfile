pipeline {
  agent any

  // UI parameters used only after first deployment exists
  parameters {
    choice(
      name: 'DEPLOYMENT_ACTION',
      choices: ['ROLLOUT', 'ROLLBACK'],
      description: 'Choose deployment action (ignored on first run; first run auto-deploys v1.0)'
    )
    choice(
      name: 'VERSION',
      choices: ['v1.0', 'v2.0'],
      description: 'Choose version to deploy (ignored on first run)'
    )
  }

  environment {
    PROJECT_ID = 'planar-door-476510-m1'           // <-- set your project
    REGION = 'us-central1'
    GAR_REPO = 'java-app'
    IMAGE_NAME = "java-app"
    // tags include build number so each build produces unique images
    V1_TAG = "v1.0-${env.BUILD_NUMBER}"
    V2_TAG = "v2.0-${env.BUILD_NUMBER}"
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V1_TAG}"
    GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V2_TAG}"
    CLUSTER_NAME = "autopilot-demo"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
    // Replace this with the allowed client IP (or CIDR) that should be able to access the app
    // e.g. "203.0.113.5/32" — change to your IP/CIDR or store in Jenkins credential and read via withCredentials
    ALLOWED_IP_CIDR = '203.0.113.5/32'
  }

  stages {
    stage('Clean Project') {
      steps {
        cleanWs()
        sh '''
          git clone https://github.com/Nagasai634/k8s-Usecase.git || true
          cd k8s-Usecase/java-gradle
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

    stage('Build & Push Images (both versions)') {
      steps {
        sh '''
          set -e
          cd k8s-Usecase/java-gradle

          # ensure static index exists for each version and build, tag & push
          mkdir -p src/main/resources/static

          # v1 content
          echo '<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>' > src/main/resources/static/index.html
          ./gradlew clean build --no-daemon
          docker build -t ${GAR_IMAGE_V1} .
          docker push ${GAR_IMAGE_V1}

          # v2 content (overwrite index and build again)
          echo '<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>' > src/main/resources/static/index.html
          ./gradlew clean build --no-daemon
          docker build -t ${GAR_IMAGE_V2} .
          docker push ${GAR_IMAGE_V2}
        '''
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

            # Obtain cluster endpoint & CA safely
            CLUSTER_ENDPOINT=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(endpoint)")
            CLUSTER_CA=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(masterAuth.clusterCaCertificate)")
            TOKEN=$(gcloud auth print-access-token)

            mkdir -p $(dirname ${KUBECONFIG})
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

            kubectl cluster-info --kubeconfig=${KUBECONFIG}
          '''
        }
      }
    }

    stage('Decide Action (first-run detection)') {
      steps {
        script {
          // Check for existing deployment (non-empty output means present)
          def out = sh(script: "kubectl get deploy java-gradle-app -n java-app --kubeconfig=${KUBECONFIG} --ignore-not-found=true --no-headers -o name || true", returnStdout: true).trim()
          boolean deployedBefore = out != ""
          if (!deployedBefore) {
            echo "No existing deployment detected -> FIRST RUN. Forcing ROLLOUT of v1.0"
            env.EFFECTIVE_ACTION = 'ROLLOUT'
            env.EFFECTIVE_VERSION = 'v1.0'
          } else {
            echo "Existing deployment detected -> respecting pipeline parameters"
            env.EFFECTIVE_ACTION = params.DEPLOYMENT_ACTION
            env.EFFECTIVE_VERSION = params.VERSION
          }
          echo "EFFECTIVE_ACTION=${env.EFFECTIVE_ACTION}"
          echo "EFFECTIVE_VERSION=${env.EFFECTIVE_VERSION}"
        }
      }
    }

    stage('Apply Configs & Perform Action') {
      steps {
        script {
          // Put values we'll interpolate into shell into Groovy locals first
          def imageTag = (env.EFFECTIVE_VERSION == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          def cidr = env.ALLOWED_IP_CIDR
          def kubeconfig = env.KUBECONFIG

          sh """
            export PATH="${WORKSPACE}/bin:${PATH}"
            export KUBECONFIG=${kubeconfig}
            set -e

            # ensure namespace exists, apply configmap/hpa/other static yamls from repo
            kubectl create namespace java-app --dry-run=client -o yaml | kubectl apply -f -

            # Apply static yamls from repo (configmap, hpa, svc, ingress skeleton)
            kubectl apply -f k8s-Usecase/configmap.yaml -n java-app --validate=false || true
            kubectl apply -f k8s-Usecase/hpa.yaml -n java-app --validate=false || true
            kubectl apply -f k8s-Usecase/service.yaml -n java-app --validate=false || true
            kubectl apply -f k8s-Usecase/ingress.yaml -n java-app --validate=false || true

            if [ "${EFFECTIVE_ACTION}" = "ROLLOUT" ]; then
              echo "Rolling out ${EFFECTIVE_VERSION} with image ${imageTag}"

              # copy deployment template and replace placeholders with concrete values
              cp k8s-Usecase/deployment.yaml /tmp/deployment-${EFFECTIVE_VERSION}.yaml
              sed -i "s|IMAGE_PLACEHOLDER|${imageTag}|g" /tmp/deployment-${EFFECTIVE_VERSION}.yaml
              sed -i "s|VERSION_PLACEHOLDER|${EFFECTIVE_VERSION}|g" /tmp/deployment-${EFFECTIVE_VERSION}.yaml

              kubectl apply -f /tmp/deployment-${EFFECTIVE_VERSION}.yaml -n java-app --validate=false

              # Patch ingress to restrict to allowed IP/CIDR
              # We interpolate the CIDR from the Groovy variable 'cidr' above to avoid Groovy parser issues
              kubectl patch ingress java-app-ingress -n java-app --type='merge' -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/whitelist-source-range":"'"${cidr}"'"}}}' \
                || echo "Ingress patch failed (maybe ingress not present or controller differs) - please adjust ALLOWED_IP_CIDR annotation for your ingress controller."

              # Wait for rollout
              if kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s; then
                echo "Rollout succeeded"
              else
                echo "Rollout failed or timed out - dumping debug info"
                kubectl describe deployment java-gradle-app -n java-app || true
                kubectl get pods -n java-app -o wide || true
                for P in $(kubectl get pods -n java-app -l app=java-gradle-app -o name 2>/dev/null || echo ""); do
                  echo "=== Logs for ${P} ==="
                  kubectl logs -n java-app ${P} --tail=100 || true
                done
                kubectl get events -n java-app --sort-by=.lastTimestamp | tail -n 40 || true
                exit 1
              fi

            else
              echo "Executing rollback (kubectl rollout undo)"
              kubectl rollout undo deployment/java-gradle-app -n java-app || { echo "Rollback failed"; exit 1; }
              kubectl rollout status deployment/java-gradle-app -n java-app --timeout=300s || { echo "Rollback status wait failed"; exit 1; }
            fi
          """
        }
      }
    }

    stage('Verify Deployment & Homepage') {
      steps {
        sh '''
          export PATH="${WORKSPACE}/bin:${PATH}"
          export KUBECONFIG=${KUBECONFIG}

          echo "=== DEPLOYMENT ==="
          kubectl get deployment java-gradle-app -n java-app -o wide || true
          kubectl get pods -l app=java-gradle-app -n java-app -o wide || true

          echo "=== SERVICE & INGRESS ==="
          kubectl get svc -n java-app || true
          kubectl get ingress java-app-ingress -n java-app -o yaml || true

          IP=$(kubectl get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
          if [ -z "$IP" ]; then
            echo "Ingress IP not available yet (pending)."
          else
            echo "Ingress IP: $IP"
            # Try to fetch homepage (will only work from allowed IPs; if agent isn't allowed this may time out)
            echo "Testing homepage (from agent):"
            if curl -s --connect-timeout 5 http://$IP/ | head -n 20; then
              echo "Homepage fetched successfully."
            else
              echo "Could not fetch homepage from build agent - maybe agent IP isn't in ALLOWED_IP_CIDR. Check your ALLOWED_IP_CIDR setting or test from allowed client."
            fi
          fi
        '''
      }
    }
  }

  post {
    always {
      script {
        def currentResult = currentBuild.result ?: 'SUCCESS'
        echo "=== PIPELINE SUMMARY ==="
        echo "Requested action: ${params.DEPLOYMENT_ACTION}"
        echo "Selected version: ${params.VERSION}"
        echo "Effective action: ${env.EFFECTIVE_ACTION}"
        echo "Effective version: ${env.EFFECTIVE_VERSION}"
        echo "Build number: ${env.BUILD_NUMBER}"
        echo "Status: ${currentResult}"
      }
      sh '''
        rm -f /tmp/deployment-v1.0.yaml /tmp/deployment-v2.0.yaml 2>/dev/null || true
      '''
    }
    success {
      echo "Pipeline completed successfully."
    }
    failure {
      echo "Pipeline failed. Check logs above for details."
    }
  }
}
