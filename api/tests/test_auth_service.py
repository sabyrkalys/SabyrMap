from app.services.auth import hash_password, verify_password


def test_hash_password_verifies_with_correct_password():
    hashed = hash_password("correct horse battery staple")
    assert verify_password("correct horse battery staple", hashed) is True


def test_verify_password_rejects_wrong_password():
    hashed = hash_password("correct horse battery staple")
    assert verify_password("wrong password", hashed) is False


def test_hash_password_output_differs_each_call():
    assert hash_password("same-password") != hash_password("same-password")
