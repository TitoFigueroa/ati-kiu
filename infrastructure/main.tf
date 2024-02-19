# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

# Filter out local zones, which are not currently supported 
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  cluster_name = "kiu-eks-${random_string.suffix.result}-challenge"
  db_name   = "kiu-db-${basename(path.cwd)}"
  ecr_name = "kiu-ecr"
  db_tags = {
    Example    = local.db_name
    GithubRepo = "terraform-aws-rds-aurora"
    GithubOrg  = "terraform-aws-modules"
    }
  ecr_tags = {
    appName   = "ati-kiu"
    repoType  = "private"
    }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"
  name = "kiu-challenge-vpc"
  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

# https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/DBActivityStreams.Prereqs.html#DBActivityStreams.Prereqs.KMS
module "vpc_endpoints" {
    source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
    version = "~> 5.0"

    vpc_id = module.vpc.vpc_id

    create_security_group      = true
    security_group_name_prefix = "${local.db_name}-vpc-endpoints-"
    security_group_description = "VPC endpoint security group"
    security_group_rules = {
    ingress_https = {
        description = "HTTPS from VPC"
        cidr_blocks = [module.vpc.vpc_cidr_block]
    }
    }

    endpoints = {
    kms = {
        service             = "kms"
        private_dns_enabled = true
        subnet_ids          = module.vpc.database_subnets
    }
    }

    tags = local.db_tags
}

################################################################################
# ECR Module
################################################################################

module "ecr" {
  source = "terraform-aws-modules/ecr/aws"

  repository_name = local.ecr_name

  repository_read_write_access_arns = [data.aws_caller_identity.current.arn]
  create_lifecycle_policy           = true
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 10 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 10
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

  repository_force_delete = true

  tags = local.ecr_tags
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-kiu-1"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }

    two = {
      name = "node-group-kiu-2"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.20.0-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}

################################################################################
# RDS Aurora Module
################################################################################

module "aurora" {
    source = "terraform-aws-modules/rds-aurora/aws"

    name            = local.db_name
    engine          = "aurora-mysql"
    engine_version  = "8.0"
    master_username = "root"
    instances = {
    1 = {
        instance_class      = "db.r5.large"
        publicly_accessible = true
    }
    2 = {
        identifier     = "mysql-static-1"
        instance_class = "db.r5.large"
    }
    3 = {
        identifier     = "mysql-excluded-1"
        instance_class = "db.r5.large"
        promotion_tier = 15
    }
    }

    vpc_id               = module.vpc.vpc_id
    db_subnet_group_name = module.vpc.subnet_ids
    security_group_rules = {
    vpc_ingress = {
        cidr_blocks = module.vpc.private_subnets_cidr_blocks
    }
    kms_vpc_endpoint = {
        type                     = "egress"
        from_port                = 443
        to_port                  = 443
        source_security_group_id = module.vpc_endpoints.security_group_id
    }
    }

    apply_immediately   = true
    skip_final_snapshot = true

    create_db_cluster_parameter_group      = true
    db_cluster_parameter_group_name        = local.db_name
    db_cluster_parameter_group_family      = "aurora-mysql8.0"
    db_cluster_parameter_group_description = "${local.db_name} example cluster parameter group"
    db_cluster_parameter_group_parameters = [
    {
        name         = "connect_timeout"
        value        = 120
        apply_method = "immediate"
        }, {
        name         = "innodb_lock_wait_timeout"
        value        = 300
        apply_method = "immediate"
        }, {
        name         = "log_output"
        value        = "FILE"
        apply_method = "immediate"
        }, {
        name         = "max_allowed_packet"
        value        = "67108864"
        apply_method = "immediate"
        }, {
        name         = "aurora_parallel_query"
        value        = "OFF"
        apply_method = "pending-reboot"
        }, {
        name         = "binlog_format"
        value        = "ROW"
        apply_method = "pending-reboot"
        }, {
        name         = "log_bin_trust_function_creators"
        value        = 1
        apply_method = "immediate"
        }, {
        name         = "require_secure_transport"
        value        = "ON"
        apply_method = "immediate"
        }, {
        name         = "tls_version"
        value        = "TLSv1.2"
        apply_method = "pending-reboot"
    }
    ]

    create_db_parameter_group      = true
    db_parameter_group_name        = local.db_name
    db_parameter_group_family      = "aurora-mysql8.0"
    db_parameter_group_description = "${local.db_name} example DB parameter group"
    db_parameter_group_parameters = [
    {
        name         = "connect_timeout"
        value        = 60
        apply_method = "immediate"
        }, {
        name         = "general_log"
        value        = 0
        apply_method = "immediate"
        }, {
        name         = "innodb_lock_wait_timeout"
        value        = 300
        apply_method = "immediate"
        }, {
        name         = "log_output"
        value        = "FILE"
        apply_method = "pending-reboot"
        }, {
        name         = "long_query_time"
        value        = 5
        apply_method = "immediate"
        }, {
        name         = "max_connections"
        value        = 2000
        apply_method = "immediate"
        }, {
        name         = "slow_query_log"
        value        = 1
        apply_method = "immediate"
        }, {
        name         = "log_bin_trust_function_creators"
        value        = 1
        apply_method = "immediate"
    }
    ]

    enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

    create_db_cluster_activity_stream     = true
    db_cluster_activity_stream_kms_key_id = module.kms.key_id

    # https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/DBActivityStreams.Overview.html#DBActivityStreams.Overview.sync-mode
    db_cluster_activity_stream_mode = "async"

    tags = local.db_tags
}

module "kms" {
    source  = "terraform-aws-modules/kms/aws"
    version = "~> 2.0"

    deletion_window_in_days = 7
    description             = "KMS key for ${local.db_name} cluster activity stream."
    enable_key_rotation     = true
    is_enabled              = true
    key_usage               = "ENCRYPT_DECRYPT"

    aliases = [local.db_name]

    tags = local.db_tags
}
