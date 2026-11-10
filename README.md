

## Snippets

Starting points, not complete files. Names in `<...>` are yours to choose.

### `variables.tf`

```hcl
variable "name" {
  description = "Your short name, prefixes everything"
  type        = string
}

variable "region" {
  type = string
}
```

`terraform.tfvars` (commit it, the runner needs it too):

```hcl
name   = "<name>"
region = "<region>"
```

### `network.tf`

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
}

# + aws_internet_gateway, aws_route_table (0.0.0.0/0 -> gateway),
#   aws_route_table_association for each subnet
```

### `eks.tf`

```hcl
data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

# + aws_iam_role_policy_attachment: AmazonEKSClusterPolicy

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.public[*].id
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# + node role (trust ec2.amazonaws.com) with AmazonEKSWorkerNodePolicy,
#   AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.public[*].id
  instance_types  = ["t3.medium"]

  scaling_config {
    min_size     = 1
    desired_size = 2
    max_size     = 3
  }

  # depends_on: the node policy attachments and the route table associations
}
```

### `ecr.tf`

```hcl
resource "aws_ecr_repository" "hello" {
  name                 = "${var.name}/hello"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
}
```

### `github-oidc.tf`

```hcl
# Exists once per account, already there: look it up.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "service_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:<you>/service-code:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "gha_service" {
  name               = "${var.name}-gha-service"
  assume_role_policy = data.aws_iam_policy_document.service_trust.json
}

# + aws_iam_role_policy: ecr:GetAuthorizationToken on "*", push actions on aws_ecr_repository.hello.arn
# + the same for "${var.name}-gha-infra": sub = repo:<you>/infra-code:pull_request
#   and repo:<you>/infra-code:ref:refs/heads/main, AdministratorAccess attached

resource "aws_eks_access_entry" "gha_infra" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.gha_infra.arn
}

resource "aws_eks_access_policy_association" "gha_infra" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.gha_infra.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
```

### `k8s.tf`

```hcl
provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.region]
  }
}

resource "kubernetes_namespace_v1" "hello" {
  metadata {
    name = "hello"
  }
}

# Step 4, once the cluster exists:
resource "kubernetes_manifest" "deployment" {
  manifest   = yamldecode(file("${path.module}/k8s/deployment.yaml"))
  depends_on = [kubernetes_namespace_v1.hello]
}
```

### `outputs.tf`

```hcl
output "service_role_arn" {
  value = aws_iam_role.gha_service.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.hello.repository_url
}

# + infra_role_arn, and the update-kubeconfig command
```

### `k8s/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  namespace: hello
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
        - name: hello
          image: <ECR_REPOSITORY_URL>:1.0.0
          ports:
            - containerPort: 8080
```

### `.github/workflows/pr.yml`

```yaml
on:
  pull_request:
    branches: [main]

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v7
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - uses: hashicorp/setup-terraform@v4
      - run: terraform fmt -check -recursive
      # + terraform init, terraform validate, terraform plan
```

### `.github/workflows/main.yml`

```yaml
on:
  push:
    branches: [main]

# same job as pr.yml, then:
#   terraform apply -auto-approve
```
