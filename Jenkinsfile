// Jenkinsfile - GAR build + GKE Autopilot deploy (first-run autoset to v1.0)
pipeline {
  agent any

  parameters {
    choice(name: 'DEPLOYMENT_ACTION', choices: ['ROLLOUT', 'ROLLBACK'], description: 'Choose deployment action (ignored on first run)')
    choice(name: 'VERSION', choices: ['v1.0', 'v2.0'], description: 'Choose version to deploy (ignored on first run)')
    string(name: 'ALLOWED_IP_CIDR', defaultValue: '203.0.113.5/32', description: 'CIDR to whitelist the ingress (e.g. your client IP/32)')
  }

  environment {
    // Update these to suit your project
    PROJECT_ID = 'planar-door-476510-m1'
    REGION = 'us-central1'
    CLUSTER_NAME = 'autopilot-demo'
    GAR_REPO = 'java-app'
    IMAGE_NAME = 'java-app'
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
    REPO_DIR = "${env.WORKSPACE}/k8s-Usecase/java-gradle"
    YAML_DIR = "${env.WORKSPACE}/k8s-Usecase"
    GCP_CRED_ID = 'gcp-service-account-key' // ensure this credential exists in Jenkins
    WORK_BIN = "${env.WORKSPACE}/bin"
  }

  stages {
    stage('Prepare workspace & tools') {
      steps {
        cleanWs()
        sh '''
          set -e
          mkdir -p ${WORKSPACE}/bin
          # clone repo if not already present
          if [ ! -d "k8s-Usecase" ]; then
            git clone https://github.com/Nagasai634/k8s-Usecase.git
          fi
        '''
        // Install kubectl into workspace/bin for deterministic usage
        sh '''
          set -e
          mkdir -p ${WORKSPACE}/bin
          KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
          curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o ${WORKSPACE}/bin/kubectl
          chmod +x ${WORKSPACE}/bin/kubectl
          echo "kubectl installed to ${WORKSPACE}/bin/kubectl"
        '''
      }
    }

    stage('Build & Push Images (v1.0, v2.0)') {
      steps {
        withCredentials([file(credentialsId: env.GCP_CRED_ID, variable: 'GCP_SA_KEYFILE')]) {
          script {
            // compute tags here to include BUILD_NUMBER safely
            def v1tag = "v1.0-${env.BUILD_NUMBER}"
            def v2tag = "v2.0-${env.BUILD_NUMBER}"
            env.GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${v1tag}"
            env.GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${v2tag}"
          }

          // build & push both images (parallelizing builds might be added later)
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}
            gcloud auth configure-docker ${GAR_HOST} --quiet || true

            cd ${REPO_DIR}
            mkdir -p src/main/resources/static

            # build v1
            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>
EOF
            ./gradlew clean build --no-daemon
            docker build -t ${GAR_IMAGE_V1} .
            docker push ${GAR_IMAGE_V1}

            # build v2
            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>
EOF
            ./gradlew clean build --no-daemon
            docker build -t ${GAR_IMAGE_V2} .
            docker push ${GAR_IMAGE_V2}
          '''
        }
      }
    }

    stage('Authenticate to GKE / write kubeconfig') {
      steps {
        withCredentials([file(credentialsId: env.GCP_CRED_ID, variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}

            # Use gcloud to populate kubeconfig (works for Autopilot)
            gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} --quiet

            mkdir -p $(dirname ${KUBECONFIG})
            kubectl config view --raw > ${KUBECONFIG}
            echo "Wrote kubeconfig to: ${KUBECONFIG}"
            ${WORK_BIN}/kubectl --kubeconfig=${KUBECONFIG} cluster-info || true
          '''
        }
      }
    }

    stage('Decide Action: first-run detection') {
      steps {
        script {
          // If deployment doesn't exist, force rollout of v1.0
          def exists = sh(script: "${WORK_BIN}/kubectl --kubeconfig=${KUBECONFIG} get deploy java-gradle-app -n java-app --ignore-not-found=true --no-headers -o name || true", returnStdout: true).trim()
          if (exists == '') {
            env.EFFECTIVE_ACTION = 'ROLLOUT'
            env.EFFECTIVE_VERSION = 'v1.0'
            echo "FIRST RUN detected -> forcing ROLLOUT of v1.0"
          } else {
            env.EFFECTIVE_ACTION = params.DEPLOYMENT_ACTION
            env.EFFECTIVE_VERSION = params.VERSION
            echo "Using requested parameters"
          }
          echo "EFFECTIVE_ACTION=${env.EFFECTIVE_ACTION}"
          echo "EFFECTIVE_VERSION=${env.EFFECTIVE_VERSION}"
        }
      }
    }

    stage('Apply base manifests (namespace, config, service, ingress, hpa)') {
      steps {
        sh '''
          set -e
          export KUBECONFIG=${KUBECONFIG}
          KUBECTL=${WORKSPACE}/bin/kubectl

          ${KUBECTL} create namespace java-app --dry-run=client -o yaml | ${KUBECTL} apply -f -
          ${KUBECTL} apply -f ${YAML_DIR}/configmap.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f ${YAML_DIR}/service.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f ${YAML_DIR}/ingress.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f ${YAML_DIR}/hpa.yaml -n java-app --validate=false || true
        '''
      }
    }

    stage('Perform Action: Rollout / Rollback') {
      steps {
        script {
          // pick image per effective version
          def imageToUse = (env.EFFECTIVE_VERSION == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          def kubeconf = env.KUBECONFIG
          def KUBECTL = "${env.WORKSPACE}/bin/kubectl"
          def cidr = params.ALLOWED_IP_CIDR ?: '0.0.0.0/0'

          // Use triple-single-quoted sh and concatenate Groovy vars into it so shell ${...} remain shell-owned.
          sh(
            '''
              set -e
              export KUBECONFIG=''' + kubeconf + '''
              KUBECTL=''' + KUBECTL + '''
              CIDR=''' + cidr + '''
              IMAGE=''' + imageToUse + '''
              VER=''' + env.EFFECTIVE_VERSION + '''

              echo "Action: ''' + env.EFFECTIVE_ACTION + '''"
              echo "Version: ${VER}"
              echo "Image: ${IMAGE}"
              echo "Applying deployment manifest for ${VER}..."

              cp ${YAML_DIR}/deployment.yaml /tmp/deployment-${VER}.yaml
              sed -i "s|IMAGE_PLACEHOLDER|${IMAGE}|g" /tmp/deployment-${VER}.yaml
              sed -i "s|VERSION_PLACEHOLDER|${VER}|g" /tmp/deployment-${VER}.yaml

              kubectl apply -f /tmp/deployment-${VER}.yaml -n java-app --validate=false || true

              # patch ingress to whitelist CIDR (annotation used by nginx ingress; update if your ingress controller differs)
              kubectl patch ingress java-app-ingress -n java-app --type='merge' -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/whitelist-source-range":"'${CIDR}'"}}}' || echo "Ingress patch skipped/failed"

              if [ "''' + env.EFFECTIVE_ACTION + '''" = "ROLLOUT" ]; then
                echo " Waiting for rollout (timeout 10m)..."
                if ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=600s; then
                  echo " Rollout succeeded"
                else
                  echo " Rollout timed out/failed - collecting debug info"
                  ${KUBECTL} describe deployment java-gradle-app -n java-app || true
                  ${KUBECTL} get pods -n java-app -o wide || true
                  for P in $(${KUBECTL} get pods -l app=java-gradle-app -n java-app -o name 2>/dev/null || echo ""); do
                    echo "=== LOGS for ${P} ==="
                    ${KUBECTL} logs -n java-app ${P} --tail=200 || true
                  done
                  ${KUBECTL} get events -n java-app --sort-by=.lastTimestamp | tail -n 80 || true
                  exit 1
                fi
              else
                echo "ROLLBACK requested -> performing rollout undo"
                ${KUBECTL} rollout undo deployment/java-gradle-app -n java-app || { echo "rollback failed"; exit 1; }
                ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=300s || { echo "rollback wait failed"; exit 1; }
              fi
            '''
          )
        }
      }
    }

    stage('Verify & Test homepage') {
      steps {
        sh '''
          set -e
          export KUBECONFIG=${KUBECONFIG}
          KUBECTL=${WORKSPACE}/bin/kubectl

          echo "=== DEPLOYMENT & PODS ==="
          ${KUBECTL} get deployment java-gradle-app -n java-app -o wide || true
          ${KUBECTL} get pods -l app=java-gradle-app -n java-app -o wide || true

          echo "=== SERVICE & INGRESS ==="
          ${KUBECTL} get svc -n java-app || true
          ${KUBECTL} get ingress java-app-ingress -n java-app -o yaml || true

          IP=$(${KUBECTL} get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
          if [ -z "$IP" ]; then
            echo "Ingress IP not available yet."
          else
            echo "Ingress IP: $IP"
            # Test homepage once IP is available
            if curl -s --connect-timeout 5 http://$IP/ | head -n 5; then
              echo "Homepage returned content."
              curl -s http://$IP/ | head -n 20
            else
              echo "Could not fetch homepage from agent. Ensure agent IP is allowed by ALLOWED_IP_CIDR or test from allowed client."
            fi
          fi
        '''
      }
    }
  } // stages

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
    }
    success {
      echo "Pipeline completed successfully."
    }
    failure {
      echo "Pipeline failed - check logs for details (image push, quota, readiness, pod events)."
    }
  }
}
