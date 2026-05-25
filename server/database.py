import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "db.sqlite")

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        public_key TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)
    
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS profiles (
        user_id INTEGER PRIMARY KEY,
        bio TEXT DEFAULT '',
        profile_picture_url TEXT DEFAULT '',
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
    )
    """)
    
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS notes (
        user_id INTEGER PRIMARY KEY,
        content TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
    )
    """)
    
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender_id INTEGER NOT NULL,
        recipient_id INTEGER NOT NULL,
        ciphertext TEXT NOT NULL,
        iv TEXT NOT NULL,
        ephemeral_public_key TEXT NOT NULL,
        mac TEXT NOT NULL,
        message_id TEXT,
        original_length INTEGER DEFAULT 0,
        client_timestamp TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        delivered INTEGER DEFAULT 0,
        FOREIGN KEY (sender_id) REFERENCES users (id),
        FOREIGN KEY (recipient_id) REFERENCES users (id)
    )
    """)
    
    for col in ["message_id TEXT", "original_length INTEGER DEFAULT 0", "client_timestamp TEXT"]:
        try:
            cursor.execute(f"ALTER TABLE messages ADD COLUMN {col}")
        except Exception:
            pass
    
    conn.commit()
    conn.close()

if __name__ == "__main__":
    init_db()
    print("Database initialized successfully at", DB_PATH)
