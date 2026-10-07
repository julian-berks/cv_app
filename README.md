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

Through CloudFront, POST requests must include an `x-amz-content-sha256` header containing the SHA-256 hex digest of the request body, otherwise CloudFront returns a `403`. The page does this automatically. From the command line:

```sh
body='{"question":"Hello"}'
curl -X POST https://cv.julianberks.com/ask \
  -H 'Content-Type: application/json' \
  -H "x-amz-content-sha256: $(printf '%s' "$body" | shasum -a 256 | cut -d' ' -f1)" \
  -d "$body"
```

## Configuration

| Environment variable | Default | Description |
| --- | --- | --- |
| `KNOWLEDGE_BASE_ID` | none (required) | Bedrock Knowledge Base ID; set by Terraform on the Lambda function |
| `MODEL_ID` | `amazon.nova-micro-v1:0` | Bedrock model or inference profile ID; set by Terraform from the `model_id` variable |

The Lambda execution role needs `bedrock:Retrieve` on the Knowledge Base and `bedrock:InvokeModel` on the model. Terraform grants both.

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
