# CV App

A web page about Julian's CV. It has a home page, a chat tool for asking questions about the CV, and an About page that shows the project's architecture documentation. Answers come from an Amazon Bedrock Knowledge Base and model. The app is a FastAPI service running in a Docker container on AWS Lambda, served at `https://cv.julianberks.com` through CloudFront.

See [docs/architecture.md](docs/architecture.md) for the AWS architecture diagram and a full component breakdown.

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
| `app.py` | FastAPI app, Bedrock calls and the Lambda handler (via Mangum) |
| `static/index.html` | Page layout and styles, the menu, home text, chat view and About view |
| `static/app.js` | Vue 3 app that switches views, sends questions, shows answers and renders the About page |
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Lambda container image based on `public.ecr.aws/lambda/python:3.12` |
| `push` | Builds the image and pushes it to ECR |
| `terraform/` | Infrastructure: ECR, Lambda, Bedrock Knowledge Base, CloudFront, ACM and WAF |
| `docs/architecture.md` | Architecture diagram and component documentation |

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
| `RATE_LIMIT_TABLE` | none (optional) | DynamoDB table holding the per-IP question counters; set by Terraform. If unset, the per-IP limit is skipped |
| `RATE_LIMIT_PER_MINUTE` | `10` | Questions one IP can ask per minute; set by Terraform from `ask_rate_limit_per_minute` |

The Lambda execution role needs `bedrock:Retrieve` on the Knowledge Base, `bedrock:InvokeModel` on the model, `dynamodb:PutItem` on the questions table and `dynamodb:UpdateItem` on the rate-limit table. Terraform grants all of these.

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
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt uvicorn
AWS_DEFAULT_REGION=eu-west-2 KNOWLEDGE_BASE_ID=<knowledge-base-id> uvicorn app:app --reload
```

Then open http://127.0.0.1:8000/.

## Infrastructure

Terraform in `terraform/app` creates the AWS resources. State is stored in an S3 bucket in `eu-west-2`.

```sh
cd terraform/app
terraform init
terraform apply
```

The `container_deployed` variable (default `true`) controls the Lambda function, ACM certificate and CloudFront distribution. On a fresh account, apply with `-var container_deployed=false` to create the ECR repository first, push an image, then apply again with the default.

DNS for `cv.julianberks.com` is managed outside Terraform, so two manual steps are needed:

1. Create the certificate validation record from the `acm_dns_validation_records` output.
2. Point `cv.julianberks.com` at the `cloudfront_domain_name` output.

The Lambda function URL uses `AWS_IAM` authorization and can be invoked only through CloudFront.

## Deploying code

Log in to ECR, then run the push script:

```sh
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin 594542138399.dkr.ecr.eu-west-2.amazonaws.com
sh push
```

Then point the Lambda function at the new image:

```sh
aws lambda update-function-code --function-name julian-cv-lambda-function --image-uri 594542138399.dkr.ecr.eu-west-2.amazonaws.com/julian-cv-ecr:latest
```

Terraform ignores changes to the function's image, so code releases don't need a Terraform apply. The image also contains `docs/architecture.md`, so documentation changes need a new image too.

The page uses relative paths, so it works at the root of the CloudFront domain. If you serve it under a path prefix, open the URL with a trailing slash.
