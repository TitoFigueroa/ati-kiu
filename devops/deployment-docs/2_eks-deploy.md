# Scripts to configure kubeconfig  and deploy the app

### Kubeconfig update
+ aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)

### Namespace creation to have multiple environments inside this cluster.
+ kubectl apply -f kiu-namespace.yml

### App deployment
+ kubectl apply -f kiu-app-deployment.yml

