from fastapi import FastAPI, Depends, WebSocket, WebSocketDisconnect, HTTPException, status, Query
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Optional
import json

import sqlite3
import asyncio

from database import init_db, get_db_connection
from security import hash_password, verify_password, create_access_token, get_current_user_id
from sockets import manager

app = FastAPI(title="Acrypcom Secure Social Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def on_startup():
    init_db()
    print("Database connection verified.")

@app.post("/register")
def register(data: dict):
    username = data.get("username", "").strip().lower()
    password = data.get("password", "")
    public_key = data.get("public_key", "")
    
    if not username or not password or not public_key:
        raise HTTPException(status_code=400, detail="Username, password, and public_key are required.")
    
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        pw_hash = hash_password(password)
        cursor.execute(
            "INSERT INTO users (username, password_hash, public_key) VALUES (?, ?, ?)",
            (username, pw_hash, public_key)
        )
        user_id = cursor.lastrowid
        
        cursor.execute("INSERT INTO profiles (user_id) VALUES (?)", (user_id,))
        conn.commit()
        
        token = create_access_token(user_id, username)
        return {
            "token": token,
            "user": {
                "id": user_id,
                "username": username,
                "public_key": public_key
            }
        }
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Username already exists.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.post("/login")
def login(data: dict):
    username = data.get("username", "").strip().lower()
    password = data.get("password", "")
    
    if not username or not password:
        raise HTTPException(status_code=400, detail="Username and password are required.")
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT id, username, password_hash, public_key FROM users WHERE username = ?", (username,))
    user = cursor.fetchone()
    conn.close()
    
    if not user or not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password.")
        
    token = create_access_token(user["id"], user["username"])
    return {
        "token": token,
        "user": {
            "id": user["id"],
            "username": user["username"],
            "public_key": user["public_key"]
        }
    }

@app.get("/users/search")
def search_users(query: str = Query("", min_length=1), current_user_id: int = Depends(get_current_user_id)):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT id, username, public_key FROM users WHERE username LIKE ? AND id != ? LIMIT 20",
        (f"%{query.strip().lower()}%", current_user_id)
    )
    users = cursor.fetchall()
    conn.close()
    
    return [{"id": u["id"], "username": u["username"], "public_key": u["public_key"]} for u in users]

@app.get("/users/{user_id}/profile")
def get_profile(user_id: int, current_user_id: int = Depends(get_current_user_id)):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT u.id, u.username, u.public_key, p.bio, p.profile_picture_url, n.content as active_note
        FROM users u
        LEFT JOIN profiles p ON u.id = p.user_id
        LEFT JOIN notes n ON u.id = n.user_id
        WHERE u.id = ?
    """, (user_id,))
    
    profile = cursor.fetchone()
    conn.close()
    
    if not profile:
        raise HTTPException(status_code=404, detail="User profile not found.")
        
    return {
        "id": profile["id"],
        "username": profile["username"],
        "public_key": profile["public_key"],
        "bio": profile["bio"],
        "profile_picture_url": profile["profile_picture_url"],
        "active_note": profile["active_note"]
    }

@app.post("/profile/update")
def update_profile(data: dict, current_user_id: int = Depends(get_current_user_id)):
    bio = data.get("bio", "")
    profile_picture_url = data.get("profile_picture_url", "")
    public_key = data.get("public_key")
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE profiles SET bio = ?, profile_picture_url = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?",
        (bio, profile_picture_url, current_user_id)
    )
    if public_key:
        cursor.execute(
            "UPDATE users SET public_key = ? WHERE id = ?",
            (public_key, current_user_id)
        )
    conn.commit()
    conn.close()
    
    return {"status": "success", "message": "Profile updated successfully."}

@app.post("/notes/publish")
async def publish_note(data: dict, current_user_id: int = Depends(get_current_user_id)):
    content = data.get("content", "").strip()
    if not content:
        raise HTTPException(status_code=400, detail="Note content cannot be empty.")
    if len(content) > 60:
        raise HTTPException(status_code=400, detail="Note cannot exceed 60 characters.")
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO notes (user_id, content, created_at) VALUES (?, ?, CURRENT_TIMESTAMP) "
        "ON CONFLICT(user_id) DO UPDATE SET content=excluded.content, created_at=excluded.created_at",
        (current_user_id, content)
    )
    conn.commit()
    conn.close()
    
    await manager.broadcast_status({
        "type": "note_update",
        "user_id": current_user_id,
        "content": content
    }, current_user_id)
    
    return {"status": "success", "message": "Note published successfully."}

@app.get("/notes/feed")
def get_notes_feed(current_user_id: int = Depends(get_current_user_id)):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT u.id as user_id, u.username, n.content, n.created_at
        FROM notes n
        JOIN users u ON n.user_id = u.id
        WHERE n.user_id != ?
        ORDER BY n.created_at DESC
    """, (current_user_id,))
    notes = cursor.fetchall()
    conn.close()
    
    return [{
        "user_id": n["user_id"],
        "username": n["username"],
        "content": n["content"],
        "created_at": n["created_at"]
    } for n in notes]

@app.get("/messages/offline")
def get_offline_messages(current_user_id: int = Depends(get_current_user_id)):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, sender_id, ciphertext, iv, ephemeral_public_key, mac, message_id, original_length, client_timestamp, created_at
        FROM messages
        WHERE recipient_id = ? AND delivered = 0
        ORDER BY created_at ASC
    """, (current_user_id,))
    messages = cursor.fetchall()

    if messages:
        ids = [m["id"] for m in messages]
        cursor.execute(
            f"UPDATE messages SET delivered = 1 WHERE id IN ({','.join(['?']*len(ids))})",
            ids
        )
        conn.commit()
        
    conn.close()
    
    return [{
        "id": m["id"],
        "sender_id": m["sender_id"],
        "ciphertext": m["ciphertext"],
        "iv": m["iv"],
        "ephemeral_public_key": m["ephemeral_public_key"],
        "mac": m["mac"],
        "message_id": m["message_id"],
        "original_length": m["original_length"],
        "timestamp": m["client_timestamp"],
        "created_at": m["created_at"]
    } for m in messages]

@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: int):
    await manager.connect(user_id, websocket)
    try:
        while True:
            data_text = await websocket.receive_text()
            try:
                payload = json.loads(data_text)
            except ValueError:
                continue
            
            recipient_id = payload.get("recipient_id")
            ciphertext = payload.get("ciphertext")
            iv = payload.get("iv")
            ephemeral_public_key = payload.get("ephemeral_public_key")
            mac = payload.get("mac")
            message_id_client = payload.get("message_id")
            original_length = payload.get("original_length", 0)
            client_timestamp = payload.get("timestamp")
            
            if not recipient_id or not ciphertext or not iv or not ephemeral_public_key or not mac:
                continue

            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO messages (sender_id, recipient_id, ciphertext, iv, ephemeral_public_key, mac, message_id, original_length, client_timestamp, delivered)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """, (user_id, recipient_id, ciphertext, iv, ephemeral_public_key, mac, message_id_client, original_length, client_timestamp))
            db_message_id = cursor.lastrowid
            conn.commit()
            cursor.execute("SELECT created_at FROM messages WHERE id = ?", (db_message_id,))
            created_at = cursor.fetchone()["created_at"]
            conn.close()

            forward_payload = {
                "type": "message",
                "id": db_message_id,
                "sender_id": user_id,
                "ciphertext": ciphertext,
                "iv": iv,
                "ephemeral_public_key": ephemeral_public_key,
                "mac": mac,
                "created_at": created_at,
                "message_id": message_id_client,
                "original_length": original_length,
                "timestamp": client_timestamp,
            }
            delivered = await manager.send_personal_message(forward_payload, recipient_id)

            if delivered:
                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute("UPDATE messages SET delivered = 1 WHERE id = ?", (db_message_id,))
                conn.commit()
                conn.close()

            await websocket.send_text(json.dumps({
                "type": "ack",
                "id": db_message_id,
                "recipient_id": recipient_id,
                "status": "delivered" if delivered else "pending",
                "created_at": created_at
            }))
            
    except WebSocketDisconnect:
        manager.disconnect(user_id)
    except Exception as e:
        print(f"WS error with user {user_id}: {e}")
        manager.disconnect(user_id)
