#!/bin/bash

# Set environment variables
export AWS_DEFAULT_REGION=us-east-2
export AWS_ACCOUNT_ID=123123123123
export CLUSTER_NAME=castimaging
export NODE_TYPE=t2.2xlarge

eksctl create cluster --name "$CLUSTER_NAME" --region "$AWS_DEFAULT_REGION" --nodegroup-name "$CLUSTER_NAME-ng" \
  --nodes-min 2 --nodes-max 4 --node-type "$NODE_TYPE" --nodes 2 --node-volume-size 100 --ssh-access --with-oidc \
  --zones ${AWS_DEFAULT_REGION}a,${AWS_DEFAULT_REGION}b --node-zones ${AWS_DEFAULT_REGION}b

eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" --approve
eksctl update addon --name vpc-cni --cluster "$CLUSTER_NAME"

eksctl create iamserviceaccount --name ebs-csi-controller-sa --namespace kube-system --cluster "$CLUSTER_NAME" \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy --approve \
  --role-only --role-name AmazonEKS_EBS_CSI_DriverRole-"$CLUSTER_NAME"

eksctl create addon --name aws-ebs-csi-driver --cluster "$CLUSTER_NAME" \
  --service-account-role-arn arn:aws:iam::"$AWS_ACCOUNT_ID":role/AmazonEKS_EBS_CSI_DriverRole-"$CLUSTER_NAME" --force

eksctl create iamserviceaccount --name efs-csi-controller-sa --namespace kube-system --cluster "$CLUSTER_NAME" \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy --approve \
  --role-only --role-name AmazonEKS_EFS_CSI_DriverRole-"$CLUSTER_NAME"

eksctl create addon --name aws-efs-csi-driver --cluster "$CLUSTER_NAME" \
  --service-account-role-arn arn:aws:iam::"$AWS_ACCOUNT_ID":role/AmazonEKS_EFS_CSI_DriverRole-"$CLUSTER_NAME" --force