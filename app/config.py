import os

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://forge_app:forge_app_lab_password@localhost:5432/forgetrack")
SECRET_KEY = os.environ.get("SECRET_KEY", "local-lab-session-key-not-a-production-secret")
