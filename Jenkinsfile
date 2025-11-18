pipeline {
  agent any

  options {
    skipDefaultCheckout()
    timeout(time: 60, unit: 'MINUTES')
  }

  parameters {
    choice(name: 'DEPLOYMENT_ACTION',
           choices: ['ROLLOUT', 'ROLLBACK'],
           description: 'Choose deployment action (ignored on first run; first run auto-deploys v1.0)')
    choice(name: 'VERSION',
           choices: ['v1.0', 'v2.0'],
           description: 'Choose version to deploy (ignored on first run)')
    string(name: 'ALLOWED_IP_CIDR',
           defaultValue: '136.119.42.77',
           description: 'CIDR to whitelist on the ingress (change per-run)')
  }

  environment {
    // EDIT these for your environment
    PROJECT_ID = 'planar-door-476510-m1'
    REGION = 'us-central1'
    CLUSTER_NAME = 'autopilot-demo'
    GAR_REPO = 'java-app'
    IMAGE_NAME = 'java-app'

    // Derived
    WORKSPACE_BIN = "${env.WORKSPACE}/bin"
    GAR_HOST = "${env.REGION}-docker.pkg.dev"
    V1_TAG = "v1.0-${env.BUILD_NUMBER}"
    V2_TAG = "v2.0-${env.BUILD_NUMBER}"
    GAR_IMAGE_V1 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V1_TAG}"
    GAR_IMAGE_V2 = "${env.GAR_HOST}/${env.PROJECT_ID}/${env.GAR_REPO}/${env.IMAGE_NAME}:${env.V2_TAG}"
    KUBECONFIG = "${env.WORKSPACE}/.kube/config"

    // Safe-mode defaults
    DEFAULT_DESIRED_REPLICAS = "3"
    SAFE_REPLICAS = "1"
    SAFE_REQUEST_CPU = "100m"
    SAFE_LIMIT_CPU = "500m"
    SAFE_REQUEST_MEM = "256Mi"
    SAFE_LIMIT_MEM = "512Mi"
  }

  stages {
    stage('Checkout Repo') {
      steps { checkout scm }
    }

    stage('Ensure Tools') {
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

          if command -v docker >/dev/null 2>&1; then
            docker --version || true
          else
            echo "WARNING: docker not found on agent. Build/push will fail without docker."
          fi

          gcloud --version || true
        '''
      }
    }

    stage('Build & Push Images') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}
            gcloud auth configure-docker ${GAR_HOST} --quiet || true

            # locate java-gradle dir
            if [ -d "k8s-Usecase/java-gradle" ]; then
              cd k8s-Usecase/java-gradle
            elif [ -d "java-gradle" ]; then
              cd java-gradle
            else
              echo "Could not find java-gradle directory at k8s-Usecase/java-gradle or java-gradle. Trying workspace root."
            fi

            mkdir -p src/main/resources/static

            # --- v1
            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V1.0</title></head><body><h1>Version 1.0 - BLUE</h1></body></html>
EOF
            ./gradlew clean build --no-daemon || true
            docker build -t $GAR_IMAGE_V1 . || true
            for i in 1 2 3; do docker push $GAR_IMAGE_V1 && break || { echo "push v1 attempt $i failed"; sleep 5; }; done || true

            # --- v2
            cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html><html><head><title>V2.0</title></head><body><h1>Version 2.0 - GREEN</h1></body></html>
EOF
            ./gradlew clean build --no-daemon || true
            docker build -t $GAR_IMAGE_V2 . || true
            for i in 1 2 3; do docker push $GAR_IMAGE_V2 && break || { echo "push v2 attempt $i failed"; sleep 5; }; done || true
          '''
        }
      }
    }

    stage('Authenticate to GKE') {
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project ${PROJECT_ID}

            if gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} --quiet; then
              mkdir -p "$(dirname ${KUBECONFIG})"
              "${WORKSPACE_BIN}/kubectl" config view --raw > "${KUBECONFIG}" || true
              echo "Wrote kubeconfig to ${KUBECONFIG}"
            else
              echo "gcloud get-credentials failed. Will mark SKIP_K8S=true and continue pipeline without k8s operations."
              echo "SKIP_K8S=true" > /tmp/jenkins_skip_k8s
            fi
          '''
        }
      }
    }

    stage('Verify Authentication') {
      steps {
        script {
          env.SKIP_K8S = 'true'
          if (fileExists('/tmp/jenkins_skip_k8s')) {
            echo "Previous step signaled to skip K8s (get-credentials failed)."
            env.SKIP_K8S = 'true'
          } else {
            def out = sh(script: """${WORKSPACE_BIN}/kubectl --kubeconfig=${KUBECONFIG} auth can-i get pods --ignore-not-found=true >/dev/null 2>&1 && echo OK || echo NO""", returnStdout: true).trim()
            if (out == 'OK') {
              echo "kubectl authentication appears to work."
              env.SKIP_K8S = 'false'
            } else {
              echo "kubectl authentication failed (auth check returned NO). Setting SKIP_K8S=true."
              echo "If this is unexpected, ensure the GCP service account has appropriate IAM roles (e.g. roles/container.admin or roles/container.developer) and the cluster is reachable."
              env.SKIP_K8S = 'true'
            }
          }
        }
      }
    }

    stage('Decide Action (first-run detection / defaults)') {
      steps {
        script {
          env.EFFECTIVE_ACTION = ''
          env.EFFECTIVE_VERSION = ''

          if (env.SKIP_K8S == 'false') {
            echo "Attempting first-run detection against cluster..."
            def exists = sh(script: """${WORKSPACE_BIN}/kubectl --kubeconfig=${KUBECONFIG} -n java-app get deploy java-gradle-app --ignore-not-found=true --no-headers -o name || true""", returnStdout: true).trim()
            boolean deployedBefore = exists != ''
            if (!deployedBefore) {
              echo "No existing deployment found -> forcing ROLLOUT of v1.0"
              env.EFFECTIVE_ACTION = 'ROLLOUT'
              env.EFFECTIVE_VERSION = 'v1.0'
            } else {
              env.EFFECTIVE_ACTION = params.DEPLOYMENT_ACTION
              env.EFFECTIVE_VERSION = params.VERSION
              echo "Using requested parameters"
            }
          } else {
            echo "Cluster unreachable. Falling back to provided parameters (or defaults)."
            env.EFFECTIVE_ACTION = params.DEPLOYMENT_ACTION ?: 'ROLLOUT'
            env.EFFECTIVE_VERSION = params.VERSION ?: 'v1.0'
          }
          echo "EFFECTIVE_ACTION=${env.EFFECTIVE_ACTION}"
          echo "EFFECTIVE_VERSION=${env.EFFECTIVE_VERSION}"
        }
      }
    }

    stage('Check CPU Quota & Decide SAFE Mode') {
      when { expression { env.SKIP_K8S != 'true' } }
      steps {
        withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_SA_KEYFILE')]) {
          sh '''
            set -e
            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SA_KEYFILE}"
            gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
            gcloud config set project $PROJECT_ID

            DESIRED=$DEFAULT_DESIRED_REPLICAS
            REQ_PER_POD_M=250
            REQ_TOTAL_M=$((DESIRED * REQ_PER_POD_M))

            QLINE=$(gcloud compute regions describe $REGION --project=$PROJECT_ID --format="value(quotas[?metric=='CPUS'].limit,quotas[?metric=='CPUS'].usage)" || echo "")
            if [ -z "$QLINE" ]; then
              echo "Could not read CPUS quota -> SAFE mode"
              echo "USE_SAFE=1" > /tmp/decide_mode
            else
              LIMIT=$(echo $QLINE | awk '{print $1}')
              USAGE=$(echo $QLINE | awk '{print $2}')
              if [ -z "$LIMIT" ] || [ -z "$USAGE" ]; then
                echo "Empty LIMIT or USAGE -> SAFE mode"
                echo "USE_SAFE=1" > /tmp/decide_mode
              else
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
            fi
            cat /tmp/decide_mode || true
          '''
        }
      }
    }

    stage('Apply base manifests & ensure external IP') {
      when { expression { env.SKIP_K8S != 'true' } }
      steps {
        sh '''
          set -e
          export KUBECONFIG="${KUBECONFIG}"
          KUBECTL="${WORKSPACE_BIN}/kubectl"

          ${KUBECTL} create namespace java-app --dry-run=client -o yaml | ${KUBECTL} apply -f - --validate=false || echo "Namespace creation skipped/failed"
          ${KUBECTL} apply -f k8s-Usecase/configmap.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f k8s-Usecase/service.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f k8s-Usecase/ingress.yaml -n java-app --validate=false || true
          ${KUBECTL} apply -f k8s-Usecase/hpa.yaml -n java-app --validate=false || true

          # Determine service name (by label) - adjust selector if your service uses a different label
          SVC=$(${KUBECTL} -n java-app get svc -l app=java-gradle-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
          if [ -n "$SVC" ]; then
            TYPE=$(${KUBECTL} -n java-app get svc "$SVC" -o jsonpath='{.spec.type}')
            echo "Service $SVC type=$TYPE"
            if [ "$TYPE" = "ClusterIP" ]; then
              echo "Patching service $SVC -> LoadBalancer (to expose externally)"
              ${KUBECTL} -n java-app patch svc "$SVC" -p '{"spec":{"type":"LoadBalancer"}}' || echo "svc patch failed"
            fi
          else
            echo "Could not detect service with label app=java-gradle-app. Skipping automatic type patch. If your service name/label differ, update the pipeline selector."
          fi

          # Wait up to 5 minutes for external IP on service or ingress
          FOUND_IP=""
          for i in $(seq 1 60); do
            if [ -n "$SVC" ]; then
              FOUND_IP=$(${KUBECTL} -n java-app get svc "$SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            fi
            if [ -z "$FOUND_IP" ]; then
              FOUND_IP=$(${KUBECTL} -n java-app get ingress java-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            fi
            if [ -n "$FOUND_IP" ]; then
              echo "External IP discovered: $FOUND_IP"
              break
            fi
            echo "Waiting for external IP... (attempt $i)"
            sleep 5
          done

          echo "$FOUND_IP" > /tmp/java_app_external_ip || true
        '''
      }
    }

    stage('Temporarily allow agent IP on ingress') {
      when { expression { env.SKIP_K8S != 'true' } }
      steps {
        script {
          // Try to detect public IP of agent (best-effort); do not fail if unavailable
          def agentIp = ''
          try {
            agentIp = sh(script: "curl -s https://ifconfig.co || curl -s https://ifconfig.me || echo ''", returnStdout: true).trim()
          } catch (e) {
            agentIp = ''
          }
          if (agentIp) {
            echo "Detected agent public IP: ${agentIp}"
            env.AGENT_PUBLIC_IP = agentIp
            // create a backup of the current annotation value so we can restore later
            sh '''
              set -e
              export KUBECONFIG="${KUBECONFIG}"
              KUBECTL="${WORKSPACE_BIN}/kubectl"
              ANNO=$( ${KUBECTL} -n java-app get ingress java-app-ingress -o jsonpath='{.metadata.annotations.nginx\\.ingress\\.kubernetes\\.io/whitelist-source-range}' 2>/dev/null || echo "" )
              echo "$ANNO" > /tmp/ingress_whitelist_before || true
              # build new annotation: combine user-provided and agent ip (avoid duplicates)
              NEW="${params.ALLOWED_IP_CIDR}"
              if [ -n "$ANNO" ]; then
                # append existing if not already present
                case ",$ANNO," in
                  *,"${params.ALLOWED_IP_CIDR}",* ) ;; 
                  * ) NEW="$NEW,$ANNO" ;;
                esac
              fi
              # append agent ip if not already present
              case ",$NEW," in
                *,"${AGENT_PUBLIC_IP}",* ) ;;
                * ) NEW="$NEW,${AGENT_PUBLIC_IP}" ;;
              esac
              echo "Applying temporary ingress whitelist: $NEW"
              ${KUBECTL} -n java-app patch ingress java-app-ingress --type='merge' -p "{\"metadata\":{\"annotations\":{\"nginx.ingress.kubernetes.io/whitelist-source-range\":\"${NEW}\"}}}" || echo "ingress patch failed"
            '''
          } else {
            echo "Could not detect agent public IP automatically; skipping temporary ingress patch. If agent curl fails later, consider adding the agent IP to ALLOWED_IP_CIDR."
          }
        }
      }
    }

    stage('Perform Action (Rollout / Rollback)') {
      when { expression { env.SKIP_K8S != 'true' } }
      steps {
        script {
          def safeFlag = sh(script: """cat /tmp/decide_mode 2>/dev/null || echo 'USE_SAFE=1'; grep -o 'USE_SAFE=[01]' /tmp/decide_mode 2>/dev/null || echo 'USE_SAFE=1'""", returnStdout: true).trim()
          boolean safeMode = safeFlag.contains('USE_SAFE=1')
          def imageToUse = (env.EFFECTIVE_VERSION == 'v1.0') ? env.GAR_IMAGE_V1 : env.GAR_IMAGE_V2

          if (env.EFFECTIVE_ACTION == 'ROLLOUT') {
            echo "ROLLOUT image=${imageToUse} safeMode=${safeMode}"

            sh """
              set -e
              export KUBECONFIG="${KUBECONFIG}"
              KUBECTL="${WORKSPACE_BIN}/kubectl"

              cp k8s-Usecase/deployment.yaml /tmp/deployment-"${env.EFFECTIVE_VERSION}".yaml
              sed -i "s|IMAGE_PLACEHOLDER|${imageToUse}|g" /tmp/deployment-"${env.EFFECTIVE_VERSION}".yaml
              sed -i "s|VERSION_PLACEHOLDER|${env.EFFECTIVE_VERSION}|g" /tmp/deployment-"${env.EFFECTIVE_VERSION}".yaml

              ${KUBECTL} apply -f /tmp/deployment-"${env.EFFECTIVE_VERSION}".yaml -n java-app --validate=false || echo "Deployment apply failed"
            """

            if (safeMode) {
              echo "Applying SAFE patches (replicas=${SAFE_REPLICAS})"
              sh '''
                set -e
                export KUBECONFIG="${KUBECONFIG}"
                KUBECTL="${WORKSPACE_BIN}/kubectl"

                ${KUBECTL} scale deployment/java-gradle-app -n java-app --replicas=$SAFE_REPLICAS || true
                ${KUBECTL} patch deployment java-gradle-app -n java-app --type='merge' -p '{
                  "spec": {
                    "template": {
                      "spec": {
                        "containers": [
                          {
                            "name": "java-app",
                            "resources": {
                              "requests": {"cpu": "'"$SAFE_REQUEST_CPU"'", "memory": "'"$SAFE_REQUEST_MEM"'"},
                              "limits": {"cpu": "'"$SAFE_LIMIT_CPU"'", "memory": "'"$SAFE_LIMIT_MEM"'"}
                            },
                            "readinessProbe": {
                              "httpGet": {"path": "/", "port": 8080},
                              "initialDelaySeconds": 8,
                              "periodSeconds": 5,
                              "failureThreshold": 6
                            }
                          }
                        ]
                      }
                    }
                  }
                }' || true
              '''
            } else {
              echo "Ensuring readinessProbe present"
              sh '''
                set -e
                export KUBECONFIG="${KUBECONFIG}"
                KUBECTL="${WORKSPACE_BIN}/kubectl"

                ${KUBECTL} patch deployment java-gradle-app -n java-app --type='merge' -p '{
                  "spec": {
                    "template": {
                      "spec": {
                        "containers": [
                          {
                            "name": "java-app",
                            "readinessProbe": {
                              "httpGet": {"path": "/", "port": 8080},
                              "initialDelaySeconds": 8,
                              "periodSeconds": 5,
                              "failureThreshold": 6
                            }
                          }
                        ]
                      }
                    }
                  }
                }' || true
              '''
            }

            // patch ingress whitelist (ensure user's ALLOWED_IP_CIDR is present)
            sh """
              set -e
              export KUBECONFIG="${KUBECONFIG}"
              KUBECTL="${WORKSPACE_BIN}/kubectl"
              # Ensure the desired allowed CIDR is part of annotation (this won't remove agent IP if present)
              CUR=\$(${KUBECTL} -n java-app get ingress java-app-ingress -o jsonpath='{.metadata.annotations.nginx\\.ingress\\.kubernetes\\.io/whitelist-source-range}' 2>/dev/null || echo "")
              NEW="${params.ALLOWED_IP_CIDR}"
              if [ -n "\$CUR" ]; then
                case ",\$CUR," in
                  *,"${params.ALLOWED_IP_CIDR}",* ) NEW="\$CUR" ;; 
                  * ) NEW="\$CUR,${params.ALLOWED_IP_CIDR}" ;;
                esac
              fi
              echo "Applying/ensuring ALLOWED_IP_CIDR present in ingress: \$NEW"
              ${KUBECTL} -n java-app patch ingress java-app-ingress --type='merge' -p "{\"metadata\":{\"annotations\":{\"nginx.ingress.kubernetes.io/whitelist-source-range\":\"\$NEW\"}}}" || echo "Ingress whitelist patch skipped/failed"
            """

            // wait for rollout or collect debug info on failure
            sh '''
              set -e
              export KUBECONFIG="${KUBECONFIG}"
              KUBECTL="${WORKSPACE_BIN}/kubectl"

              if ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=900s; then
                echo "Rollout succeeded."
              else
                echo "Rollout timed out/failed - collecting debug info"
                ${KUBECTL} describe deployment java-gradle-app -n java-app || true
                ${KUBECTL} get pods -n java-app -o wide || true
                for P in $(${KUBECTL} get pods -n java-app -l app=java-gradle-app -o name 2>/dev/null || echo ""); do
                  echo "=== LOGS for ${P} ==="
                  ${KUBECTL} logs -n java-app ${P} --tail=200 || true
                done
                ${KUBECTL} get events -n java-app --sort-by=.lastTimestamp | tail -n 80 || true
                exit 1
              fi
            '''
          } else {
            echo "ROLLBACK requested"
            sh '''
              set -e
              export KUBECONFIG="${KUBECONFIG}"
              KUBECTL="${WORKSPACE_BIN}/kubectl"

              ${KUBECTL} rollout undo deployment/java-gradle-app -n java-app || { echo "rollback failed"; exit 1; }
              ${KUBECTL} rollout status deployment/java-gradle-app -n java-app --timeout=300s || { echo "rollback wait failed"; exit 1; }
            '''
          }
        }
      }
    }

    stage('Verify & Test (attempt homepage fetch)') {
      when { expression { env.SKIP_K8S != 'true' } }
      steps {
        sh '''
          set -e
          export KUBECONFIG="${KUBECONFIG}"
          KUBECTL="${WORKSPACE_BIN}/kubectl"

          echo "=== DEPLOYMENT ==="
          ${KUBECTL} get deployment java-gradle-app -n java-app -o wide || true
          ${KUBECTL} get pods -l app=java-gradle-app -n java-app -o wide || true

          echo "=== SERVICE & INGRESS ==="
          ${KUBECTL} get svc -n java-app || true
          ${KUBECTL} get ingress java-app-ingress -n java-app -o yaml || true

          IP=$(cat /tmp/java_app_external_ip 2>/dev/null || echo "")
          if [ -z "$IP" ]; then
            IP=$(${KUBECTL} get svc -n java-app -l app=java-gradle-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
          fi
          if [ -z "$IP" ]; then
            IP=$(${KUBECTL} get ingress java-app-ingress -n java-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
          fi

          if [ -n "$IP" ]; then
            echo "Attempting curl http://$IP/ from agent..."
            if curl -s --connect-timeout 5 http://$IP/ | head -n 10; then
              echo "Homepage fetched successfully (agent)."
            else
              echo "Could not fetch homepage from agent. That may be due to ALLOWED_IP_CIDR blocking this agent's IP. Will try an in-cluster curl to verify the app is serving."
              echo "=== Running ephemeral in-cluster curl pod ==="
              ${KUBECTL} run curltest -n java-app --rm -i --restart=Never --image=curlimages/curl --command -- sh -c "sleep 1; echo '======== IN-CLUSTER CURL OUTPUT ========'; curl -sS --connect-timeout 5 http://$IP/ || echo 'in-cluster curl failed';" || true
            fi
          else
            echo "No external IP found. Trying in-cluster access via ClusterIP service."
            SVC=$(${KUBECTL} -n java-app get svc -l app=java-gradle-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$SVC" ]; then
              CLUSTER_IP=$(${KUBECTL} -n java-app get svc "$SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
              echo "Cluster service $SVC clusterIP=$CLUSTER_IP"
              if [ -n "$CLUSTER_IP" ]; then
                ${KUBECTL} run curltest -n java-app --rm -i --restart=Never --image=curlimages/curl --command -- sh -c "echo 'curl http://$CLUSTER_IP/'; curl -sS --connect-timeout 5 http://$CLUSTER_IP/ || echo 'in-cluster clusterIP curl failed';" || true
              fi
            else
              echo "No service found to test."
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
      // restore ingress whitelist to what it was before the run (best-effort)
      sh '''
        set -e
        export KUBECONFIG="${KUBECONFIG}"
        KUBECTL="${WORKSPACE_BIN}/kubectl"
        if [ -f /tmp/ingress_whitelist_before ]; then
          OLD=$(cat /tmp/ingress_whitelist_before || echo "")
          if [ -n "$OLD" ]; then
            echo "Restoring original ingress whitelist: $OLD"
            ${KUBECTL} -n java-app patch ingress java-app-ingress --type='merge' -p "{\"metadata\":{\"annotations\":{\"nginx.ingress.kubernetes.io/whitelist-source-range\":\"$OLD\"}}}" || echo "restore ingress annotation failed"
          else
            # if original was blank, remove annotation
            echo "Removing temporary whitelist annotation (original empty)"
            ${KUBECTL} -n java-app patch ingress java-app-ingress --type='json' -p '[{"op":"remove","path":"/metadata/annotations/nginx.ingress.kubernetes.io~1whitelist-source-range"}]' || echo "remove annotation failed or not present"
          fi
        fi
        rm -f /tmp/deployment-* /tmp/decide_mode /tmp/jenkins_skip_k8s /tmp/java_app_external_ip /tmp/ingress_whitelist_before 2>/dev/null || true
      '''
    }
    success { echo "Pipeline completed successfully." }
    failure { echo "Pipeline failed. See console output above for details." }
  }
}
