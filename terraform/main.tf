
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.cluster_name
  cidr = "${var.vpc_cidr_prefix}.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["${var.vpc_cidr_prefix}.1.0/24", "${var.vpc_cidr_prefix}.2.0/24", "${var.vpc_cidr_prefix}.3.0/24"]
  public_subnets  = ["${var.vpc_cidr_prefix}.101.0/24", "${var.vpc_cidr_prefix}.102.0/24", "${var.vpc_cidr_prefix}.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "karpenter.sh/discovery"                    = var.cluster_name
    "kubernetes.io/role/internal-elb"           = 1
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb	" = 1
  }
}



module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.3"

  cluster_version                 = "1.29"
  cluster_name                    = var.cluster_name
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets
  enable_irsa                     = true

  cluster_addons = {
    # Note: https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html#fargate-gs-coredns
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }

  # Only need one node to get Karpenter up and running
  eks_managed_node_groups = {
    default = {
      desired_size = 3
      # iam_role_additional_policies = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
      instance_types = ["t3.large"]
      tags = {
        Owner = "default"
      }
      security_group_rules = {
        ingress_self_all = {
          description = "Node to node all ports/protocols"
          protocol    = "-1"
          from_port   = 0
          to_port     = 0
          type        = "ingress"
          cidr_blocks = ["0.0.0.0/0"]
        }
        egress_all = {
          description = "Node all egress"
          protocol    = "-1"
          from_port   = 0
          to_port     = 0
          type        = "egress"
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
    }
  }

  cluster_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  # manage_aws_auth_configmap = true
  # create_aws_auth_configmap = true 

  # aws_auth_roles = [
  #   {
  #     rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Admin"
  #     username = var.username
  #     groups   = ["system:masters"]
  #   },
  # ]
  access_entries = {
    user = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.username}"

      policy_associations = {
        single = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    role = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Admin"

      policy_associations = {
        single = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # tags = {
  #   "karpenter.sh/discovery" = var.cluster_name
  # }
}


module "observability" {
  source                  = "./observability"
  adot_namespace          = "opentelemetry-operator-system"
  cluster_name            = var.cluster_name
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  region                  = var.region
  subnet_ids              = module.vpc.private_subnets
  security_group_ids      = [module.eks.node_security_group_id, module.eks.cluster_primary_security_group_id]
  depends_on = [
    module.eks
  ]
}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${var.cluster_name}"
  provider_url                  = replace(module.eks.oidc_provider, "https://", "")
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_driver_version
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
  depends_on = [module.eks]
}

# resource "aws_ecr_repository" "app-hello" {
#   name                 = "grafana-demo-hello"
#   image_tag_mutability = "MUTABLE"
#   force_delete         = true
#   image_scanning_configuration {
#     scan_on_push = false
#   }
# }
# resource "aws_ecr_repository" "app-world" {
#   name                 = "grafana-demo-world"
#   image_tag_mutability = "MUTABLE"
#   force_delete         = true
#   image_scanning_configuration {
#     scan_on_push = false
#   }
# }
