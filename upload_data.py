import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore
import os

# Configuration
EXCEL_FILE = 'TC-NN-2025-1836-A1.xlsx'
SHEET_NAME = 'MASTER LIST'
COLLECTION_NAME = 'instrument_masters'
SERVICE_ACCOUNT_KEY = 'serviceAccountKey.json'

def seed_data():
    # 1. Check for Service Account Key
    if not os.path.exists(SERVICE_ACCOUNT_KEY):
        print(f"Error: {SERVICE_ACCOUNT_KEY} not found.")
        print("Please fetch your service account key from Firebase Console -> Project Settings -> Service Accounts.")
        print("Save it as 'serviceAccountKey.json' in this folder.")
        return

    # 2. Initialize Firebase
    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
            firebase_admin.initialize_app(cred)
        print("Firebase initialized.")
    except Exception as e:
        print(f"Error initializing Firebase: {e}")
        return
    
    db = firestore.client()

    # 3. Read Excel
    print(f"Reading {EXCEL_FILE}...")
    try:
        # Check required libraries
        import openpyxl
    except ImportError:
        print("Error: 'openpyxl' library is missing. Install it with: pip install openpyxl")
        return

    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name=SHEET_NAME)
        # Normalize column names (remove leading/trailing spaces)
        df.columns = df.columns.str.strip()
        print(f"Columns found: {df.columns.tolist()}")
        
        if 'ID' not in df.columns:
            print("CRITICAL ERROR: Column 'ID' not found in Excel file.")
            print(f"Available columns: {df.columns.tolist()}")
            return

    except Exception as e:
        print(f"Error reading Excel file: {e}")
        return

    # 4. Iterate and Upload
    print(f"Found {len(df)} rows. Starting upload to '{COLLECTION_NAME}'...")
    
    success_count = 0
    
    for index, row in df.iterrows():
        try:
            # Ensure ID is a string for the Document ID
            raw_id = row['ID']
            if pd.isna(raw_id):
                print(f"Skipping row {index}: ID is missing.")
                continue
                
            doc_id = str(raw_id).strip()
            
            # Firestore Document IDs cannot contain forward slashes '/'.
            # We will replace '/' with '_' for the Document Key.
            safe_doc_id = doc_id.replace('/', '_')
            
            # Prepare data map
            data = {
                'size_mm': row['SIZE in MM'] if pd.notna(row['SIZE in MM']) else None,
                'id': doc_id, # Keep the original ID (with slashes) here
                'instrument': row['Instrument'] if pd.notna(row['Instrument']) else None,
                'cert_number': row['CERT. NUMBER'] if pd.notna(row['CERT. NUMBER']) else None,
                'valid_until': row['VALID'] if pd.notna(row['VALID']) else None,
                'uploaded_at': firestore.SERVER_TIMESTAMP
            }
            
            # Upload
            db.collection(COLLECTION_NAME).document(safe_doc_id).set(data)
            
            success_count += 1
            if success_count % 10 == 0:
                print(f"Uploaded {success_count} documents...")
                
        except Exception as e:
            print(f"Error uploading row {index}: {e}")

    print(f"Finished. Successfully uploaded {success_count} documents to '{COLLECTION_NAME}'.")

if __name__ == '__main__':
    seed_data()
