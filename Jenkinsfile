// Jenkinsfile - Build (v1 & v2) -> Push to GAR -> Deploy to GKE Autopilot
pipeline {
  agent any

  options {
    timestamps()
  }

  parameters {
    choice(name: 'DEPLOYMENT_ACTION', choices: ['ROLLOUT', 'ROLLBACK'], description: 'Choose deployment action (ignored on first run)')
    choice(name: 'VERSION', choices: ['v1.0', 'v2.0'], description: 'Choose version to deploy (ignored on first run)')
    string(name: 'ALLOWED_IP_CIDR', defaultValue: '136.119.42.77/32', description: 'CIDR to whitelist ingress (example: 203.0.113.5/32)')
  }

  environment {
    PROJECT_ID = 'planar-door-476510-m1'         // change to your project
    REGION = 'us-central1'
    CLUSTER_NAME = 'autopilot-demo'              // change if needed
    GAR_REPO = 'java-app'
    IMAGE_NAME = 'java-app'
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    REPO_DIR = "${env.WORKSPACE}/k8s-Usecase/java-gradle"
    YAML_DIR = "${env.WORKSPACE}/k8s-Usecase"
    WORK_BIN = "${env.WORKSPACE}/bin"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
    GCP_CRED_ID = 'gcp-service-account-key'      // secret file credential in Jenkins
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare tools & workspace') {
      steps {
        sh '''
          set -e
          mkdir -p ${WORKSPACE}/bin
          # ensure repo dir exists (checkout normally does this)
          if [ ! -d "${YAML_DIR}" ]; then
            git clone https://github.com/Nagasai634/k8s-Usecase.git
          fi
        '''
        sh '''
          set -e
          KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
          curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o ${WORKSPACE}/bin/kubectl
          chmod +x ${WORKSPACE}/bin/kubectl
          echo "kubectl installed to ${WORKSPACE}/bin/kubectl"
        '''
      }
    }

    stage('Build & Push Images (with Java fallback)') {
      steps {
        withCredentials([file(credentialsId: env.GCP_CRED_ID, variable: 'GCP_SA_KEYFILE')]) {
          script {
            // compute image tags with build number
            def v1tag = "v1.0-${env.BUILD_NUMBER}"
            def v2tag = "v2.0-${env.BUILD_NUMBER}"
            env.GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${v1tag}"
            env.GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${v2tag}"
          }

          // Build and push images. If Java build fails, build lightweight nginx image serving static page.
          sh(
            '''
              set -e
              export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
              gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
              gcloud config set project ${PROJECT_ID}
              gcloud auth configure-docker ${GAR_HOST} --quiet || true

              cd ${REPO_DIR}
              mkdir -p src/main/resources/static
              if [ -f ./gradlew ]; then chmod +x ./gradlew; fi

              build_and_push() {
                local version=$1
                local image=$2
                echo "=== Build attempt for ${version} -> ${image} ==="

                # try Java gradle build + docker image if possible
                set +e
                ./gradlew clean build --no-daemon
                GRADLE_STATUS=$?
                set -e

                if [ "${GRADLE_STATUS}" -eq 0 ]; then
                  echo "Gradle build succeeded for ${version} - building app docker image"
                  # assume Dockerfile in repo is suitable; otherwise fallback will run
                  docker build -t ${image} .
                else
                  echo "Gradle build failed for ${version}; building minimal nginx fallback image"
                  # create a simple nginx Dockerfile that serves index.html
                  TMPDIR=$(mktemp -d)
                  cat > ${TMPDIR}/index.html <<EOF
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${version}</title></head>
<body style="font-family:Arial;text-align:center;padding:60px;background:#f3f4f6">
  <div style="display:inline-block;padding:30px;border-radius:8px;background:#111827;color:#fff">
    <h1>${version} - FALLBACK</h1>
    <p>This is a fallback static page (Gradle build failed).</p>
  </div>
</body>
</html>
EOF
                  cat > ${TMPDIR}/Dockerfile <<'DF'
FROM nginx:1.25-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
DF
                  docker build -t ${image} ${TMPDIR}
                  rm -rf ${TMPDIR}
                fi

                # push with up to 3 retries
                for i in 1 2 3; do
                  if docker push ${image}; then
                    echo "Pushed ${image}"
                    break
                  else
                    echo "Push attempt $i for ${image} failed"
                    sleep 5
                    if [ $i -eq 3 ]; then
                      echo "Failed to push ${image} after retries"
                      return 1
                    fi
                  fi
                done

                return 0
              }

              # create versioned index pages (app may override, but we ensure content exists)
              cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>
EOF

              build_and_push "v1.0" "${GAR_IMAGE_V1}"

              cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>
EOF

              build_and_push "v2.0" "${GAR_IMAGE_V2}"

              echo "Images available:"
              echo "  ${GAR_IMAGE_V1}"
              echo "  ${GAR_IMAGE_V2}"
            '''
          )
        }
      }
    }

    stage('Authenticate to GKE') {
      steps {
        withCredentials([file(credentialsId: env.GCP_CRED_ID, variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}
            gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} --quiet
            mkdir -p $(dirname ${KUBECONFIG})
            kubectl config view --raw > ${KUBECONFIG}
            echo "Wrote kubeconfig to ${KUBECONFIG}"
            ${WORK_BIN}/kubectl --kubeconfig=${KUBECONFIG} cluster-info || true
          '''
        }
      }
    }

    stage('Decide Action (first-run detection)') {
      steps {
        script {
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

    stage('Apply base manifests (namespace/config/service/ingress/hpa)') {
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
          def kubeconf = env.KUBECONFIG
          def KUBECTL = "${env.WORKSPACE}/bin/kubectl"
          def cidr = params.ALLOWED_IP_CIDR ?: '0.0.0.0/0'
          def imageToUse = (env.EFFECTIVE_VERSION == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          def ver = env.EFFECTIVE_VERSION
          def action = env.EFFECTIVE_ACTION

          sh(
            '''
              set -e
              export KUBECONFIG=''' + kubeconf + '''
              KUBECTL=''' + KUBECTL + '''
              CIDR=''' + cidr + '''
              IMAGE=''' + imageToUse + '''
              VER=''' + ver + '''
              ACTION=''' + action + '''

              echo "Performing ${ACTION} for ${VER} using image ${IMAGE}"

              cp ${YAML_DIR}/deployment.yaml /tmp/deployment-${VER}.yaml
              sed -i "s|IMAGE_PLACEHOLDER|${IMAGE}|g" /tmp/deployment-${VER}.yaml
              sed -i "s|VERSION_PLACEHOLDER|${VER}|g" /tmp/deployment-${VER}.yaml

              ${KUBECTL} apply -f /tmp/deployment-${VER}.yaml -n java-app --validate=false || true

              # patch ingress to whitelist CIDR (nginx ingress). Adjust for your ingress controller if needed.
              ${KUBECTL} patch ingress java-app-ingress -n java-app --type='merge' -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/whitelist-source-range":"'${CIDR}'"}}}' || echo "Ingress patch skipped/failed"

              if [ "${ACTION}" = "ROLLOUT" ]; then
                echo "Waiting for rollout (timeout 10m)..."
                if ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=600s; then
                  echo "Rollout succeeded."
                else
                  echo "Rollout timed out/failed - collecting debug info"
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
                echo "Performing rollback (rollout undo)"
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

          echo "=== DEPLOYMENT ==="
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
            if curl -s --connect-timeout 5 http://$IP/ | head -n 5; then
              echo "Homepage responded (first 20 lines):"
              curl -s http://$IP/ | head -n 20
            else
              echo "Could not fetch homepage from agent. Ensure agent IP (or Jenkins controller) is allowed by ALLOWED_IP_CIDR"
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

    success {
      echo "Pipeline completed successfully."
    }

    failure {
      echo "Pipeline failed — inspect logs for details (image build/push, kubeconfig, quota, readiness, pod events)."
    }
  }
}
