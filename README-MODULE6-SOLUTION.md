# ITMO 463 Module 6 Assessment - Completed Template

This folder has the missing Module 6 code filled in for DynamoDB + SQS + SNS + S3.

## Before `terraform apply` (required personal values)

1. In `install-env.sh` and `install-be-env.sh`, replace:
   - `YOUR_GITHUB_USERNAME`
   - `YOUR_REPOSITORY`
   - `YOUR_MODULE6_PATH`
   with your actual GitHub SSH repo and the folder containing these Module 6 files.
2. In `terraform.tfvars`, verify your Module 4 AWS values:
   - `imageid`
   - `key-name`
   - region
   - any names you previously used.
3. S3 bucket names are globally unique. The supplied names were changed to likely-unique names, but if AWS says a bucket already exists, change both bucket names in `terraform.tfvars`.
4. `app.js`, `app.py`, `provider.tf`, and `terraform.tfvars` currently use `us-east-1`. If your class environment uses another region, change all of them to the same region.

## What was completed

- DynamoDB table variable: `dynamodb-name = "company"`
- DynamoDB table `company` with String hash key `RecordNumber`
- IAM inline role policy named exactly `dynamodb_fullaccess_policy`
- Node AWS SDK v3 DynamoDB dependency added
- `app.js` imports `ListTablesCommand`, `DynamoDBClient`, `ScanCommand`, `PutItemCommand`, and `QueryCommand`
- Uploads insert a DynamoDB item and enqueue its RecordNumber in SQS
- Legacy RDS/MySQL app dependencies removed
- `app.py` lists DynamoDB tables and reads records from DynamoDB
- backend generates grayscale image, writes it to finished S3, creates presigned URL
- backend updates `RAWS3URL` to `done`
- backend updates `FINSIHEDS3URL` to the `https://...` presigned URL
- exact course typo `FINSIHEDS3URL` is intentionally preserved because the provided autograder checks that spelling
- resources use `Name = module-06` where tag support applies

## Deploy

From your Vagrant Ubuntu environment, in this Terraform directory:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

After apply, use the `url` Terraform output in a browser.

## Upload the 5 required images

Upload **5 different image files** through the form. Each upload should create one DynamoDB item and one SQS message.

Confirm the SNS email subscription if you want to receive the generated link by email.

## Process all 5 SQS messages quickly

The systemd timer only runs every 8 minutes and `app.py` processes one message per invocation. Instead of waiting ~40 minutes, SSH to the backend and run the backend script once for each queued image:

```bash
sudo python3 /usr/local/bin/app.py
sudo python3 /usr/local/bin/app.py
sudo python3 /usr/local/bin/app.py
sudo python3 /usr/local/bin/app.py
sudo python3 /usr/local/bin/app.py
```

If the timer already processed some images, later invocations may simply say the queue is empty; that is fine.

You can also inspect the timer/service:

```bash
sudo systemctl status checkqueue.timer
sudo systemctl status checkqueue.service
sudo journalctl -u checkqueue.service --no-pager -n 100
```

## Run the supplied autograder

Back in the Vagrant environment where your AWS credentials are configured:

```bash
python3 module-06-test.py
```

The five grading checks are:

1. DynamoDB table named `company`
2. At least 5 items in it
3. At least one `RAWS3URL` value equals `done`
4. At least one `FINSIHEDS3URL` contains `https://`
5. IAM role `project_role` contains inline policy `dynamodb_fullaccess_policy`

The expected target is **10/10**. Submit the generated `module-06-results.txt` file.

## Important

Do not rename `FINSIHEDS3URL` to a correctly spelled English name. The course test uses the misspelled form.


## Current lab values (updated Sep 27, 2026)

- Region: `us-east-1`
- AMI: `ami-0d6706b99f85f1a04` (Ubuntu 22.04 image verified in us-east-1)
- EC2 key pair: `module-05-key`
- Current Terraform-managed security group: `sg-07e6e7579338a74ac`
- GitHub repository: `https://github.com/badreddinetayeb7-crypto/module-06-lab.git`
- Repository files are expected at the repository root (`/home/ubuntu/module-06-lab` after clone).
- Terraform CLI credentials path in this Coursera container: `/home/coder/.aws/credentials`
- S3 path-style access is enabled in `provider.tf` for this lab container.

Do not commit AWS credentials, Terraform state files, the Terraform binary, the AWS CLI installer, or private key files to GitHub.
