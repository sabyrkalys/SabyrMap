from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql://alpinequest:alpinequest@localhost:5433/alpinequest"
    JWT_SECRET_KEY: str = "dev-secret-change-me"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    # Single-user mode: access is protected outside the app (VPN), so every
    # request is served as SINGLE_USER_EMAIL and no token is required.
    AUTH_DISABLED: bool = False
    SINGLE_USER_EMAIL: str = "alpinequest.dev@example.com"

    # Map server. PUBLIC_HOST is the name clients use; tiles are behind nginx
    # at https://PUBLIC_HOST/tiles unless TILES_PUBLIC_URL says otherwise
    # (dev: Martin directly at http://localhost:3000).
    PUBLIC_HOST: str = "localhost"
    TILES_PUBLIC_URL: str | None = None
    # Martin inside the compose network: the worker fetches glyphs and sprites
    # from it for offline styles.
    MARTIN_URL: str = "http://martin:3000"
    # Paths inside the containers (TILES_DIR/REGIONS_DIR in .env are the host
    # side of the bind mounts).
    TILES_PATH: str = "/srv/tiles"
    REGIONS_PATH: str = "/srv/regions"

    # Offline region limits.
    REGION_MAX_BYTES: int = 500 * 1024 * 1024
    REGION_MAX_ZOOM: int = 17
    REGION_MAX_PER_HOUR: int = 5
    REGION_TTL_HOURS: int = 24
    REGION_MAX_PARALLEL: int = 2

    @property
    def tiles_public_url(self) -> str:
        return (self.TILES_PUBLIC_URL or f"https://{self.PUBLIC_HOST}/tiles").rstrip("/")

    class Config:
        env_file = ".env"


settings = Settings()
