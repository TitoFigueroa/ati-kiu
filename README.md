# **ati-kiu**

## This application allow people to store names easy and quick, since its going to be a global people names database, it will require high availability on execution side, and HA at database level. The application just allow anyone to push names, not possible to update or delete them. 

## AWS Terraform infrastructure for scalable apps

### Resources:
+ VPC                        (Managing the networking)
+ EKS Cluster                (Managing the app deploy and scaling)
+ Aurora MySQL Database       (Managing the app data at HA)
+ ECR Repository             (Managing the container images for EKS deployments)


# Architecture selection based on Security and Performance Best Practices usede

+ RDS deployed in private VPC only, using VPC Endpoint to make possible talk EKS with RDS securely via private subnet
+ ALB in front of EKS Cluster to allow secured traffic from outside to pods apps
+ App Database Creds, they are stored for local dev test, but after the app deployment will have to look environment variables to find the right user/pass/host to reach the database. (This step requires further development, and use of SSM storing creds information in a secure way)
+ ECR repository not public, remaining the company docker images on private, and allowing use versioning.
+ RDS Aurora MySQL, this resource its a self managed cluster database, that allow us have multiple nodes behing a database proxy, this proxy help us to pick nodes behing depending on query types. If we want to just read, it will use a slave node, and if we want to write, can be configured to select another. Even can be configured to have a read only node, in order to perform long task like huge reports of the entire company. 
+ VPC with 3 AZNs allowing the eks cluster nodes run on each zone, this will provide more reliability in case of a region failure
+ AWS Region selected: us-east-1 as a starting point since is one of the fastest, securest and sometimes involves better resources costs. This infra will be replicated in more regions previous an analysis to see from where we have most of incoming users. For example, if we have a lot of users from India we can replicate this infra near that region to allow better peformance. 

# Full flow steps:

## 1 - INFRASTRUCTURE CREATION: Create infrastructure based on terraform files inside ["infrastructure"](https://github.com/TitoFigueroa/ati-kiu/blob/infrastructure) folder, this step relays on a previously Terraform Cloud workspace creation and integrated with GitHub. After pushing the code to the configured branch (in this case main), infra will be planned, and mnually approved the apply.

## 2 - APP-BUILD: Build docker image, and push it to the ECR container registry, this will allow the eks deployment, find the right docker container to run. Find the Dockerfile under [devops/docker](https://github.com/TitoFigueroa/ati-kiu/blob/devops/docker) folder. (Inside this folder you will see a compose file, its to help developers test the code locally with a docker based mysql database). At root repository level, code app is available inside the [app](https://https://github.com/TitoFigueroa/ati-kiu/blob/app) folder.

## 3 - DATABASE CONFIGURATION: Connect to the database via Bastion host cause the database is under a private subnet, OR deploy a small app insie the EKS that executes the connection and model database creation script. No matter which method you select, the model script is under the [database-model](https://https://github.com/TitoFigueroa/ati-kiu/blob/database-model) folder.

## 4 - EKS CONFIGURATION: Once the infrastructure is created completed and correctly, follow the steps under the [devops/deployment-docs](https://https://github.com/TitoFigueroa/ati-kiu/blob/devops/deployment-docs) folder, this are a mark down files, that resumes all the steps requires to configure EKS allowing use add-ons that will be super useful to deploy public apps via loadbalancer

## 5 - APP DEPLOYMENT: Last but not least step, deploying the app with required objects to make alive the app inside the EKS cluster. Execute in the indicated order the eksctl commands to deploy each manifest correctly, look under the [devops/k8s](https://https://github.com/TitoFigueroa/ati-kiu/blob/devops/k8s) folder to move forward deploying this app.





# **DISCLAIMER**: This content is wroten for people with knowledge and experience on terraform, aws and node. There are steps that will require some kind of experience to trouble shoot issues in case of a failure. 