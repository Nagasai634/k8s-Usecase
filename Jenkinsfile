pipeline {
  agent any

  parameters {
    choice(name: 'DEPLOYMENT_ACTION',
           choices: ['ROLLOUT', 'ROLLBACK'],
           description: 'Choose deployment action (ignored on first run; first run auto-deploys v1.0)')
    choice(name: 'VERSION',
           choices: ['v1.0', 'v2.0'],
           description: 'Choose version to deploy (ignored on first run)')
    string(name: 'ALLOWED_IP_CIDR',
           defaultValue: 'YOUR_IP/32',
           description: 'CIDR to whitelist on the ingress (change per-run; e.g. 203.0.113.5/32)')
  }

  environment {
    PROJECT_ID = 'planar-door-476510-m1'
    REGION = 'us-central1'
    CLUSTER_NAME = 'autopilot-demo'
    GAR_REPO = 'java-app'
    IMAGE_NAME = 'java-app'

    WORKSPACE_BIN = "${env.WORKSPACE}/bin"
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    V1_TAG = "v1.0-${env.BUILD_NUMBER}"
    V2_TAG = "v2.0-${env.BUILD_NUMBER}"
    GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V1_TAG}"
    GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V2_TAG}"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"

    DEFAULT_DESIRED_REPLICAS = "3"
    SAFE_REPLICAS = "1"
    SAFE_REQUEST_CPU = "100m"
    SAFE_LIMIT_CPU = "500m"
    SAFE_REQUEST_MEM = "256Mi"
    SAFE_LIMIT_MEM = "512Mi"
  }

  stages {
    stage('Prepare tools') {
      steps {
        sh '''
          set -e
          mkdir -p "${WORKSPACE_BIN}"
          if [ ! -x "${WORKSPACE_BIN}/kubectl" ]; then
            KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
            curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o "${WORKSPACE_BIN}/kubectl"
            chmod +x "${WORKSPACE_BIN}/kubectl"
          fi
          echo "kubectl (client):"
          "${WORKSPACE_BIN}/kubectl" version --client || true
          if command -v docker >/dev/null 2>&1; then docker --version || true; else echo "WARNING: docker not found on agent"; fi
          gcloud --version || true
        '''
      }
    }

    stage('Build & push both images to GAR') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}
            gcloud auth configure-docker ${GAR_HOST} --quiet || true

            cd k8s-Usecase/java-gradle

            mkdir -p src/main/resources/static
            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>
EOF
            ./gradlew clean build --no-daemon
            docker build -t ${GAR_IMAGE_V1} .
            for i in 1 2 3; do docker push ${GAR_IMAGE_V1} && break || { echo "push v1 attempt $i failed"; sleep 5; }; done

            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>
EOF
            ./gradlew clean build --no-daemon
            docker build -t ${GAR_IMAGE_V2} .
            for i in 1 2 3; do docker push ${GAR_IMAGE_V2} && break || { echo "push v2 attempt $i failed"; sleep 5; }; done
          '''
        }
      }
    }

    stage('Authenticate to GKE & write kubeconfig') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}
            gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} --quiet

            mkdir -p $(dirname ${KUBECONFIG})
            kubectl config view --raw > ${KUBECONFIG}
            echo "Wrote kubeconfig to ${KUBECONFIG}"
            "${WORKSPACE_BIN}/kubectl" --kubeconfig=${KUBECONFIG} cluster-info || true
          '''
        }
      }
    }

    stage('Decide effective action (detect first run)') {
      steps {
        script {
          def exists = sh(script: "'${env.WORKSPACE}/bin/kubectl' --kubeconfig=${env.KUBECONFIG} -n java-app get deploy java-gradle-app --ignore-not-found=true --no-headers -o name || true", returnStdout: true).trim()
          boolean deployedBefore = exists != ''
          if (!deployedBefore) {
            env.EFFECTIVE_ACTION = 'ROLLOUT'
            env.EFFECTIVE_VERSION = 'v1.0'
            echo "FIRST RUN -> forcing ROLLOUT of v1.0"
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

    stage('Check CPU quota and set safe mode') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}

            DESIRED=${DEFAULT_DESIRED_REPLICAS}
            REQ_PER_POD_M=250
            REQ_TOTAL_M=$((DESIRED * REQ_PER_POD_M))

            QLINE=$(gcloud compute regions describe ${REGION} --project=${PROJECT_ID} --format="value(quotas[?metric=='CPUS'].limit,quotas[?metric=='CPUS'].usage)" || echo "")
            if [ -z "$QLINE" ]; then
              echo "Could not read CPUS quota -> SAFE mode"
              echo "USE_SAFE=1" > /tmp/decide_mode
            else
              LIMIT=$(echo $QLINE | awk '{print $1}')
              USAGE=$(echo $QLINE | awk '{print $2}')
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

    stage('Apply base manifests (namespace, svc, ingress, configmap, hpa)') {
      steps {
        sh '''
          set -e
          export KUBECONFIG=${KUBECONFIG}
          KUBECTL="${WORKSPACE_BIN}/kubectl"

          ${KUBECTL} create namespace java-app --dry-run=client -o yaml | ${KUBECTL} apply -f -
          ${KUBECTL} apply -f k8s-Usecase/configmap.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f k8s-Usecase/service.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f k8s-Usecase/ingress.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f k8s-Usecase/hpa.yaml -n java-app --validate=false || true
        '''
      }
    }

    stage('Perform action (rollout / rollback)') {
      steps {
        script {
          def kubeconf = env.KUBECONFIG
          def KUBECTL = "${env.WORKSPACE}/bin/kubectl"
          def cidr = params.ALLOWED_IP_CIDR ?: env.ALLOWED_IP_CIDR
          def imageToUse = (env.EFFECTIVE_VERSION == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2

          def safeFlag = sh(script: "cat /tmp/decide_mode 2>/dev/null || echo 'USE_SAFE=1';
