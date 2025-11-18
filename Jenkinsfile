pipeline {
  agent any

  parameters {
    choice(name: 'DEPLOYMENT_ACTION',
           choices: ['ROLLOUT', 'ROLLBACK'],
           description: 'Choose deployment action (ignored on first run; first run auto-deploys v1.0)')
    choice(name: 'VERSION',
           choices: ['v1.0', 'v2.0'],
           description: 'Choose version to deploy (ignored on first run)')
  }

  environment {
    PROJECT_ID = 'planar-door-476510-m1'          // <-- adjust
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
    // Replace with the CIDR you want to allow (or store in Jenkins credential)
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
          chmod +x ./gradlew || true
        '''
      }
    }

    stage('Setup Tools') {
      steps {
        sh '''
          set -e
          mkdir -p "${WORKSPACE}/bin"
          # download kubectl if not present or version mismatch
          if [ ! -x "${WORKSPACE}/bin/kubectl" ]; then
            KVER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
            curl -L --fail "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o "${WORKSPACE}/bin/kubectl"
            chmod +x "${WORKSPACE}/bin/kubectl"
          fi
          # sanity
          "${WORKSPACE}/bin/kubectl" version --client || true
        '''
      }
    }

    stage('Build & Push Images (both versions)') {
      steps {
        sh '''
          set -e
          cd k8s-Usecase/java-gradle
          mkdir -p src/main/resources/static

          # v1
          cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>
EOF
          ./gradlew clean build --no-daemon
          docker build -t ${GAR_IMAGE_V1} .
          docker push ${GAR_IMAGE_V1}

          # v2
          cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>
EOF
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
            set -e
            export KUBECONFIG=${KUBECONFIG}

            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}

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

            # quick validation using explicit kubectl path
            "${WORKSPACE}/bin/kubectl" cluster-info --kubeconfig=${KUBECONFIG}
          '''
        }
      }
    }

    stage('Decide Action (first-run detection)') {
      steps {
        script {
          // Use explicit kubectl path to avoid PATH problems
          def exists = sh(script: "\"${env.WORKSPACE}/bin/kubectl\" get deploy java-gradle-app -n java-app --kubeconfig=${env.KUBECONFIG} --ignore-not-found=true --no-headers -o name || true", returnStdout: true).trim()
          boolean deployedBefore = exists != ''
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
          // precompute image and cidr in Groovy (safe interpolation here)
          def imageToUse = (env.EFFECTIVE_VERSION == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          def cidr = env.ALLOWED_IP_CIDR
          def kubeconf = env.KUBECONFIG
          def KUBECTL = "${env.WORKSPACE}/bin/kubectl"

          // Apply namespace & static resources
          sh """
            set -e
            export KUBECONFIG=${kubeconf}
            ${KUBECTL} create namespace java-app --dry-run=client -o yaml | ${KUBECTL} apply -f -
            ${KUBECTL} apply -f k8s-Usecase/configmap.yaml -n java-app --validate=false || true
            ${KUBECTL} apply -f k8s-Usecase/hpa.yaml -n java-app --validate=false || true
            ${KUBECTL} apply -f k8s-Usecase/service.yaml -n java-app --validate=false || true
            ${KUBECTL} apply -f k8s-Usecase/ingress.yaml -n java-app --validate=false || true
          """

          if (env.EFFECTIVE_ACTION == 'ROLLOUT') {
            // prepare and apply deployment
            sh """
              set -e
              cp k8s-Usecase/deployment.yaml /tmp/deployment-${env.EFFECTIVE_VERSION}.yaml
              sed -i "s|IMAGE_PLACEHOLDER|${imageToUse}|g" /tmp/deployment-${env.EFFECTIVE_VERSION}.yaml
              sed -i "s|VERSION_PLACEHOLDER|${env.EFFECTIVE_VERSION}|g" /tmp/deployment-${env.EFFECTIVE_VERSION}.yaml
              ${KUBECTL} apply -f /tmp/deployment-${env.EFFECTIVE_VERSION}.yaml -n java-app --validate=false
            """

            // build patch command in Groovy to avoid Groovy parser problems and then execute it
            def patchCmd = "${KUBECTL} patch ingress java-app-ingress -n java-app --type='merge' -p '{\"metadata\":{\"annotations\":{\"nginx.ingress.kubernetes.io/whitelist-source-range\":\"${cidr}\"}}}' || echo \"Ingress patch failed (maybe ingress not present or controller differs) - please adjust ALLOWED_IP_CIDR annotation for your ingress controller.\""
            sh patchCmd

            // wait for rollout (debug on failure)
            sh """
              set -e
              if ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=600s; then
                echo "Rollout succeeded"
              else
                echo "Rollout timed out/failed - dumping debug info"
                ${KUBECTL} describe deployment java-gradle-app -n java-app || true
                ${KUBECTL} get pods -n java-app -o wide || true
                for P in \$(${KUBECTL} get pods -n java-app -l app=java-gradle-app -o name 2>/dev/null || echo ""); do
                  echo "=== Logs for \${P} ==="
                  ${KUBECTL} logs -n java-app \${P} --tail=100 || true
                done
                ${KUBECTL} get events -n java-app --sort-by=.lastTimestamp | tail -n 40 || true
                exit 1
              fi
            """
          } else {
            // rollback path
            sh """
              set -e
              ${KUBECTL} rollout undo deployment/java-gradle-app -n java-app || { echo "Rollback failed"; exit 1; }
              ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=300s || { echo "Rollback status wait failed"; exit 1; }
            """
          }
        }
      }
    }

    stage('Verify Deployment & Homepage') {
      steps {
        sh '''
          set -e
          KUBECTL="${WORKSPACE}/bin/kubectl"
          export KUBECONFIG=${KUBECONFIG}

          echo "=== DEPLOYMENT ==="
          ${KUBECTL} get deployment java-gradle-app -n java-app -o wide || true
          ${KUBECTL} get pods -l app=java-gradle-app -n java-app -o wide || true

          echo "=== SERVICE & INGRESS ==="
          ${KUBECTL} get svc -n java-app || true
          ${KUBECTL} get ingress java-app-ingress -n java-app -o yaml || true

          IP=$(${KUBECTL} get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
          if [ -z "$IP" ]; then
            echo "Ingress IP not available yet (pending)."
          else
            echo "Ingress IP: $IP"
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
      sh 'rm -f /tmp/deployment-v1.0.yaml /tmp/deployment-v2.0.yaml 2>/dev/null || true'
    }
    success { echo "Pipeline completed successfully." }
    failure { echo "Pipeline failed. Check logs above for details." }
  }
}
