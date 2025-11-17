#!/bin/bash

# Enable required GCP APIs
gcloud services enable \
    container.googleapis.com \
    artifactregistry.googleapis.com \
    cloudresourcemanager.googleapis.com \
    compute.googleapis.com \
    iam.googleapis.com

echo "Required GCP APIs enabled"