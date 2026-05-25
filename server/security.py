import hashlib
import os
import jwt
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

SECRET_KEY = os.environ.get("ACRYPDOM_SECRET_KEY", "dev_key_change_me_in_prod")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7 # 7 days

security_scheme = HTTPBearer()

def hash_password(password: str) -> str:
    salt = os.urandom(16)
    iterations = 100000
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return f"pbkdf2:sha256:{iterations}${salt.hex()}${dk.hex()}"

def verify_password(password: str, hashed_password: str) -> bool:
    try:
        parts = hashed_password.split("$")
        if len(parts) != 3:
            return False
        meta, salt_hex, dk_hex = parts
        iterations = int(meta.split(":")[-1])
        salt = bytes.fromhex(salt_hex)
        dk_expected = bytes.fromhex(dk_hex)
        dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
        return dk == dk_expected
    except Exception:
        return False

def create_access_token(user_id: int, username: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode = {
        "sub": str(user_id),
        "username": username,
        "exp": expire
    }
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_current_user_id(credentials: HTTPAuthorizationCredentials = Security(security_scheme)) -> int:
    token = credentials.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid session token payload",
            )
        return int(user_id)
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired or invalid token",
        )
