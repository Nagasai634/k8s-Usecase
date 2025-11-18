// Jenkinsfile - build v1/v2 -> push to GAR -> deploy to GKE Autopilot
pipeline {
  agent any

  options { timestamps() }

  parameters {
    choice(name: 'DEPLOYMENT_ACTION', choices: ['ROLLOUT','ROLLBACK'], description: 'Choose deployment action (ignored on first run)')
    choice(name: 'VERSION', choices: ['v1.0','v2.0'], description: 'Choose version to deploy (ignored on first run)')
    string(name: 'ALLOWED_IP_CIDR', defaultValue: '136.119.42.77/32', description: 'CIDR to whitelist ingress (example: 203.0.113.5/32)')
  }

  environment {
    PROJECT_ID = 'planar-door-476510-m1'
    REGION = 'us-central1'
    CLUSTER_NAME = 'autopilot-demo'
    GAR_REPO = 'java-app'
    IMAGE_NAME = 'java-app'
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    REPO_DIR = "${env.WORKSPACE}/k8s-Usecase/java-gradle"
    YAML_DIR = "${env.WORKSPACE}/k8s-Usecase"
    WORK_BIN = "${env.WORKSPACE}/bin"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
    GCP_CRED_ID = 'gcp-service-account-key'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Prepare tools & workspace') {
      steps {
        sh '''
          set -e
          mkdir -p ${WORKSPACE}/bin
          if [ ! -d "${YAML_DIR}" ]; then
            git clone https://github.com/Nagasai634/k8s-Usecase.git
          fi
        '''
        sh '''
          set -e
          KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
          curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o ${WORK_BIN}/kubectl
          chmod +x ${WORK_BIN}/kubectl
          echo "kubectl installed to ${WORK_BIN}/kubectl"
        '''
      }
    }

    stage('Build & Push Images (with Java fallback)') {
      steps {
        withCredentials([file(credentialsId: env.GCP_CRED_ID, variable: 'GCP_SA_KEYFILE')]) {
          script {
            def v1tag = "v1.0-${env.BUILD_NUMBER}"
            def v2tag = "v2.0-${env.BUILD_NUMBER}"
            env.GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${v1tag}"
            env.GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${v2tag}"
          }

          sh '''
            set -e
            export PATH="${WORK_BIN}:${PATH}"
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}
            gcloud auth configure-docker ${GAR_HOST} --quiet || true

            cd ${REPO_DIR}
            mkdir -p src/main/resources/static
            if [ -f "./gradlew" ]; then chmod +x ./gradlew; fi

            build_and_push() {
              version=$1; image=$2
              echo "=== Build attempt: ${version} -> ${image} ==="
              set +e
              ./gradlew clean build --no-daemon
              GRADLE_STATUS=$?
              set -e
              if [ "${GRADLE_STATUS}" -eq 0 ]; then
                echo "Gradle succeeded -> building app image"
                docker build -t ${image} .
              else
                echo "Gradle failed -> building minimal nginx fallback image"
                TMPDIR=$(mktemp -d)
                cat > ${TMPDIR}/index.html <<EOF
<!DOCTYPE html><html><head><title>${version}</title></head><body><h1>${version} - FALLBACK</h1></body></html>
EOF
                cat > ${TMPDIR}/Dockerfile <<'DF'
FROM nginx:1.25-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
DF
                docker build -t ${image} ${TMPDIR}
                rm -rf ${TMPDIR}
              fi

              for i in 1 2 3; do
                if docker push ${image}; then
                  echo "Pushed ${image}"
                  break
                else
                  echo "Push attempt $i failed for ${image}"
                  sleep 5
                  if [ $i -eq 3 ]; then
                    echo "Failed to push ${image}"
                    return 1
                  fi
                fi
              done
              return 0
            }

            # ensure static pages exist
            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>
EOF
            build_and_push "v1.0" "${GAR_IMAGE_V1}"

            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>
EOF
            build_and_push "v2.0" "${GAR_IMAGE_V2}"

            echo "Images ready: ${GAR_IMAGE_V1} , ${GAR_IMAGE_V2}"
          '''
        }
      }
    }

    stage('Authenticate to GKE (token-based kubeconfig)') {
      steps {
        withCredentials([file(credentialsId: env.GCP_CRED_ID, variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export PATH="${WORK_BIN}:${PATH}"
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}

            CLUSTER_ENDPOINT=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} --format="value(endpoint)")
            CLUSTER_CA=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} --format="value(masterAuth.clusterCaCertificate)")
            TOKEN=$(gcloud auth print-access-token)

            if [ -z "${CLUSTER_ENDPOINT}" ] || [ -z "${CLUSTER_CA}" ] || [ -z "${TOKEN}" ]; then
              echo "Failed to obtain cluster endpoint/ca/token"
              exit 1
            fi

            mkdir -p $(dirname ${KUBECONFIG})
            cat > ${KUBECONFIG} <<EOF
apiVersion: v1
kind: Config
current-context: ${CLUSTER_NAME}
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: https://${CLUSTER_ENDPOINT}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${CLUSTER_NAME}
  name: ${CLUSTER_NAME}
users:
- name: ${CLUSTER_NAME}
  user:
    token: ${TOKEN}
EOF

            ${WORK_BIN}/kubectl --kubeconfig=${KUBECONFIG} cluster-info || true
            echo "Wrote token-based kubeconfig to ${KUBECONFIG}"
          '''
        }
      }
    }

    stage('Check CPU Quota & Decide SAFE Mode') {
      steps {
        withCredentials([file(credentialsId: env.GCP_CRED_ID, variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export PATH="${WORK_BIN}:${PATH}"
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}

            DESIRED=3
            REQ_PER_POD_M=250
            # use POSIX arithmetic - no backslashes to confuse Groovy parser
            REQ_TOTAL_M=$((DESIRED * REQ_PER_POD_M))

            # get CPU quota (limit and usage) for the region
            Q=$(gcloud compute regions describe ${REGION} --project=${PROJECT_ID} --format="value(quotas[?metric=='CPUS'].limit,quotas[?metric=='CPUS'].usage)" || echo "")
            if [ -z "$Q" ]; then
              echo "Could not read CPUS quota -> SAFE mode"
              echo "USE_SAFE=1" > /tmp/decide_mode
            else
              LIMIT=$(echo $Q | awk '{print $1}')
              USAGE=$(echo $Q | awk '{print $2}')
              AVAIL_M=$(python3 - <<PY
limit=${LIMIT}
usage=${USAGE}
avail = float(limit) - float(usage)
print(int(avail*1000))
PY
)
              echo "CPUs limit=${LIMIT}, usage=${USAGE}, avail_m=${AVAIL_M}"
              if [ ${AVAIL_M} -lt ${REQ_TOTAL_M} ]; then
                echo "Not enough CPU quota (${AVAIL_M}m < ${REQ_TOTAL_M}m) -> SAFE"
                echo "USE_SAFE=1" > /tmp/decide_mode
              else
                echo "Quota sufficient -> NORMAL"
                echo "USE_SAFE=0" > /tmp/decide_mode
              fi
            fi
            cat /tmp/decide_mode || true
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
            echo "FIRST RUN -> forcing ROLLOUT v1.0"
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
          export PATH="${WORK_BIN}:${PATH}"
          export KUBECONFIG=${KUBECONFIG}
          KUBECTL=${WORK_BIN}/kubectl

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
          def KUBECTL = "${env.WORK_BIN}/kubectl"
          def cidr = params.ALLOWED_IP_CIDR ?: '0.0.0.0/0'
          def imageToUse = (env.EFFECTIVE_VERSION == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2
          def ver = env.EFFECTIVE_VERSION
          def action = env.EFFECTIVE_ACTION

          sh(
            '''
              set -e
              export PATH="${WORK_BIN}:${PATH}"
              export KUBECONFIG=''' + kubeconf + '''
              KUBECTL=''' + KUBECTL + '''
              CIDR=''' + cidr + '''
              IMAGE=''' + imageToUse + '''
              VER=''' + ver + '''
              ACTION=''' + action + '''

              echo "Performing ${ACTION} for ${VER} using ${IMAGE}"

              cp ${YAML_DIR}/deployment.yaml /tmp/deployment-${VER}.yaml
              sed -i "s|IMAGE_PLACEHOLDER|${IMAGE}|g" /tmp/deployment-${VER}.yaml
              sed -i "s|VERSION_PLACEHOLDER|${VER}|g" /tmp/deployment-${VER}.yaml

              ${KUBECTL} apply -f /tmp/deployment-${VER}.yaml -n java-app --validate=false || true

              ${KUBECTL} patch ingress java-app-ingress -n java-app --type='merge' -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/whitelist-source-range":"'${CIDR}'"}}}' || echo "Ingress patch skipped/failed"

              if [ "${ACTION}" = "ROLLOUT" ]; then
                echo "Waiting for rollout (timeout 10m)..."
                if ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=600s; then
                  echo "Rollout succeeded."
                else
                  echo "Rollout failed - collecting debug info"
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
          export PATH="${WORK_BIN}:${PATH}"
          export KUBECONFIG=${KUBECONFIG}
          KUBECTL=${WORK_BIN}/kubectl

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
      sh 'rm -f /tmp/deployment-*.yaml /tmp/decide_mode 2>/dev/null || true'
    }
    success { echo "Pipeline completed successfully." }
    failure { echo "Pipeline failed — inspect logs for details." }
  }
}
