# Lets Shira Cloud deploy and operate a cell in the customer's account. The customer
# applies this module themselves, reviews the permissions, and can revoke access at any
# time by deleting the role.
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "operator" {
  name                 = var.role_name
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.operator_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.external_id } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.managed_policy_arns)
  role       = aws_iam_role.operator.name
  policy_arn = each.value
}

# PowerUserAccess excludes IAM. A cell needs a few roles (fleet, flow logs), so allow IAM
# only on resources named shira-* in this account.
resource "aws_iam_role_policy" "cell_iam" {
  role = aws_iam_role.operator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UpdateAssumeRolePolicy",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
        "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:ListInstanceProfilesForRole",
        "iam:PassRole",
      ]
      Resource = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/shira-*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/shira-*",
      ]
    }]
  })
}
