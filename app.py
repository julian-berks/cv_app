import ipaddress
import logging
import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from mangum import Mangum
from pydantic import BaseModel, ConfigDict, Field

logger = logging.getLogger(__name__)

KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID")
# Change region prefix (us./eu.) if using an inference profile.
MODEL_ID = os.environ.get("MODEL_ID", "amazon.nova-micro-v1:0")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE")
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "30"))
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN")
RATE_LIMIT_TABLE = os.environ.get("RATE_LIMIT_TABLE")
RATE_LIMIT_PER_MINUTE = int(os.environ.get("RATE_LIMIT_PER_MINUTE", "10"))
STATIC_DIR = Path(__file__).parent / "static"
DOCS_DIR = Path(__file__).parent / "docs"

app = FastAPI()
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

agent_client = boto3.client("bedrock-agent-runtime")
runtime_client = boto3.client("bedrock-runtime")
dynamodb_client = boto3.client("dynamodb")


class AskRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    question: str = Field(min_length=1, max_length=1000)


def answer_question(question: str) -> str:
    # Step 1: retrieve relevant chunks from the (managed) Knowledge Base
    retrieval = agent_client.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": question},
    )

    chunks = [result["content"]["text"] for result in retrieval["retrievalResults"]]
    context_text = "\n\n".join(chunks)

    # Step 2: ask the model to answer using the retrieved context
    prompt = (
        f"Using only the context below, answer the question.\n\n"
        f"If the context does not clearly answer the question, say you don't have enough information.\n\n"
        f"Never invent your own answer or question or restate a different question than the one asked.\n\n"
        f"Any question asked must make sense in the context of an English language conversation.\n\n"
        f"Context:\n{context_text}\n\n"
        f"Question: {question}"
    )

    response = runtime_client.converse(
        modelId=MODEL_ID,
        messages=[{"role": "user", "content": [{"text": prompt}]}],
    )

    return response["output"]["message"]["content"][0]["text"]


def viewer_ip(request: Request) -> str | None:
    # CloudFront appends the connecting IP, so the last entry can't be spoofed by the client.
    forwarded = request.headers.get("x-forwarded-for", "")
    candidate = forwarded.split(",")[-1].strip()
    try:
        return str(ipaddress.ip_address(candidate))
    except ValueError:
        return None


def record_question(question: str, ip: str | None) -> None:
    if not DYNAMODB_TABLE:
        return
    now = datetime.now(timezone.utc)
    item = {
        "id": {"S": str(uuid.uuid4())},
        "question": {"S": question},
        "asked_at": {"S": now.isoformat()},
        "expires_at": {"N": str(int((now + timedelta(days=RETENTION_DAYS)).timestamp()))},
    }
    if ip:
        item["ip"] = {"S": ip}
    try:
        dynamodb_client.put_item(TableName=DYNAMODB_TABLE, Item=item)
    except (BotoCoreError, ClientError):
        # Losing a log entry shouldn't stop the user getting their answer.
        logger.exception("Failed to record question")


def require_same_origin(request: Request) -> None:
    # Browsers set these headers and page scripts can't forge them; other clients can, so this only stops casual misuse.
    if not ALLOWED_ORIGIN:
        return
    if request.headers.get("origin") != ALLOWED_ORIGIN or request.headers.get("sec-fetch-site", "same-origin") != "same-origin":
        raise HTTPException(status_code=403, detail="Questions can only be asked from the website.")


def enforce_rate_limit(request: Request) -> None:
    ip = viewer_ip(request)
    if not RATE_LIMIT_TABLE or not ip:
        return
    now = int(time.time())
    try:
        result = dynamodb_client.update_item(
            TableName=RATE_LIMIT_TABLE,
            Key={"bucket": {"S": f"{ip}#{now // 60}"}},
            UpdateExpression="ADD hits :one SET expires_at = :expires",
            ExpressionAttributeValues={":one": {"N": "1"}, ":expires": {"N": str(now + 120)}},
            ReturnValues="UPDATED_NEW",
        )
    except (BotoCoreError, ClientError):
        # Fail open: a broken counter shouldn't stop visitors asking questions.
        logger.exception("Rate limit check failed")
        return
    if int(result["Attributes"]["hits"]["N"]) > RATE_LIMIT_PER_MINUTE:
        raise HTTPException(status_code=429, detail="You're asking questions too quickly. Please wait a minute and try again.")


@app.get("/")
async def root():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/architecture.md")
async def architecture():
    return FileResponse(DOCS_DIR / "architecture.md", media_type="text/markdown")


@app.post("/ask", dependencies=[Depends(require_same_origin), Depends(enforce_rate_limit)])
def ask(request: AskRequest, http_request: Request):
    try:
        answer = answer_question(request.question)
    except (BotoCoreError, ClientError):
        logger.exception("Bedrock request failed")
        raise HTTPException(status_code=502, detail="Could not get an answer right now. Please try again.")
    record_question(request.question, viewer_ip(http_request))
    return {"answer": answer}


@app.get("/s3")
async def s3_question():
    print("Starting S3 question retrieval")
    answer = answer_question("What is Julian's experience with S3")
    print(answer)

    return {
        "statusCode": 200,
        "body": answer,
    }



handler = Mangum(app, lifespan="off")
