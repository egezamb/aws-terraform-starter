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
| **Security Group** | Allows HTTP (80) from anywhere, SSH (22) from configurable CIDR |
| **EC2 Instance** | `t3.micro` (free-tier eligible) running Apache via `user_data`, IMDSv2 enforced |
| **S3 Bucket** | Versioning enabled, AES-256 encryption, all public access blocked |

---

## Why I Built This

I am a 3rd-year Software Development student moving deeper into cloud and DevOps. I had already deployed AWS resources manually via the Console as a freelancer, but I wanted to learn **Terraform** properly — not just `terraform apply` from a tutorial, but writing structured code from scratch.

This repo is the result of that learning, made public so anyone else starting Terraform can clone, read, and run it.

---

## Tech Stack

- **Terraform** `>= 1.5.0`
- **AWS Provider** `~> 5.0` (Hashicorp official)
- **GitHub Actions** for CI (fmt + validate on every push/PR)
- **Amazon Linux 2023** (latest AMI auto-selected via `data` source)

---

## Project Structure

```
aws-terraform-starter/
├── providers.tf              # Terraform + AWS provider configuration
├── variables.tf              # All input variables with descriptions and validation
├── vpc.tf                    # VPC, IGW, subnet, route table
├── ec2.tf                    # EC2 + security group + AMI lookup + user_data
├── s3.tf                     # S3 bucket with versioning + encryption + access block
├── outputs.tf                # Useful outputs (IPs, IDs, URLs)
├── terraform.tfvars.example  # Example variables file (copy to terraform.tfvars)
├── .gitignore                # Excludes state files, .terraform/, secrets
└── .github/
    └── workflows/
        └── terraform.yml     # CI: fmt check + init + validate on every push
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

After ~2 minutes, Terraform will output the EC2 public DNS. Open `http://<public-dns>` and you'll see the deployed web server.

### Destroy

```bash
terraform destroy
```

Always destroy when done — even free-tier instances accumulate small charges after the 12-month limit.

---

## CI/CD

Every push and pull request triggers a GitHub Actions workflow that:

1. Runs `terraform fmt -check -recursive` (fails if code isn't formatted)
2. Runs `terraform init -backend=false`
3. Runs `terraform validate`
4. Posts a summary comment on pull requests

This catches formatting and syntax issues before code lands in `main` — exactly the kind of guardrails real DevOps teams set up.

See [`.github/workflows/terraform.yml`](./.github/workflows/terraform.yml).

---

## Security Notes

- **State files** (`*.tfstate`) and **`terraform.tfvars`** are gitignored — they can contain secrets and resource IDs.
- **`allowed_ssh_cidr`** defaults to `0.0.0.0/0` so the example works out of the box, but you should always restrict this to your IP via `terraform.tfvars`.
- **S3 bucket** has **all public access blocked**, **versioning enabled**, and **AES-256 server-side encryption** — secure-by-default.
- **EC2 metadata service** is locked to **IMDSv2 only** to prevent SSRF attacks.

---

## Cost Estimate

Roughly **free** if you stay within the AWS Free Tier:
- `t3.micro` EC2 — 750 hours/month free for 12 months
- VPC / Subnet / IGW / Route Table — free
- S3 bucket (empty) — free
- Data transfer (light testing) — free under 1 GB out per month

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
