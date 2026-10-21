# AWS Terraform Starter — VPC + EC2 + S3

![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?style=flat&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-Provider%205.x-FF9900?style=flat&logo=amazon-aws&logoColor=white)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?style=flat&logo=github-actions&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)

A clean, **learning-focused** starter for deploying a basic but complete **AWS environment** with **Terraform**. Designed to be readable, well-commented, and a real reference for anyone (myself included) learning Infrastructure-as-Code.

It applies the same practices real DevOps teams rely on — version control, CI on every push, secure-by-default resources, consistent tagging — to a deliberately small, single-AZ footprint. It's a **reference and learning base, not a production blueprint**: for real workloads you'd add private subnets + NAT, remote state with locking, multi-AZ, and a load balancer (see [Next Steps](#next-steps--possible-extensions)).

> Clone it, run `terraform apply`, and you have a live VPC + web server + secure S3 bucket in ~2 minutes. If it saves you time, a ⭐ helps others find it.

---

## What This Deploys

```
                          Internet
                              │
                              ▼
                  ┌───────────────────────┐
                  │   Internet Gateway    │
                  └───────────┬───────────┘
                              │
              ┌───────────────┴───────────────┐
              │  VPC  (10.0.0.0/16)           │
              │                               │
              │   ┌───────────────────────┐   │
              │   │ Public Subnet         │   │
              │   │ (10.0.1.0/24)         │   │
              │   │                       │   │
              │   │   ┌───────────────┐   │   │
              │   │   │ EC2 (t3.micro)│   │   │
              │   │   │ Amazon Linux  │   │   │
              │   │   │ + Apache      │   │   │
              │   │   └───────────────┘   │   │
              │   └───────────────────────┘   │
              └───────────────────────────────┘

   ┌────────────────────────────────────────────────┐
   │  S3 Bucket — Versioned, Encrypted, Private     │
   └────────────────────────────────────────────────┘
```

| Resource | What it does |
|----------|--------------|
| **VPC** | Custom VPC with DNS support enabled, `10.0.0.0/16` |
| **Internet Gateway** | Provides internet access to the VPC |
| **Public Subnet** | `10.0.1.0/24` in the first AZ, auto-assigns public IPs |
| **Route Table** | Routes `0.0.0.0/0` traffic to the IGW |
| **Security Group** | Allows HTTP (80) from anywhere; SSH (22) only from `allowed_ssh_cidr`, and not at all when it is unset |
| **EC2 Instance** | `t3.micro` (free-tier eligible) running Apache via `user_data`, IMDSv2 enforced |
| **S3 Bucket** | Versioning enabled, AES-256 encryption, all public access blocked |
| **VPC Flow Logs** | Every accepted and rejected connection, to a private S3 bucket; deleted after 30 days |

---

## Why I Built This

I am a 3rd-year Software Development student moving deeper into cloud and DevOps. I had already deployed AWS resources manually via the Console as a freelancer, but I wanted to learn **Terraform** properly — not just `terraform apply` from a tutorial, but writing structured code from scratch.

This repo is the result of that learning, made public so anyone else starting Terraform can clone, read, and run it.

---

## Tech Stack

- **Terraform** `>= 1.5.0`
- **AWS Provider** `~> 5.0` (Hashicorp official)
- **GitHub Actions** for CI (fmt + validate + `terraform test` + trivy security scan on every push/PR)
- **Amazon Linux 2023** (the current AMI, read from the public SSM parameter AWS maintains)

---

## Project Structure

```
aws-terraform-starter/
├── providers.tf              # Terraform + AWS provider configuration
├── variables.tf              # All input variables with descriptions and validation
├── vpc.tf                    # VPC, IGW, subnet, route table
├── ec2.tf                    # EC2 + security group + AMI (SSM parameter) + user_data
├── s3.tf                     # S3 bucket with versioning + encryption + access block
├── flow_logs.tf              # VPC flow logs to a private S3 bucket that expires them
├── outputs.tf                # Useful outputs (IPs, IDs, URLs)
├── terraform.tfvars.example  # Example variables file (copy to terraform.tfvars)
├── tests/plan.tftest.hcl     # Plan-only tests with mocked providers (terraform test)
├── .gitignore                # Excludes state files, .terraform/, secrets
└── .github/
    └── workflows/
        └── terraform.yml     # CI: fmt + init + validate + test, and a trivy security scan
```

---

## Quick Start

### Prerequisites
- AWS account with programmatic credentials configured (`aws configure` or environment variables)
- Terraform `>= 1.5` installed (`brew install terraform` on macOS)

### Deploy

```bash
git clone https://github.com/egezamb/aws-terraform-starter.git
cd aws-terraform-starter

cp terraform.tfvars.example terraform.tfvars
# Open terraform.tfvars and set `allowed_ssh_cidr` to your IP (e.g. "1.2.3.4/32")

terraform init
terraform plan
terraform apply
```

Changing `vpc_cidr` or `public_subnet_cidr`? The VPC must be /16 to /28 and the subnet must lie inside it. `terraform plan` checks both, so a wrong pair fails before anything is created.

After ~2 minutes, Terraform will output the EC2 public DNS. Open `http://<public-dns>` and you'll see the deployed web server.

### Destroy

```bash
terraform destroy
```

Always destroy when done: once the credits or the free months run out, a running instance is billed.

---

## CI/CD

Every push and pull request triggers a GitHub Actions workflow that:

1. Runs `terraform fmt -check -recursive` (fails if code isn't formatted)
2. Runs `terraform init -backend=false`
3. Runs `terraform validate`, then `terraform test`: plan-only tests with mocked providers (`tests/plan.tftest.hcl`) that pin the secure defaults (SSH closed unless asked for, encrypted disk, IMDSv2, a private, versioned, TLS-only bucket). The result goes to the job summary.
4. Scans the code with `trivy config` and fails on any new HIGH or CRITICAL finding. Findings accepted on purpose carry a `trivy:ignore` comment with the reason on the resource itself.

The workflow has a read-only token and every action is pinned to a commit SHA. Dependabot proposes updates for the actions and the Terraform providers, and `.terraform.lock.hcl` is committed so CI uses the same provider builds as your machine.

This catches formatting and syntax issues before code lands in `main` — exactly the kind of guardrails real DevOps teams set up.

See [`.github/workflows/terraform.yml`](./.github/workflows/terraform.yml).

---

## Security Notes

- **State files** (`*.tfstate`) and **`terraform.tfvars`** are gitignored — they can contain secrets and resource IDs.
- **`allowed_ssh_cidr`** is unset by default, so no SSH port is opened. Set it to your IP (`"1.2.3.4/32"`) in `terraform.tfvars` to SSH in; `0.0.0.0/0` is rejected.
- **S3 bucket** has **all public access blocked**, **versioning enabled**, **AES-256 server-side encryption**, and a policy that **denies any request without TLS**. Old object versions expire after 30 days.
- **VPC flow logs** record every accepted and rejected connection in a private, encrypted S3 bucket, so blocked scans and unexpected outbound traffic leave a trace. They go to S3 because a CloudWatch destination needs an IAM role; logs are deleted after `flow_log_retention_days` (30).
- **EC2 metadata service** is locked to **IMDSv2 only** to prevent SSRF attacks.
- **EC2 root volume** is **encrypted** (gp3), and the security group allows **outbound HTTP and HTTPS only**.
- **The VPC's default security group** has **no rules**, so anything launched into it by mistake gets no traffic.
- **The AMI** is the standard Amazon Linux 2023 image, read from AWS's public SSM parameter for the instance type's architecture.

---

## Cost Estimate

A few dollars a month if left running. Who pays depends on when the AWS account was opened:

- **Opened on or after 15 July 2025:** the Free Tier is credits — $100 at sign-up, up to $200 with
  the onboarding tasks — on a Free plan that lasts up to 6 months. This stack's charges come off
  the credits.
- **Opened before 15 July 2025:** the legacy 12-month Free Tier, which includes 750 hours a month
  of `t2.micro`/`t3.micro`.
- **Billed in full:** roughly $12–14 a month in `eu-central-1`. Most of it is the instance
  (`t3.micro`, about $9). The instance's public IPv4 address is billed by the hour (about $3.60)
  and the 8 GB gp3 root volume adds under $1.

The VPC, subnet, internet gateway and route table are free. An empty S3 bucket costs nothing. Flow logs are billed per GB delivered to S3; a quiet test stack writes a few MB a month.

Run `terraform destroy` when you are done testing.

---

## What This Project Demonstrates

- Writing structured Terraform code (providers, variables, resources, outputs)
- Using `data` sources to look up dynamic values (latest AMI, availability zones)
- Resource tagging strategy via `default_tags`
- Variable validation with `validation` blocks
- Secure-by-default AWS configurations (IMDSv2, S3 public access block, encryption)
- Setting up CI for IaC (fmt + init + validate in GitHub Actions)
- Proper `.gitignore` hygiene for Terraform projects
- `user_data` bootstrapping for EC2 instances

---

## Next Steps / Possible Extensions

- Add a private subnet + NAT Gateway
- Add an RDS instance in the private subnet
- Use Terraform modules to refactor (`modules/vpc`, `modules/ec2`)
- Add remote state via S3 + DynamoDB locking
- Add Application Load Balancer in front of the EC2 instance
- Add CloudWatch logging and a basic dashboard

These are exactly the kinds of extensions I want to build next as my Terraform skills mature.

---

## Author

**Ege Zambelli** — 3rd-year Software Development student at WSB Merito Wrocław, focusing on cloud engineering and DevOps.

- GitHub: [@egezamb](https://github.com/egezamb)
- Related projects:
  - [calculator-pytest-cicd](https://github.com/egezamb/calculator-pytest-cicd) — Python + pytest + GitHub Actions CI/CD
  - [git-cicd-project](https://github.com/egezamb/git-cicd-project) — Git workflows + automation
  - [sbatools](https://github.com/egezamb/sbatools) — Git Flow + release automation
  - [ege-portfolio-2025](https://github.com/egezamb/ege-portfolio-2025) — Personal portfolio (Next.js)

---

## License

MIT — see [LICENSE](./LICENSE) if present, otherwise free to use, modify, and learn from.
