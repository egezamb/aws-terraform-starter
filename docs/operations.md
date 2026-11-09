# Operating the starter

## Before deploying

Run `make check` and `make security`. These checks do not use an AWS account.
For a real deployment, verify the intended AWS account with `aws sts get-caller-identity`,
copy `terraform.tfvars.example` to `terraform.tfvars`, then review `terraform plan`.
Keep state, variable files and saved plans private. Commit the provider lock file.

| Input | Default | When to change it |
| --- | --- | --- |
| `allowed_http_cidrs` | `["0.0.0.0/0"]` | Limit the demo to your IPv4 network, or use `[]` to close HTTP. |
| `allowed_ssh_cidr` | `null` | Open SSH only to your IPv4 CIDR. |
| `ssh_key_name` | `null` | Select an existing key pair in the deployment region for SSH. |
| `root_volume_size_gib` | `8` | Increase disk space; storage is billed. |
| `asset_version_retention_days` | `30` | Keep overwritten/deleted asset versions longer or shorter. |
| `flow_log_retention_days` | `30` | Change how long network logs are retained. |
| `allow_bucket_force_destroy` | `false` | Opt in only when all bucket contents are disposable. |

Session Manager is the default shell access path. It does not need an SSH key.
An SSH key pair is not created by this project; keep its private key outside the repository.

## Check a deployment

After applying, copy the URL from `terraform output -raw web_url`. An EC2 instance
being running does not mean cloud-init has finished installing Apache.

For a shell, copy the command from `terraform output -raw session_manager_command`.
The AWS CLI Session Manager plugin must be installed, and your caller identity must
be allowed to start a session. The instance role lets the agent register; it does
not grant your user permission to connect.

Inside the instance, inspect these when the web page is unavailable:

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo systemctl status httpd
curl --fail http://localhost/
```

If localhost works, check `allowed_http_cidrs`, your current public IP, the public
address and the internet-gateway route. If installation failed, inspect the dnf
error and network connectivity. Bootstrap stops on package errors and does not
pretend that Apache started.

Use `terraform output -raw flow_logs_bucket` to find the log bucket. List its
`AWSLogs/` prefix with the AWS CLI in your selected region. Delivery is asynchronous;
a missing object immediately after deployment does not establish that no traffic occurred.

## Clean up deliberately

Review `terraform plan -destroy` before `terraform destroy`. Nonempty buckets are
protected by default. An unsuccessful destroy can still have removed other resources;
inspect state and the next plan instead of assuming it rolled back.

For disposable data only, set `allow_bucket_force_destroy = true` in your private
variable file and run `terraform apply` first so that the setting reaches state.
Then review the destroy plan and destroy. This deletes assets, historical versions
and flow logs; lifecycle retention is not a backup against explicit deletion.

To retain data, copy the required objects and historical versions to a destination
you control before emptying buckets. A simple `aws s3 sync` copies current objects,
not every historical version. Keep the state until cleanup is complete; deleting
state does not delete resources or stop charges.
