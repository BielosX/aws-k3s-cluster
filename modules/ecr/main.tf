resource "aws_ecr_repository" "node-manager" {
  name = "node-manager"
  force_delete = true
  image_tag_mutability = "IMMUTABLE"
}