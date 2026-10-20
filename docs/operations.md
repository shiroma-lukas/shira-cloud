# Operations

## First-time setup (operator account)

```sh
cd envs/bootstrap && terraform init && terraform apply     # creates the state bucket
```

Keep `envs/bootstrap/terraform.tfstate` somewhere safe; it only tracks the state bucket.

## Hosted environment

```sh
cd envs/hosted
cp backend.hcl.example backend.hcl           # set the state bucket name
cp terraform.tfvars.example terraform.tfvars # one entry per customer cell
terraform init -backend-config=backend.hcl
terraform apply
```

Adding a customer is a new entry in `cells`; removing one destroys only that cell (its
database keeps a final snapshot while `deletion_protection` is on).

## Bringing a cell to life

**1. Fill the app secret** (never through Terraform, so the values stay out of state):

```sh
jq -n --arg id "$GITHUB_APP_ID" --rawfile key ./github-app.pem --arg anthropic "$ANTHROPIC_API_KEY" \
  '{github_app_id: $id, github_private_key: $key, anthropic_api_key: $anthropic}' > /tmp/app.json
aws secretsmanager put-secret-value --region sa-east-1 \
  --secret-id "shira/shira-<slug>/app" --secret-string file:///tmp/app.json
rm /tmp/app.json
```

**2. Upload config and context.** Hosts pull them every 5 minutes and restart their
dispatcher (after its current task) when anything changed.

```sh
aws s3 sync ./config  s3://<config_bucket>/config  --delete   # agents/, repos/
aws s3 sync ./context s3://<config_bucket>/context --delete   # roles/worker.md, ...
```

**3. Restart the fleet** once the secret is set, so dispatchers start with it:

```sh
aws autoscaling start-instance-refresh --region sa-east-1 --auto-scaling-group-name shira-<slug>-fleet
```

## Day to day

Open a shell on any host of the cell and use the `shira` CLI:

```sh
aws ssm start-session --region sa-east-1 --target <instance-id>
sudo shira submit --repo org/repo --goal "Fix ..."
sudo shira list
sudo shira show <task-id>
sudo shira answer <task-id> --text "..."
sudo shira kill on        # pause every agent in the cell
```

Logs: CloudWatch `/shira/<cell>/dispatcher`, `/egress`, and `/bootstrap`. The
`Shira/<cell>/EgressDenied` metric counts blocked connection attempts.

## Upgrading Shira

Change `shira_version` for the cell and apply. The launch template changes and the Auto
Scaling group replaces hosts gradually. A task running on a replaced host loses its lease
and is retried on another host.

## BYOC

1. The customer applies `modules/byoc-access` in their account with our account id and an
   agreed external id, and sends us the role ARN.
2. We copy `envs/byoc-example` to `envs/byoc-<customer>`, set its state key, role ARN,
   region, and CIDR, and apply.
3. Steps "Bringing a cell to life" apply unchanged, run with the customer's role.

The customer can cut us off at any time by deleting the role; the cell keeps running.

## Keeping costs down

Every option below is opt-in per environment or cell; module defaults stay on the robust choice.

| Option | Where | Effect | Trade-off |
|---|---|---|---|
| `nat_mode = "instance"` | network | Replaces the NAT gateway (~US$70/month fixed) with a `t4g.nano` doing NAT | One instance carries all egress; AWS auto-recovers it on host failure. Use `"gateway"` for paying customers |
| `fleet_spot = true` + `fleet_spot_instance_types` | cell | Sandbox hosts on Spot, typically 60-70% cheaper | A reclaimed host's task is retried on another host (lease expiry). More instance types mean fewer interruptions |
| `fleet_architecture = "arm64"` | cell | Graviton hosts, ~20% cheaper per vCPU | Instance types must be Graviton (`m7g`, `m6g`, `t4g`, ...); checked at plan time |
| `db_instance_class = "db.t4g.micro"` | cell | Smallest Postgres | Fine for test cells; not for real load |
| Destroy when idle | env | `terraform destroy` after a test session, `apply` before the next | Takes ~10 minutes to come back (RDS creation dominates) |

`envs/hosted/terraform.tfvars.example` uses all of them for the internal test cell.

## Known gaps (M1)

- Transcripts are uploaded to S3 by the sync timer, but the URIs recorded in the database
  still point at the host's disk. An S3 transcript store in the core will fix this.
- Dispatchers connect as the RDS master user. A least-privilege application role comes
  with the next migration round.
- Scaling in doesn't drain a host: its running task is retried elsewhere. A lifecycle hook
  that waits for the dispatcher to stop will fix this.
- No inbound endpoints yet: Slack intake (M2) will add a load balancer.
