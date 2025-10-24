import json
import time
import random
import os
import pandas as pd
from datetime import datetime, timedelta
from kafka import KafkaProducer
from faker import Faker
import logging
import numpy as np
from typing import Optional, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
KAFKA_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:19092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'npl_input_stream')
GENERATION_RATE = int(os.getenv('GENERATION_RATE', '5'))  # messages per second
CSV_FILE_PATH = os.getenv('CSV_FILE_PATH', 'data/cleanedDataOct04.csv')
LOOP_DATA = os.getenv('LOOP_DATA', 'true').lower() == 'true'  # Loop through data when finished

fake = Faker()

class SaskTelDataGenerator:
    def __init__(self):
        self.producer = None
        self.df = None
        self.current_index = 0
        self.load_csv_data()
        
    def create_producer(self):
        """Create Kafka producer with retry logic"""
        max_retries = 10
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                producer = KafkaProducer(
                    bootstrap_servers=KAFKA_SERVERS,
                    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                    key_serializer=lambda k: k.encode('utf-8') if k else None,
                    # Additional configurations for reliability
                    acks='all',
                    retries=3,
                    batch_size=16384,
                    linger_ms=10,
                    buffer_memory=33554432
                )
                logger.info(f"Connected to Kafka at {KAFKA_SERVERS}")
                return producer
            except Exception as e:
                retry_count += 1
                logger.warning(f"Failed to connect to Kafka (attempt {retry_count}/{max_retries}): {e}")
                time.sleep(5)
        
        raise Exception("Could not connect to Kafka after maximum retries")
    
    def load_csv_data(self):
        """Load and prepare CSV data"""
        try:
            logger.info(f"Loading CSV data from {CSV_FILE_PATH}")
            
            # Try different encodings in case cp437 fails
            encodings_to_try = ['cp437', 'utf-8', 'latin-1', 'iso-8859-1']
            
            for encoding in encodings_to_try:
                try:
                    self.df = pd.read_csv(CSV_FILE_PATH, encoding=encoding)
                    logger.info(f"Successfully loaded CSV with {encoding} encoding")
                    break
                except UnicodeDecodeError:
                    continue
            
            if self.df is None:
                raise ValueError("Could not load CSV with any encoding")
            
            # Expected columns based on your Jupyter notebook
            required_columns = ["CAN", "cleaned_text_x", "X_NOTE_TYPE"]
            optional_columns = ["START_x", "PROMO_END"]
            
            # Check if required columns exist
            missing_columns = [col for col in required_columns if col not in self.df.columns]
            if missing_columns:
                logger.warning(f"Missing required columns: {missing_columns}")
                # Create dummy data if columns are missing
                if "CAN" not in self.df.columns:
                    self.df["CAN"] = [f"CAN_{i:06d}" for i in range(len(self.df))]
                if "cleaned_text_x" not in self.df.columns:
                    self.df["cleaned_text_x"] = [fake.text() for _ in range(len(self.df))]
                if "X_NOTE_TYPE" not in self.df.columns:
                    self.df["X_NOTE_TYPE"] = [random.choice(["SERVICE", "BILLING", "TECHNICAL", "COMPLAINT"]) for _ in range(len(self.df))]
            
            # Clean the data
            self.df = self.df.dropna(subset=["CAN", "cleaned_text_x"])
            
            # Convert date columns if they exist
            for date_col in optional_columns:
                if date_col in self.df.columns:
                    try:
                        self.df[date_col] = pd.to_datetime(self.df[date_col], errors='coerce')
                    except:
                        pass
            
            logger.info(f"Loaded {len(self.df)} records from CSV")
            logger.info(f"Columns available: {list(self.df.columns)}")
            
        except Exception as e:
            logger.error(f"Failed to load CSV data: {e}")
            # Create synthetic data as fallback
            self.create_synthetic_data()
    
    def create_synthetic_data(self):
        """Create synthetic SaskTel-like data as fallback"""
        logger.info("Creating synthetic data as fallback")
        
        note_types = ["SERVICE", "BILLING", "TECHNICAL", "COMPLAINT", "SALES", "SUPPORT"]
        service_terms = ["internet", "phone", "tv", "mobile", "landline", "fiber"]
        issue_terms = ["outage", "slow", "billing error", "connection", "payment", "upgrade"]
        action_terms = ["resolved", "escalated", "refunded", "installed", "repaired", "cancelled"]
        
        synthetic_data = []
        for i in range(1000):  # Create 1000 synthetic records
            # Generate realistic customer notes
            service = random.choice(service_terms)
            issue = random.choice(issue_terms)
            action = random.choice(action_terms)
            
            note_templates = [
                f"Customer called regarding {service} {issue}. Issue was {action}.",
                f"Billing inquiry about {service} charges. Customer complaint {action}.",
                f"Technical support for {service} connectivity. Problem {action}.",
                f"Service request for {service} upgrade. Request {action}.",
                f"Customer experiencing {issue} with {service}. Case {action}."
            ]
            
            synthetic_data.append({
                "CAN": f"CAN_{i+1:06d}",
                "cleaned_text_x": random.choice(note_templates),
                "X_NOTE_TYPE": random.choice(note_types),
                "START_x": fake.date_time_between(start_date='-2y', end_date='now'),
                "PROMO_END": fake.date_time_between(start_date='now', end_date='+1y')
            })
        
        self.df = pd.DataFrame(synthetic_data)
        logger.info(f"Created {len(self.df)} synthetic records")
    
    def enhance_note_with_entities(self, note_text: str) -> str:
        """Add more realistic entities to notes for better ML inference"""
        enhancements = []
        
        # Add dollar amounts randomly
        if random.random() < 0.3:
            amount = round(random.uniform(10, 500), 2)
            enhancements.append(f"Amount: ${amount}")
        
        # Add person names
        if random.random() < 0.2:
            enhancements.append(f"Handled by {fake.name()}")
        
        # Add locations
        if random.random() < 0.15:
            enhancements.append(f"Location: {fake.city()}")
        
        # Add organizations
        if random.random() < 0.1:
            orgs = ["SaskTel", "Technical Department", "Billing Department", "Customer Service"]
            enhancements.append(f"Dept: {random.choice(orgs)}")
        
        if enhancements:
            return f"{note_text} {' '.join(enhancements)}"
        return note_text
    
    def generate_message_from_row(self, row: pd.Series) -> Dict[str, Any]:
        """Generate a Kafka message from a CSV row"""
        # Extract data from row
        can = str(row.get("CAN", f"CAN_{random.randint(100000, 999999)}"))
        note_type = str(row.get("X_NOTE_TYPE", "SERVICE"))
        text = str(row.get("cleaned_text_x", "Customer service note"))
        
        # Enhance text with additional entities
        enhanced_text = self.enhance_note_with_entities(text)
        
        # Add timestamp - use original date if available, otherwise recent random time
        if "START_x" in row and pd.notna(row["START_x"]):
            try:
                timestamp = int(pd.to_datetime(row["START_x"]).timestamp() * 1000)
            except:
                timestamp = int(datetime.now().timestamp() * 1000)
        else:
            # Random timestamp within last 30 days
            base_time = datetime.now() - timedelta(days=random.randint(0, 30))
            timestamp = int(base_time.timestamp() * 1000)
        
        # Add optional promo information
        promo_info = {}
        if "PROMO_END" in row and pd.notna(row["PROMO_END"]):
            try:
                promo_end = int(pd.to_datetime(row["PROMO_END"]).timestamp() * 1000)
                promo_info["promo_end"] = promo_end
            except:
                pass
        
        # Create message matching ML inference pipeline expectations
        message = {
            "can": can,
            "note_type": note_type,
            "text": enhanced_text,
            "timestamp": timestamp,
            # **promo_info
        }
        
        # Add metadata
        message["metadata"] = {
            "source": "csv_generator",
            "row_index": self.current_index,
            "generation_time": int(datetime.now().timestamp() * 1000)
        }
        
        return message
    
    def get_next_row(self) -> Optional[pd.Series]:
        """Get next row from CSV data"""
        if self.df is None or len(self.df) == 0:
            return None
        
        if self.current_index >= len(self.df):
            if LOOP_DATA:
                logger.info("Reached end of data, looping back to beginning")
                self.current_index = 0
            else:
                logger.info("Reached end of data, stopping")
                return None
        
        row = self.df.iloc[self.current_index]
        self.current_index += 1
        return row
    
    def run(self):
        """Main data generation loop"""
        logger.info(f"Starting SaskTel data generator")
        logger.info(f"Rate: {GENERATION_RATE} msg/sec, Topic: {KAFKA_TOPIC}")
        logger.info(f"CSV file: {CSV_FILE_PATH}")
        logger.info(f"Loop data: {LOOP_DATA}")
        
        self.producer = self.create_producer()
        
        try:
            message_count = 0
            start_time = time.time()
            
            while True:
                # Get next row from CSV
                row = self.get_next_row()
                if row is None:
                    logger.info("No more data available")
                    break
                
                # Generate message
                message = self.generate_message_from_row(row)
                
                # Send to Kafka
                try:
                    future = self.producer.send(
                        topic=KAFKA_TOPIC,
                        key=message['can'],
                        value=message
                    )
                    # Optional: wait for confirmation
                    # future.get(timeout=10)
                    
                    message_count += 1
                    
                    if message_count % 100 == 0:
                        elapsed = time.time() - start_time
                        rate = message_count / elapsed if elapsed > 0 else 0
                        logger.info(f"Sent {message_count} messages (avg rate: {rate:.2f} msg/sec)")
                    
                    # Debug: print first few messages
                    if message_count <= 3:
                        logger.info(f"Sample message: {json.dumps(message, indent=2)}")
                    
                except Exception as e:
                    logger.error(f"Failed to send message: {e}")
                    continue
                
                # Control generation rate
                time.sleep(1.0 / GENERATION_RATE)
                
        except KeyboardInterrupt:
            logger.info("Shutting down data generator...")
        except Exception as e:
            logger.error(f"Error in data generation: {e}")
        finally:
            if self.producer:
                self.producer.flush()
                self.producer.close()
            logger.info(f"Generator stopped. Sent {message_count} total messages")

def main():
    """Entry point"""
    generator = SaskTelDataGenerator()
    generator.run()

if __name__ == "__main__":
    main()