#!/usr/bin/env python3
"""
ML Model Server for Flair NER using FastAPI
"""
import os
from contextlib import asynccontextmanager
from typing import List, Dict

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import uvicorn

from flair.data import Sentence
from flair.models import SequenceTagger

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

def load_model():
    """Load Flair model"""
    try:
        model_path = "models/distilroberta-base-ner-v3/final-model.pt"
        
        print(f"Loading model from {model_path}...")
        
        if not os.path.exists(model_path):
            print(f"ERROR: Model file not found at {model_path}")
            print(f"Current directory: {os.getcwd()}")
            if os.path.exists('models/distilroberta-base-ner-v3/'):
                print(f"Files in models/: {os.listdir('models/distilroberta-base-ner-v3/')}")
            return None
        
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
        # Create sentence and predict
        sentence = Sentence(request.text)
        model.predict(sentence)
        
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