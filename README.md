# Shira Cloud

AWS infrastructure for running [Shira](https://github.com/shiroma-lukas/shira) as a managed
service, hosted by us or in a customer's own AWS account (BYOC). Proprietary; the Shira
core is open source under Apache-2.0.

## Shape

A **cell** is one customer's complete Shira deployment: Postgres, a sandbox fleet,
buckets, a secret, IAM, and logs. Cells never share data.

```
                      VPC (sa-east-1, hosted: shared by cells; BYOC: customer's own)
 ┌───────────────────────────────────────────────────────────────────────────────┐
 │ public subnets: NAT gateways only                                             │
 │ private subnets, per cell:                                                    │
 │   RDS Postgres 17 ◄── fleet only                                              │
 │   EC2 Auto Scaling group, each host:                                          │
 │     dispatcher ──docker──► gVisor sandbox ×N ──► egress proxy ──► NAT ──► out │
 │                            (internal network,    (per-sandbox allowlist,      │
 │                             no route out)         no private addresses)       │
 └───────────────────────────────────────────────────────────────────────────────┘
   S3: <cell>-config (agents, repos, context)    <cell>-transcripts (expire 90 days)
   Secrets Manager: shira/<cell>/app             CloudWatch: /shira/<cell>/*
```

- **Hosts:** Ubuntu 24.04, Docker with gVisor (`runsc`), the egress proxy, and one dispatcher.
  Dispatchers on many hosts share the queue safely (Postgres `SKIP LOCKED`).
- **No inbound access:** no ports open, no SSH. Operators use SSM Session Manager.
- **Containers can't reach the host's credentials:** IMDSv2 with hop limit 1, and the proxy
  refuses link-local addresses.
- **Secrets never enter Terraform state:** RDS manages its own password; the app secret is
  created empty and filled out of band.
- **VPC flow logs** record every connection independently of the hosts.

## Layout

| Path | What |
|---|---|
| `modules/network` | VPC, subnets, NAT, S3 endpoint, flow logs |
| `modules/cell` | One customer: RDS, buckets, secret, logs, and the fleet |
| `modules/sandbox-fleet` | Launch template, Auto Scaling group, IAM, host bootstrap |
| `modules/byoc-access` | Role a BYOC customer creates so we can operate their cell |
| `envs/bootstrap` | Terraform state bucket (once per operator account) |
| `envs/hosted` | Our hosted environment in sa-east-1: shared VPC, `for_each` cells |
| `envs/byoc-example` | A cell in a customer account, through their operator role |

Operating it: [docs/operations.md](docs/operations.md).

The code uses only features shared by Terraform ≥ 1.11 and OpenTofu ≥ 1.11 (ephemeral resources and
write-only arguments, which keep generated passwords out of state), so either works.
