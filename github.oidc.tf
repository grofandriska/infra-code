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
      values   = ["repo:grofandriska@64146340/service-code@1452916862:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "gha_service" {
  name               = "${var.project_name}-gha-service"
  assume_role_policy = data.aws_iam_policy_document.service_trust.json
}



data "aws_iam_policy_document" "infra_trust" {
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
      values = [
        "repo:grofandriska@64146340/infra-code@1452916127:pull_request",
      "repo:grofandriska@64146340/infra-code@1452916127:ref:refs/heads/main", ]
    }
  }
}

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

resource "aws_iam_role" "gha_infra" {
  name               = "${var.project_name}-gha-infra"
  assume_role_policy = data.aws_iam_policy_document.infra_trust.json
}

resource "aws_iam_role_policy_attachment" "gha_infra" {
  role       = aws_iam_role.gha_infra.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "gha_service_ecr" {
  name = "ecr-push"
  role = aws_iam_role.gha_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = aws_ecr_repository.hello.arn
      },
    ]
  })
}