resource "aws_ecr_repository" "hello" {
  name                 = "${var.project_name}/hello"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
}