# EKS Add-on settings (This step requires the cluster be alive) **Remember, replace "my-cluster" with the real cluster name on each step that requires it**

## 1 EKS Load Balancer Add-on
### Create Load Balancer policy (policy file already included in this folder) 
+ aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json

### Create an IAM role based on previous policy
+ eksctl create iamserviceaccount \
  --cluster=my-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::111122223333:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

### Install cert-manager
+ kubectl apply \
    --validate=false \
    -f https://github.com/jetstack/cert-manager/releases/download/v1.13.3/cert-manager.yaml

### Install alb controller steps
+ curl -Lo v2_5_4_full.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.5.4/v2_5_4_full.yaml
+ sed -i.bak -e '596,604d' ./v2_5_4_full.yaml
+ sed -i.bak -e 's|your-cluster-name|my-cluster|' ./v2_5_4_full.yaml 
+ kubectl apply -f v2_5_4_full.yaml
+ curl -Lo v2_5_4_ingclass.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.5.4/v2_5_4_ingclass.yaml
+ kubectl apply -f v2_5_4_ingclass.yaml

### Verify controller installation
+ kubectl get deployment -n kube-system aws-load-balancer-controller


## 2 VPC CNI Add-on settings Creation

### Verify Vpc CNI Add-on if installed (IF a version number is returned we are done, if not follow steps bellow this verification check)
+ kubectl describe daemonset aws-node --namespace kube-system | grep amazon-k8s-cni: | cut -d : -f 3
+ aws eks describe-addon --cluster-name my-cluster --addon-name vpc-cni --query addon.addonVersion --output text

### Steps if Add-on is not there
+ kubectl get daemonset aws-node -n kube-system -o yaml > aws-k8s-cni-old.yaml
+ aws eks create-addon --cluster-name my-cluster --addon-name vpc-cni --addon-version v1.16.2-eksbuild.1 \
    --service-account-role-arn arn:aws:iam::111122223333:role/AmazonEKSVPCCNIRole
+ aws eks describe-addon --cluster-name my-cluster --addon-name vpc-cni --query addon.addonVersion --output text

## 3 EKS Core DNS Add-on settings

### Check version CORE DNS (IF a version number is returned we are done, if not follow steps bellow this verification check)
+ kubectl describe deployment coredns --namespace kube-system | grep coredns: | cut -d : -f 3
+ aws eks describe-addon --cluster-name my-cluster --addon-name coredns --query addon.addonVersion --output text

### Steps if Add-on is not there
+ kubectl get deployment coredns -n kube-system -o yaml > aws-k8s-coredns-old.yaml
+ aws eks create-addon --cluster-name my-cluster --addon-name coredns --addon-version v1.11.1-eksbuild.6
+ aws eks describe-addon --cluster-name my-cluster --addon-name coredns --query addon.addonVersion --output text


## 4 Kube Proxy Add-on settings

### Verify version of self managed Kube Proxy 
+ aws eks describe-addon --cluster-name my-cluster --addon-name kube-proxy --query addon.addonVersion --output text

### Check Kube Proxy container image version
+ kubectl describe daemonset kube-proxy -n kube-system | grep Image

### Update Kube Proxy version if versions is old 
+ kubectl set image daemonset.apps/kube-proxy -n kube-system kube-proxy=602401143452.dkr.ecr.region-code.amazonaws.com/eks/kube-proxy:v1.26.2-minimal-eksbuild.2

### Confirm new version updated
+ kubectl describe daemonset kube-proxy -n kube-system | grep Image | cut -d ":" -f 3

