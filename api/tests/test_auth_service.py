from app.services.auth import hash_password, verify_password


def test_hash_password_verifies_with_correct_password():
    hashed = hash_password("correct horse battery staple")
    assert verify_password("correct horse battery staple", hashed) is True


def test_verify_password_rejects_wrong_password():
    hashed = hash_password("correct horse battery staple")
    assert verify_password("wrong password", hashed) is False


def test_hash_password_output_differs_each_call():
    assert hash_password("same-password") != hash_password("same-password")


import uuid
from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app.config import settings
from app.services.auth import InvalidTokenError, create_access_token, decode_access_token


def test_create_and_decode_access_token_roundtrip():
    user_id = uuid.uuid4()
    token = create_access_token(user_id)
    assert decode_access_token(token) == user_id


def test_decode_access_token_rejects_garbage():
    with pytest.raises(InvalidTokenError):
        decode_access_token("not-a-real-token")


def test_decode_access_token_rejects_expired_token():
    expired_payload = {
        "sub": str(uuid.uuid4()),
        "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
    }
    token = jwt.encode(expired_payload, settings.JWT_SECRET_KEY, algorithm="HS256")
    with pytest.raises(InvalidTokenError):
        decode_access_token(token)


def test_decode_access_token_rejects_wrong_signature():
    payload = {
        "sub": str(uuid.uuid4()),
        "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
    }
    token = jwt.encode(payload, "a-different-secret-key", algorithm="HS256")
    with pytest.raises(InvalidTokenError):
        decode_access_token(token)
