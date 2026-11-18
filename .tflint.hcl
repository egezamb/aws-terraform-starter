# tflint: Terraform's own recommended rules, and the AWS ruleset, which knows
# what the AWS API accepts (instance types, for example) before an apply finds out.
config {
  call_module_type = "none"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
