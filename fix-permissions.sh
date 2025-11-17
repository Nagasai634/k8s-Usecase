#!/bin/bash
set -e

echo "=== Fixing Jenkins Workspace Permissions ==="

# Navigate to workspace
cd /var/lib/jenkins/workspace/first-job

# Fix ownership and permissions
sudo chown -R jenkins:jenkins k8s-Usecase/
sudo chmod -R 755 k8s-Usecase/

# Specifically fix gradlew
cd k8s-Usecase/java-gradle
sudo chmod +x ./gradlew
sudo chown jenkins:jenkins ./gradlew

echo "=== Current Directory Structure ==="
pwd
ls -la

echo "=== Gradlew Permissions ==="
ls -la gradlew

echo "=== Java Version ==="
java -version

echo "=== Fix Completed ==="