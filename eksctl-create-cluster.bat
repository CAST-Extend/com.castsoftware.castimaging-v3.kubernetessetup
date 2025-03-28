set AWS_DEFAULT_REGION=us-east-2
set AWS_ACCOUNT_ID=123123123123
set CLUSTER_NAME=castimaging

REM If you don't have SSH keys, you can generate one using the following command in PowerShell:
REM mkdir C:\Users\USERNAME\.ssh
REM ssh-keygen -t rsa -b 2048 -f C:\Users\USERNAME\.ssh\id_rsa

eksctl create cluster --name %CLUSTER_NAME% --region %AWS_DEFAULT_REGION% --nodegroup-name %CLUSTER_NAME%-ng --nodes-min 2 --nodes-max 4 --node-type t2.2xlarge --nodes 2 --node-volume-size 50 --ssh-access  --with-oidc
eksctl utils associate-iam-oidc-provider --cluster %CLUSTER_NAME% --approve
eksctl update addon --name vpc-cni --cluster %CLUSTER_NAME% 

eksctl create iamserviceaccount   --name ebs-csi-controller-sa   --namespace kube-system   --cluster %CLUSTER_NAME%   --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy   --approve   --role-only   --role-name AmazonEKS_EBS_CSI_DriverRole-%CLUSTER_NAME%
eksctl create addon  --name aws-ebs-csi-driver   --cluster %CLUSTER_NAME%   --service-account-role-arn arn:aws:iam::%AWS_ACCOUNT_ID%:role/AmazonEKS_EBS_CSI_DriverRole-%CLUSTER_NAME%   --force

eksctl create iamserviceaccount   --name efs-csi-controller-sa   --namespace kube-system   --cluster %CLUSTER_NAME%   --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy   --approve   --role-only   --role-name AmazonEKS_EFS_CSI_DriverRole-%CLUSTER_NAME%
eksctl create addon  --name aws-efs-csi-driver   --cluster %CLUSTER_NAME%   --service-account-role-arn arn:aws:iam::%AWS_ACCOUNT_ID%:role/AmazonEKS_EFS_CSI_DriverRole-%CLUSTER_NAME%   --force
