# CV App

A chat web page for asking questions about Julian's CV. Answers come from an Amazon Bedrock Knowledge Base and model. The app is a FastAPI service running in a Docker container on AWS Lambda.

## How it works

1. The browser loads the Vue 3 chat page from `/`.
2. Each question is sent to `POST /ask`.
3. The backend retrieves matching CV content from the Bedrock Knowledge Base.
4. A Bedrock model answers using only that content, and the answer appears in the chat.

Each question is answered on its own; earlier messages in the chat aren't sent to the model.

## Project structure

| File | Purpose |
| --- | --- |
| `app.py` | FastAPI app, Bedrock calls and the Lambda handler (via Mangum) |
| `static/index.html` | Chat page layout and styles |
| `static/app.js` | Vue 3 app that sends questions and shows answers |
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Lambda container image based on `public.ecr.aws/lambda/python:3.12` |
| `push` | Builds the image and pushes it to ECR |

Vue 3 is loaded from the unpkg CDN, so there's no front-end build step.

## Routes

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/` | Chat page |
| `POST` | `/ask` | Body `{"question": "..."}` returns `{"answer": "..."}` |
| `GET` | `/s3` | Fixed test question about S3 experience |
| `GET` | `/static/*` | Page assets |

`/ask` rejects blank questions and questions over 1000 characters with a `422`, and returns a `502` if Bedrock fails.

## Configuration

| Environment variable | Default | Description |
| --- | --- | --- |
| `KNOWLEDGE_BASE_ID` | `WVOCVIUTT0` | Bedrock Knowledge Base ID |
| `MODEL_ID` | `amazon.nova-micro-v1:0` | Bedrock model or inference profile ID |

The Lambda execution role needs `bedrock:Retrieve` on the Knowledge Base and `bedrock:InvokeModel` on the model.

## Running locally

Running locally calls the real Bedrock services, so you need AWS credentials with the permissions above.

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt uvicorn
AWS_DEFAULT_REGION=eu-west-2 uvicorn app:app --reload
```

Then open http://127.0.0.1:8000/.

## Deploying

Log in to ECR, then run the push script:

```sh
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin 594542138399.dkr.ecr.eu-west-2.amazonaws.com
sh push
```

Then point the Lambda function at the new image:

```sh
aws lambda update-function-code --function-name <function-name> --image-uri 594542138399.dkr.ecr.eu-west-2.amazonaws.com/cv-app:latest
```

The page uses relative paths, so it works behind a Lambda function URL or at the root of an API Gateway. Under an API Gateway stage path such as `/prod`, open the URL with a trailing slash (`/prod/`).
