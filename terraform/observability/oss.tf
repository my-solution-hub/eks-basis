
resource "aws_grafana_workspace" "example" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana_assume.arn
  name = var.cluster_name
}

resource "aws_iam_role" "grafana_assume" {
  name = "${var.cluster_name}-grafana-assume"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "grafana.amazonaws.com"
        }
      },
    ]
  })

}

resource "aws_iam_role_policy_attachment" "assume" {
  role       = aws_iam_role.grafana_assume.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_cloudwatch_log_group" "prom_log" {
  name = "${var.cluster_name}_prom_log"
}

resource "aws_prometheus_workspace" "prom" {
  alias = var.cluster_name
  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.prom_log.arn}:*"
  }
}
