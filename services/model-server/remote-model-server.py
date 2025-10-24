#!/usr/bin/env python3
"""
ML Model Server for Flair NER using FastAPI with S3 model loading
"""

# CRITICAL: Set thread limits BEFORE any other imports
import os
os.environ['OMP_NUM_THREADS'] = '2'
os.environ['MKL_NUM_THREADS'] = '2'
os.environ['OPENBLAS_NUM_THREADS'] = '2'
os.environ['NUMEXPR_NUM_THREADS'] = '2'

from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

import os
import tempfile
from contextlib import asynccontextmanager
from typing import List, Dict

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import uvicorn
import boto3
from botocore.exceptions import ClientError

# Import torch and set threads immediately
import torch
torch.set_num_threads(2)
torch.set_num_interop_threads(2)
print(f"[PERFORMANCE] PyTorch threads set to: {torch.get_num_threads()}")

from flair.data import Sentence
from flair.models import SequenceTagger

# timing
from datetime import datetime
import time

# Global model
model = None

class PredictionRequest(BaseModel):
    text: str = Field(..., min_length=1, description="Text to analyze")
    note_type: str = Field(default="UNKNOWN", description="Note type")
    can: str = Field(default="", description="Customer account number")

class PredictionResponse(BaseModel):
    SERVICE: List[str] = []
    ISSUE: List[str] = []
    AMOUNT: List[str] = []
    PERSON: List[str] = []
    ACTION: List[str] = []
    ORG: List[str] = []
    LOCATION: List[str] = []

def download_model_from_s3():
    """Download model from S3-compatible storage to local temporary directory"""
    try:
        # Get all configuration from environment variables
        bucket_name = os.getenv("S3_BUCKET_NAME")
        model_key = os.getenv("S3_MODEL_KEY")
        endpoint_url = os.getenv("S3_ENDPOINT_URL")
        access_key = os.getenv("AWS_ACCESS_KEY_ID")
        secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
        aws_region = os.getenv("AWS_REGION", "us-east-1")
        
        # Validation
        if not bucket_name:
            raise ValueError("S3_BUCKET_NAME environment variable is required")
        if not endpoint_url:
            raise ValueError("S3_ENDPOINT_URL environment variable is required")
        if not access_key or not secret_key:
            raise ValueError("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required")
        
        # print(f"Connecting to S3-compatible storage...")
        # print(f"Endpoint: {endpoint_url}")
        # print(f"Bucket: {bucket_name}")
        # print(f"Model Key: {model_key}")
        
        # Initialize S3 client with explicit credentials and endpoint
        s3_client = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=aws_region,
            config=boto3.session.Config(signature_version='s3v4')
        )

        # Create temporary directory for model
        temp_dir = tempfile.mkdtemp()
        local_model_path = os.path.join(temp_dir, "final-model.pt")
        
        print(f"Downloading model file...")
        # Download model file
        s3_client.download_file(bucket_name, model_key, local_model_path)
        
        # print(f"Model downloaded successfully to {local_model_path}")
        return local_model_path
        
    except ClientError as e:
        print(f"S3 download error: {e}")
        error_code = e.response['Error']['Code']
        if error_code == '404':
            print(f"Model not found at s3://{bucket_name}/{model_key}")
        elif error_code == '403':
            print("Access denied. Check your AWS credentials and bucket permissions.")
        raise
    except Exception as e:
        print(f"Failed to download model from S3: {e}")
        import traceback
        traceback.print_exc()
        raise

def load_model():
    """Load Flair model from S3 or local path"""
    try:
        # Check if we should use S3 or local path
        use_s3 = os.getenv("USE_S3_MODEL", "true").lower() == "true"
        
        if use_s3:
            print("Using S3 model loading...")
            model_path = download_model_from_s3()
        else:
            # Fallback to local path for development
            model_path = "models/distilroberta-base-ner-v3/final-model.pt"
            print(f"Using local model path: {model_path}")
            
            if not os.path.exists(model_path):
                print(f"ERROR: Model file not found at {model_path}")
                print(f"Current directory: {os.getcwd()}")
                return None
        
        print(f"Loading model from {model_path}...")
        loaded_model = SequenceTagger.load(model_path)
        print("Model loaded successfully!")
        return loaded_model
        
    except Exception as e:
        print(f"Failed to load model: {e}")
        import traceback
        traceback.print_exc()
        return None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model on startup"""
    global model
    print("Starting ML Model Server...")
    model = load_model()
    
    if not model:
        print("ERROR: Could not load model")
        raise RuntimeError("Model loading failed")
    
    print("Model loaded. Server ready.")
    yield
    print("Shutting down...")

app = FastAPI(
    title="ML Model Server",
    description="NER Model for Telco Data",
    version="1.0.0",
    lifespan=lifespan
)

@app.get("/health")
async def health():
    """Health check"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    return {"status": "healthy"}

@app.get("/ready")
async def ready():
    """Readiness check"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not ready")
    return {"status": "ready"}

@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    """Main prediction endpoint"""
    if not model:
        raise HTTPException(status_code=503, detail="Model not available")
    
    if not request.text or not request.text.strip():
        raise HTTPException(status_code=400, detail="Empty text provided")
    
    try:
        # Start timing calc
        start_time = time.time()

        # Create sentence and predict
        sentence = Sentence(request.text)
        model.predict(sentence)
        
        # Calculate and print inference time
        inference_time_ms = (time.time() - start_time) * 1000
        print(f"Inference > time: {inference_time_ms:.0f}ms")

        # Extract entities
        label_dict = {
            "SERVICE": [],
            "ISSUE": [],
            "AMOUNT": [],
            "PERSON": [],
            "ACTION": [],
            "ORG": [],
            "LOCATION": []
        }
        
        for label in sentence.labels:
            entity_text = str(label).split('"')[1]
            entity_type = str(label.value)
            
            if entity_type in label_dict and entity_text not in label_dict[entity_type]:
                label_dict[entity_type].append(entity_text)
        
        return PredictionResponse(**label_dict)
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction error: {str(e)}")

@app.get("/test")
async def test():
    """Test endpoint with sample data"""
    test_text = "John Smith called about internet service issue in Regina. Charged $50."
    
    try:
        sentence = Sentence(test_text)
        model.predict(sentence)
        
        entities = {k: [] for k in ["SERVICE", "ISSUE", "AMOUNT", "PERSON", "ACTION", "ORG", "LOCATION"]}
        
        for label in sentence.labels:
            entity_text = str(label).split('"')[1]
            entity_type = str(label.value)
            if entity_type in entities:
                entities[entity_type].append(entity_text)
        
        return {
            "test_text": test_text,
            "entities": entities,
            "status": "success"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")