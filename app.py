import logging
import os
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from mangum import Mangum
from pydantic import BaseModel, ConfigDict, Field

logger = logging.getLogger(__name__)

KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID", "WVOCVIUTT0")
# Change region prefix (us./eu.) if using an inference profile.
MODEL_ID = os.environ.get("MODEL_ID", "amazon.nova-micro-v1:0")
STATIC_DIR = Path(__file__).parent / "static"

app = FastAPI()
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

agent_client = boto3.client("bedrock-agent-runtime")
runtime_client = boto3.client("bedrock-runtime")


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
        f"Context:\n{context_text}\n\n"
        f"Question: {question}"
    )

    response = runtime_client.converse(
        modelId=MODEL_ID,
        messages=[{"role": "user", "content": [{"text": prompt}]}],
    )

    return response["output"]["message"]["content"][0]["text"]


@app.get("/")
async def root():
    return FileResponse(STATIC_DIR / "index.html")


@app.post("/ask")
def ask(request: AskRequest):
    try:
        answer = answer_question(request.question)
    except (BotoCoreError, ClientError):
        logger.exception("Bedrock request failed")
        raise HTTPException(status_code=502, detail="Could not get an answer right now. Please try again.")
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
