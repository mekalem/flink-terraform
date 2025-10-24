FROM python:3.9-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy generator script
COPY nplGenerator.py .

RUN mkdir -p /app/data

CMD ["python", "nplGenerator.py"]
