# Documentation Overview

This repository contains the helm chart and the documentation for deploying CAST Imaging on Azure AKS or Amazon EKS.

## Infrastructure Setup Guides

### Kubernetes cluster minimum requirements:
- Number of worker nodes: 2
- Worker node specs: 32GB RAM - 8 vCPUs - 50GB Disk (system)

### [EKS Cluster Setup](EKS-ClusterSetup.md)
Instructions to setup a sample AWS EKS cluster with minimum requirements.

### AKS Cluster Setup
We are not providing instructions for creating an Azure AKS cluster. Please refer to Azure on-line documentation.

## Imaging Deployment Guides

### [AWS EKS Configuration](README-AWS-EKS.md)
Guide to deploy Imaging on EKS

### [Azure AKS Configuration](README-Azure-AKS.md)
Guide to deploy Imaging on AKS

## Upgrade Documentation

### [Version 3.2.2 Upgrade Guide](README-3.2.2-Upgrade.md)
Guide to upgrade your Imaging Kubernetes deployment from 3.1.1 to 3.2.2

## Getting Started

Please refer to the specific documentation files above for detailed instructions on each topic. We recommend reading through the relevant guides carefully before proceeding with any implementation.
