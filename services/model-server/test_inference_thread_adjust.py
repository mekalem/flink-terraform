#!/usr/bin/env python3
"""
Pure model inference test - WITH THREAD LIMITING
"""

# CRITICAL: Set thread limits BEFORE any imports
import os
os.environ['OMP_NUM_THREADS'] = '2'
os.environ['MKL_NUM_THREADS'] = '2'
os.environ['OPENBLAS_NUM_THREADS'] = '2'
os.environ['NUMEXPR_NUM_THREADS'] = '2'

import time
import sys
import glob
import torch

# Set PyTorch threads immediately after import
torch.set_num_threads(2)
torch.set_num_interop_threads(2)

from flair.data import Sentence
from flair.models import SequenceTagger

print("="*60)
print("PURE MODEL INFERENCE TEST - WITH THREAD LIMITING")
print("="*60)

# Show thread configuration immediately
print(f"\nThread Configuration:")
print(f"  OMP_NUM_THREADS:     {os.environ.get('OMP_NUM_THREADS')}")
print(f"  PyTorch threads:     {torch.get_num_threads()}")
print(f"  Interop threads:     {torch.get_num_interop_threads()}")

# Find model path
model_paths = glob.glob('/tmp/tmp*/final-model.pt')
if not model_paths:
    print("ERROR: No model found in /tmp/tmp*/")
    sys.exit(1)

model_path = model_paths[0]
print(f"\nModel path: {model_path}")

# Load model
print("\nLoading model...")
load_start = time.time()
model = SequenceTagger.load(model_path)
load_time = time.time() - load_start
print(f"Model loaded in {load_time:.2f} seconds")

# Test text
test_text = "John called about internet service in Regina. Charged $50."
print(f"\nTest text: {test_text}")

# Run 10 inference tests
times = []
print("\nRunning 10 inference tests...")
print("-"*60)

for i in range(10):
    sentence = Sentence(test_text)
    start = time.time()
    model.predict(sentence)
    elapsed = (time.time() - start) * 1000
    times.append(elapsed)
    
    # Show entities found
    entities = len(sentence.labels)
    print(f"Test {i+1:2d}: {elapsed:6.0f}ms | Entities found: {entities}")

print("-"*60)
print(f"\nStatistics:")
print(f"  Average: {sum(times)/len(times):.0f}ms")
print(f"  Min:     {min(times):.0f}ms")
print(f"  Max:     {max(times):.0f}ms")
print(f"  Median:  {sorted(times)[len(times)//2]:.0f}ms")

# Environment info
print("\n" + "="*60)
print("Environment Info:")
print("="*60)
print(f"PyTorch version:    {torch.__version__}")
print(f"PyTorch threads:    {torch.get_num_threads()}")
print(f"Interop threads:    {torch.get_num_interop_threads()}")
print(f"MKL available:      {torch.backends.mkl.is_available()}")
print(f"OpenMP available:   {torch.backends.openmp.is_available()}")

import flair
print(f"Flair version:      {flair.__version__}")

print("="*60)