from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    firebase_credentials_path: str = "firebase-service-account.json"
    firebase_credentials_json: str = ""
    critical_alerts_enabled: bool = False
    monitor_auth_url: str = ""
    google_oauth_client_id: str = ""
    internal_api_key: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
