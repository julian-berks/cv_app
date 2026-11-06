# CV App

A web page about Julian's CV. It has a home page, a chat tool for asking questions about the CV, and an About page that shows the project's architecture documentation. Answers come from an Amazon Bedrock Knowledge Base and model. The app is a FastAPI service running in a Docker container on AWS Lambda, served at `https://cv.julianberks.com` through CloudFront.

See [Container/docs/architecture.md](Container/docs/architecture.md) for the AWS architecture diagram and a full component breakdown.

## How it works

1. The browser loads the Vue 3 page from `/`. It opens on the home page, and a menu switches between **Home**, **Ask about my CV** and **About this project**.
2. In the chat view, each question is sent to `POST /ask`.
3. The backend retrieves matching CV content from the Bedrock Knowledge Base.
4. A Bedrock model answers using only that content, and the answer appears in the chat.
5. The About page fetches `/architecture.md` and renders it in the browser, including the diagrams.

Each question is answered on its own; earlier messages in the chat aren't sent to the model.

## Project structure

| File | Purpose |
| --- | --- |
| `Container/app.py` | FastAPI app, Bedrock calls and the Lambda handler (via Mangum) |
| `Container/static/` | Page layout, styles and Vue 3 app |
| `Container/requirements.txt` | Python dependencies |
| `Container/Dockerfile` | Lambda container image definition |
| `Container/push` | Builds and pushes the Lambda image to ECR; Terraform runs it when container files change |
| `rag_data/` | Source documents uploaded to the Bedrock Knowledge Base |
| `terraform/` | ECR, Lambda, S3, Bedrock, DynamoDB, CloudFront, ACM and WAF infrastructure |
| `Container/docs/architecture.md` | Architecture diagram and component documentation |

Vue 3 is loaded from the unpkg CDN, so there's no front-end build step. The About page also loads `marked`, `DOMPurify` and `mermaid` from unpkg, only when it's first opened, so it needs internet access.

## Routes

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/` | Home page, with the chat tool and project documentation behind the menu |
| `GET` | `/architecture.md` | Architecture documentation shown on the About page |
| `POST` | `/ask` | Body `{"question": "..."}` returns `{"answer": "..."}` |
| `GET` | `/s3` | Fixed test question about S3 experience |
| `GET` | `/static/*` | Page assets |

`/ask` rejects blank questions and questions over 1000 characters with a `422`, and returns a `502` if Bedrock fails.

Each IP address can ask at most 10 questions a minute (`ask_rate_limit_per_minute`). Further questions get a `429` with a friendly message until the minute rolls over. The counters live in a DynamoDB table (`<name>-rate-limits`) with a short TTL, and the check fails open: if the counter can't be reached, the question is still answered. WAF adds a separate flood limit of 100 requests of any kind per IP in 5 minutes, because the Free plan only supports plain per-IP limits over 5 minutes.

When `ALLOWED_ORIGIN` is set (Terraform sets it to `https://<domain_name>`), `/ask` also returns a `403` unless the request carries a matching `Origin` header and, if present, `Sec-Fetch-Site: same-origin`. Browsers add these automatically when the page asks a question. This stops other websites and simple scripts from calling `/ask`, but anyone can still send the headers by hand, so it isn't authentication.

Through CloudFront, POST requests must include an `x-amz-content-sha256` header containing the SHA-256 hex digest of the request body, otherwise CloudFront returns a `403`. The page does this automatically. From the command line, send the origin header as well:

```sh
body='{"question":"Hello"}'
curl -X POST https://cv.julianberks.com/ask \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://cv.julianberks.com' \
  -H "x-amz-content-sha256: $(printf '%s' "$body" | shasum -a 256 | cut -d' ' -f1)" \
  -d "$body"
```

## Configuration

| Environment variable | Default | Description |
| --- | --- | --- |
| `KNOWLEDGE_BASE_ID` | none (required) | Bedrock Knowledge Base ID; set by Terraform on the Lambda function |
| `MODEL_ID` | `amazon.nova-micro-v1:0` | Bedrock model or inference profile ID; set by Terraform from the `model_id` variable |
| `DYNAMODB_TABLE` | none (optional) | DynamoDB table that stores each question, timestamp and visitor IP; set by Terraform. If unset, questions aren't recorded |
| `RETENTION_DAYS` | `30` | How many days a recorded question is kept before DynamoDB deletes it; set by Terraform from the `question_retention_days` variable |
| `ALLOWED_ORIGIN` | none (optional) | Origin that `/ask` accepts, such as `https://cv.julianberks.com`; set by Terraform from `domain_name`. If unset, the origin check is skipped, which is what you want when running locally |
| `GUARDRAIL_ID` | none (optional) | Bedrock Guardrail applied to each question (prompt-attack, topic and content filters); set by Terraform. If unset, no guardrail is used |
| `GUARDRAIL_VERSION` | `DRAFT` | Guardrail version; set by Terraform |
| `RETRIEVAL_RESULTS` | `20` | Number of CV chunks retrieved from the Knowledge Base for each question |
| `RATE_LIMIT_TABLE` | none (optional) | DynamoDB table holding the per-IP question counters; set by Terraform. If unset, the per-IP limit is skipped |
| `RATE_LIMIT_PER_MINUTE` | `10` | Questions one IP can ask per minute; set by Terraform from `ask_rate_limit_per_minute` |

The Lambda execution role needs `bedrock:Retrieve` on the Knowledge Base, `bedrock:InvokeModel` on the model, `bedrock:ApplyGuardrail` on the guardrail, `dynamodb:PutItem` on the questions table and `dynamodb:UpdateItem` on the rate-limit table. Terraform grants all of these.

## Recorded questions

After each successful answer, `/ask` writes an item to the DynamoDB table `<name>-questions` (`julian-cv-questions` by default) with:

| Attribute | Value |
| --- | --- |
| `id` | Random UUID (partition key) |
| `question` | The question as asked, with surrounding whitespace removed |
| `asked_at` | UTC timestamp in ISO 8601 format |
| `ip` | Visitor IP address, taken from the last `X-Forwarded-For` entry that CloudFront adds. Omitted if it isn't a valid IP |
| `expires_at` | Unix timestamp after which DynamoDB's TTL feature deletes the item (default 30 days) |

Change the retention period with the `question_retention_days` Terraform variable. DynamoDB deletes expired items in the background, usually within a couple of days of the expiry time, so they can linger briefly past it.

The IP address is personal data. Keep the retention period as short as you need, and make sure visitors are told what's recorded.

If the write fails, the error is logged and the visitor still gets their answer. Failed Bedrock calls aren't recorded. To read the questions:

```sh
aws dynamodb scan --table-name julian-cv-questions --region eu-west-2
```

## Running locally

Running locally calls the real Bedrock services, so you need AWS credentials with the permissions above and the Knowledge Base ID.

```sh
cd Container
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt uvicorn
AWS_DEFAULT_REGION=eu-west-2 KNOWLEDGE_BASE_ID=<knowledge-base-id> uvicorn app:app --reload
```

Then open http://127.0.0.1:8000/.

## Infrastructure and deployment

Terraform in `terraform/app` provisions the application and its AWS dependencies. It creates the ECR repository, builds and pushes the Lambda container, uploads the files in `rag_data/` to S3, creates and syncs a managed Bedrock Knowledge Base, and configures the Lambda function, DynamoDB tables, guardrail, CloudFront distribution, ACM certificate and WAF. Terraform state is stored in the `594542138399-tfstate` S3 bucket in `eu-west-2`; that bucket must exist before initialization.

Before applying, make sure:

- Terraform 1.11 or later is installed.
- AWS credentials are configured for the account used by this deployment and can create the resources in the Terraform configuration.
- Docker and the AWS CLI are installed and available to Terraform. Terraform runs `Container/push` locally to authenticate to ECR and build/push the image.
- The AWS account can use the configured Bedrock model in `eu-west-2`.

The app's default Terraform inputs are:

| Variable | Default | Description |
| --- | --- | --- |
| `name` | `julian-cv` | Prefix used to name application resources |
| `region` | `eu-west-2` | Region for the application resources |
| `domain_name` | `cv.julianberks.com` | Public application domain |
| `model_id` | `amazon.nova-micro-v1:0` | Bedrock model used to answer questions |
| `lambda_reserved_concurrency` | `5` | Maximum concurrent Lambda executions; use `-1` for no limit |
| `ask_rate_limit_per_minute` | `10` | Per-IP question limit enforced by the application |
| `waf_requests_per_5_minutes` | `100` | Per-IP request limit enforced by WAF |
| `question_retention_days` | `30` | DynamoDB retention period for recorded questions and visitor IPs |
| `tags` | `{}` | Tags applied to resources |

Initialize and apply the configuration:

```sh
cd terraform/app
terraform init
terraform apply
```

The container build runs when files under `Container/` change. Terraform uploads all files under `rag_data/` and starts a Knowledge Base ingestion job when those source files change. Run `terraform apply` after changing infrastructure, application code, or Knowledge Base source documents; no separate image push or Lambda update command is needed.

DNS for the application is managed outside Terraform. The ACM certificate and CloudFront WAF are created in `us-east-1`; the other application resources use the configured `region`. To validate the certificate before the full apply waits for DNS, first create it and retrieve its DNS validation records:

```sh
terraform apply -target=aws_acm_certificate.cv
terraform output -json acm_dns_validation_records
```

Create the returned CNAME record(s) with your DNS provider, then run `terraform apply` to finish creating CloudFront and the remaining resources. Once the apply completes, point the application domain at the `cloudfront_domain_name` output. Terraform does not manage either DNS change.

The Lambda function URL uses `AWS_IAM` authorization and can be invoked only through CloudFront. The ECR push script currently authenticates to the `594542138399` ECR registry in `eu-west-2`; keep that registry aligned with the deployment account and region.

The page uses relative paths, so it works at the root of the CloudFront domain. If you serve it under a path prefix, open the URL with a trailing slash.
