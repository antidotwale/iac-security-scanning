# iac-security-scanning

Personal lab on my own GitHub account. The company and scenario are fictional. Nothing here is client or employer work. No AWS account or credentials were used: the Terraform was only validated and scanned, and it has never been applied.

## Scenario

A small startup (fictional) hands over its first Terraform draft: a storage bucket, a web server, a security group, an IAM policy and a log group. The task is to scan it, understand what the scanners are saying, fix it, and put a gate in CI so the weak version can never reach main.

Two versions live side by side:

- `terraform/initial` is the first draft.
- `terraform/reviewed` is the same infrastructure after fixes.

Tools: Terraform 1.17.0 with the AWS provider constrained to `~> 6.0` (exact version in the lock files), Checkov 3.4.5 and Trivy 0.76.1.

## Results

| Config | Checkov passed | Checkov failed | Checkov skipped | Trivy HIGH and CRITICAL |
|---|---|---|---|---|
| initial | 11 | 29 | 0 | 9 (1 critical, 8 high) |
| reviewed | 65 | 0 | 5 | 0 |

`terraform validate` passes on both.

## What the first draft got wrong

- **Bucket:** a policy allowing any principal to read objects, no public access block, no versioning, no access logging, no customer managed key.
- **Network:** SSH open to the whole internet and unrestricted egress.
- **IAM:** a policy allowing every action on every resource.
- **Instance:** metadata service not requiring tokens, unencrypted root volume, a public IP, no instance role.
- **Logs:** no retention period and no encryption key.

## What changed in the reviewed version

- Public access block, versioning, KMS encryption, access logging and lifecycle rules on the bucket, and a policy that only denies insecure transport.
- SSH restricted to an admin range, HTTPS in from the internet kept on purpose for a public web tier, and egress limited to the S3 prefix list.
- An IAM policy scoped to the one bucket and the one key.
- An instance role, token required metadata, an encrypted root volume and no public IP.
- Log retention of 365 days with a key whose policy allows the logs service.

## Where the two scanners disagreed

On the first draft, Checkov raised 29 findings and Trivy 9. Their rule sets overlap but do not match, which is why I ran both.

On the reviewed version, Checkov passed an egress rule open to the internet on port 443 and Trivy flagged it as AWS-0104 (critical). Trivy was right for this instance, which only needs S3, so I changed the rule to allow only the S3 prefix list.

## Accepted risks

Every accepted risk is written next to the resource with its reason, not hidden in a global ignore.

- Checkov skips on both buckets: no event notifications (static assets, nothing consumes events) and no cross region replication (single region recovery accepted to avoid doubling storage cost).
- Checkov skip and Trivy ignore (AWS-0132) on the log bucket: S3 server access log delivery does not support SSE-KMS, so AES256 is used.

## A bug neither scanner caught

The first reviewed draft encrypted the bucket with a customer managed key, but the deploy policy gave the role no permission to use that key. Both scanners passed it. Applied, every object read would have failed with access denied. I found it by reading the policy against the bucket settings, then added the two KMS permissions. Because this lab never applied anything, that interaction is reasoned and not tested in AWS.

## CI

`.github/workflows/iac.yml` runs on every push and pull request to main, once per Terraform version.

- `reviewed` is gated. The Checkov gate fails on any failed check and the Trivy gate fails on any HIGH or CRITICAL. Both gates run even if the first fails, so a red job shows both results.
- `initial` is report only, so main stays green while the weak version still exists for comparison.
- Trivy is installed as a binary with a checksum check, Checkov is pinned in a virtual environment, every Action is pinned to a commit SHA and the token is read only.
- Each run writes a count table to the run summary and keeps the JSON reports as an artifact.
- `terraform validate` is run locally, not in CI.

**Proof the gates can fail.** On a throwaway pull request I turned the gate on for the initial config. Both gate steps failed (Checkov: 29 failed checks, Trivy: 8 high and 1 critical) while the reviewed job stayed green (evidence 05). The pull request was closed without merging.

## Limits of this lab

- Nothing was applied, so runtime behaviour in AWS is untested.
- Scanners read configuration. They do not prove a design is right, as the KMS permission bug above shows.
- Results depend on the Checkov and Trivy rule sets at the versions above and will change as the rules change.
- One small configuration, not a real estate of modules, remote state or multiple environments.

## Reproduce

    cd terraform/reviewed
    terraform init -backend=false && terraform validate
    cd ../..
    checkov -d terraform/reviewed --framework terraform --compact --quiet
    trivy config --severity HIGH,CRITICAL terraform/reviewed

Run the same commands in `terraform/initial` to see the findings. Do not run `terraform plan` or `apply`.

## Evidence

| File | What it shows |
|---|---|
| evidence/01-checkov-initial.txt | Checkov on the first draft, 29 failed checks |
| evidence/02-checkov-reviewed.txt | Checkov on the reviewed version, 0 failed, 5 skipped |
| evidence/03-trivy-initial.txt | Trivy on the first draft, 9 findings |
| evidence/04-trivy-reviewed.txt | Trivy on the reviewed version, 0 findings |
| evidence/05-gate-proof-red-run.txt | CI log of both gates failing when the initial config was gated |
