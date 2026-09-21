from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql://alpinequest:alpinequest@localhost:5433/alpinequest"
    JWT_SECRET_KEY: str = "dev-secret-change-me"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    # Single-user mode: access is protected outside the app (VPN), so every
    # request is served as SINGLE_USER_EMAIL and no token is required.
    AUTH_DISABLED: bool = False
    SINGLE_USER_EMAIL: str = "alpinequest.dev@example.com"

    class Config:
        env_file = ".env"


settings = Settings()
