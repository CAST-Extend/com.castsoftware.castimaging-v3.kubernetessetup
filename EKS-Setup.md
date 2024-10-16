# Prerequisites


## IAM user and permissions
For EKS, user needs to have certain privileges to e.g. create all the required resources and objects.  
According AWS Best Practices you should *never* use your root account for working with AWS services. 

There are 2 attempts to follow:

1. provide admin access  
login with an admin of your AWS account
go to "IAM" => "users" => click on your user => "Permissions" => "Add permission" => then search for _AdministratorAccess_ and attach this policy  
Basically your user just requires *one* policy being attached:  _AdministratorAccess_

2. provide a dedicated list of privileges/policies  
to cover all the required privileges, first you have to create additional policies  

EKS-Admin-policy:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:*"
            ],
            "Resource": "*"
        }
    ]
}
```

CloudFormation-Admin-policy:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:*"
            ],
            "Resource": "*"
        }
    ]
}
```
Finally, assign the following policies to your IAM user you are going to use:
  - AmazonEC2FullAccess
  - IAMFullAccess
  - AmazonVPCFullAccess
  - CloudFormation-Admin-policy
  - EKS-Admin-policy  

...where the last 2 policies are the ones you created above

### create IAM role
AWSServiceRoleForAmazonEKS 

* open https://console.aws.amazon.com/iam and choose _Roles_ => _create role_  
* choose _EKS_ service followed by _Allows Amazon EKS to manage your clusters on your behalf_  
* choose _Next: Permissions_
* click _Next: Review_

### create keypair
eks-mycluster

* open EC2 dashboard https://console.aws.amazon.com/ec2
* click _KeyPairs_ in left navigation bar under section "Network&Security"
* click _Create Key Pair_
* provide name for keypair, _eks-mycluster_ and click *_Create_*
* !! the keypair will be downloaded immediately => file *eks-mycluster.pem* !!

### create API Access key/-secret
* create key+secret via AWS console
  AWS-console => IAM => Users => <your user> => tab *Security credentials* => button *Create access key*
* Download the .csv file (contains the Access key ID)

# Setup aws cli

Follow instructions from here: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

## Test
```bash
aws --version
```
## Configure AWS access
```
aws configure
```
* Provide Access key ID, Default region name (us-east-2), Default output format (json)


# Setup of eksctl 

## Installation
for non-Linux OS you can find a binary download here:
https://github.com/weaveworks/eksctl/releases

on Linux, you can just execute:

```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp  

sudo mv /tmp/eksctl /usr/local/bin
```

This utility will use the same _credentials_ file as we explored for the AWS cli, located under '~/.aws/credentials'

## Test
```eksctl version```


# kubectl - the commandline K8s tool


## install _kubectl

Follow instructions from here: https://kubernetes.io/docs/tasks/tools/

## check kubectl

* Linux:  
```kubectl version --short --client```
* Windows:  
```kubectl.exe version --short --client```


# Install Helm

# Documentation:
https://helm.sh/docs/intro/quickstart/

# Binary download:
https://github.com/helm/helm/releases



# Create cluster

## Update ex_eks-mycluster.yaml file (VPC id, subnets, EC2 key)

## Apply it: 

```eksctl create cluster -f ex_eks-mycluster.yaml```


# Enable EBS CSI Driver

## Update region and cluster name in below commands before executing them

```
eksctl utils associate-iam-oidc-provider --region=us-east-2 --cluster=eks-mycluster --approve
```

```
eksctl create iamserviceaccount   --region us-east-2   --name ebs-csi-controller-sa   --namespace kube-system   --cluster eks-mycluster   --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy   --approve   --role-only   --role-name AmazonEKS_EBS_CSI_DriverRole
```

```
eksctl create addon --name aws-ebs-csi-driver --cluster eks-mycluster --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole --force
```
