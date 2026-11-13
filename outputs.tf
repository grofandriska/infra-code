output "service_role_arn" {
  value = aws_iam_role.gha_service.arn
}

output "infra_role_arn" {
  value = aws_iam_role.gha_infra.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.hello.repository_url
}