pipeline {
  agent any

  parameters {
    choice(name: 'DEPLOYMENT_ACTION', choices: ['ROLLOUT', 'ROLLBACK'], description: 'Choose deployment action (ignored on first build)')
    choice(name: 'VERSION', choices: ['v1.0', 'v2.0'], description: 'Version to deploy')
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
    REGION_FLAG = "us-central1"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"
    PATH = "${env.WORKSPACE}/bin:${env.PATH}"
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 60, unit: 'MINUTES')
  }

  stages {

    stage('Clean workspace') {
      steps {
        cleanWs()
        sh 'mkdir -p ${WORKSPACE}/bin ${WORKSPACE}/.kube'
      }
    }

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Install kubectl') {
      steps {
        sh '''
          set -e
          # download kubectl stable
          KUBECTL_BIN=${WORKSPACE}/bin/kubectl
          if [ ! -f "${KUBECTL_BIN}" ]; then
            curl -L -o /tmp/kubectl "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x /tmp/kubectl
            mv /tmp/kubectl ${KUBECTL_BIN}
          fi
          ${KUBECTL_BIN} version --client=true || true
        '''
      }
    }

    stage('Build & Push Images') {
      parallel {
        stage('Build v1.0') {
          steps {
            sh '''
              set -e
              cd k8s-Usecase/java-gradle
              mkdir -p src/main/resources/static
              cat > src/main/resources/static/index.html <<'HTML'
<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>
HTML
              ./gradlew clean build --no-daemon
              docker build -t ${GAR_IMAGE_V1} .
              docker push ${GAR_IMAGE_V1}
            '''
          }
        }

        stage('Build v2.0') {
          steps {
            sh '''
              set -e
              cd k8s-Usecase/java-gradle
              mkdir -p src/main/resources/static
              cat > src/main/resources/static/index.html <<'HTML'
<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>
HTML
              ./gradlew clean build --no-daemon
              docker build -t ${GAR_IMAGE_V2} .
              docker push ${GAR_IMAGE_V2}
            '''
          }
        }
      }
    }

    stage('Prepare GKE credentials') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            echo "Authenticating to GCP..."
            gcloud auth activate-service-account --key-file="$GCP_SA_KEYFILE"
            gcloud config set project ${PROJECT_ID}

            # Acquire cluster endpoint & CA certificate
            CLUSTER_INFO=$(gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION_FLAG} --format="json")
            CLUSTER_ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r '.endpoint')
            CLUSTER_CA=$(echo "$CLUSTER_INFO" | jq -r '.masterAuth.clusterCaCertificate')
            if [ -z "$CLUSTER_ENDPOINT" ] || [ -z "$CLUSTER_CA" ]; then
              echo "Failed to get cluster details via gcloud. Aborting."
              exit 1
            fi

            # Get access token
            TOKEN=$(gcloud auth print-access-token)

            mkdir -p $(dirname ${KUBECONFIG})
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

            kubectl --kubeconfig=${KUBECONFIG} version --short || true
            kubectl --kubeconfig=${KUBECONFIG} cluster-info || true
          '''
        }
      }
    }

    stage('Clean existing k8s resources') {
      steps {
        sh '''
          set -e
          export KUBECONFIG=${KUBECONFIG}
          # delete only app resources to avoid touching cluster-level things
          kubectl delete ingress java-app-ingress -n java-app --ignore-not-found
          kubectl delete service java-gradle-service -n java-app --ignore-not-found
          kubectl delete deployment java-gradle-app -n java-app --ignore-not-found
          sleep 5
        '''
      }
    }

    stage('Deploy to GKE') {
      steps {
        script {
          def action
          def version
          if (env.BUILD_NUMBER == '1') {
            action = 'ROLLOUT'
            version = 'v1.0'
            echo "First build: deploying v1.0"
          } else {
            action = params.DEPLOYMENT_ACTION
            version = params.VERSION
            echo "Requested action: ${action}, version: ${version}"
          }

          def imageTag = (version == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2

          sh """
            set -e
            export KUBECONFIG=${KUBECONFIG}
            echo "Applying namespace"
            kubectl apply -f k8s-Usecase/namespace.yaml

            echo "Applying configmap"
            kubectl apply -f k8s-Usecase/configmap.yaml -n java-app

            echo "Applying service (ensure NEG annotation present)"
            kubectl apply -f k8s-Usecase/service.yaml -n java-app

            echo "Preparing deployment manifest for ${imageTag}"
            cp k8s-Usecase/deployment.yaml /tmp/deployment-${version}.yaml
            sed -i "s|IMAGE_PLACEHOLDER|${imageTag}|g" /tmp/deployment-${version}.yaml
            sed -i "s|VERSION_PLACEHOLDER|${version}|g" /tmp/deployment-${version}.yaml

            # Apply deployment and ingress
            kubectl apply -f /tmp/deployment-${version}.yaml -n java-app --validate=false
            kubectl apply -f k8s-Usecase/ingress.yaml -n java-app

            echo "Waiting for deployment rollout (timeout 10m)..."
            kubectl rollout status deployment/java-gradle-app -n java-app --timeout=600s

          """
        }
      }
    }

    stage('Verify public access') {
      steps {
        sh '''
          set -e
          export KUBECONFIG=${KUBECONFIG}

          echo "Gathering statuses..."
          kubectl get deployment java-gradle-app -n java-app -o wide
          kubectl get pods -l app=java-gradle-app -n java-app -o wide
          kubectl get svc java-gradle-service -n java-app -o wide
          kubectl describe svc java-gradle-service -n java-app || true
          kubectl get endpoints java-gradle-service -n java-app -o yaml || true

          echo "Waiting for Ingress external IP (up to ~6 minutes)..."
          IP=""
          for i in {1..36}; do
            IP=$(kubectl get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
            if [ -n "$IP" ]; then
              echo "Found Ingress IP: $IP"
              break
            fi
            echo "Ingress IP not yet ready ($i/36). Sleeping 10s..."
            sleep 10
          done

          if [ -z "$IP" ]; then
            echo "ERROR: Ingress external IP not provisioned in time. Printing debug output..."
            kubectl describe ingress java-app-ingress -n java-app || true
            kubectl get events -n java-app --sort-by=.lastTimestamp | tail -n 50 || true
            exit 1
          fi

          echo "Probing application at http://$IP/ (will retry up to 20 times)..."
          HTTP_CODE="000"
          for attempt in {1..20}; do
            HTTP_CODE=$(curl -s -o /tmp/app_response.html -w "%{http_code}" --connect-timeout 5 http://$IP/ || echo "000")
            echo "Attempt ${attempt}: HTTP ${HTTP_CODE}"
            if [ "${HTTP_CODE}" = "200" ]; then
              echo "Application responded (HTTP 200). Showing top content:"
              sed -n '1,40p' /tmp/app_response.html || true
              break
            fi
            sleep 6
          done

          if [ "${HTTP_CODE}" != "200" ]; then
            echo "Application DID NOT respond from Ingress. Gathering debug info..."
            kubectl describe ingress java-app-ingress -n java-app || true
            kubectl get pods -l app=java-gradle-app -n java-app -o wide || true
            kubectl get endpoints java-gradle-service -n java-app -o yaml || true
            kubectl logs -l app=java-gradle-app -n java-app --tail=200 || true
            echo "You can inspect GCP LB backend health via gcloud. Example:"
            echo "  gcloud compute forwarding-rules list --global --filter=\"IPAddress=$IP\" --format='table(name,IPAddress,target)'"
            exit 1
          fi

          echo "SUCCESS: Application reachable at http://$IP/"
        '''
      }
    }
  }

  post {
    always {
      script {
        sh '''
          echo "=== POST-CHECKS ==="
          export KUBECONFIG=${KUBECONFIG}
          kubectl get pods,svc,ing -n java-app || true
          echo "--- End of pipeline run ---"
        '''
      }
    }

    success {
      echo "Pipeline completed successfully — app deployed and reachable."
    }

    failure {
      echo "Pipeline failed. Inspect the logs above for the failing stage and the debug prints."
    }
  }
}
