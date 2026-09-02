"""
Firebase Cloud Messaging helper for topic-based push notifications.
"""
import os
import json
import firebase_admin
from firebase_admin import credentials, messaging

_firebase_app = None


def _get_firebase_app():
    """
    Lazily initializes Firebase Admin SDK.
    Supports both local file (firebase_service_account.json) and
    FIREBASE_SERVICE_ACCOUNT_JSON env var (for Render deployment).
    """
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    cred_path = os.getenv("FIREBASE_CREDENTIALS", "firebase_service_account.json")
    if os.path.exists(cred_path):
        cred = credentials.Certificate(cred_path)
    else:
        env_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
        if env_json:
            try:
                cred_dict = json.loads(env_json)
                cred = credentials.Certificate(cred_dict)
            except Exception as e:
                raise RuntimeError(
                    f"Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON env var: {e}"
                )
        else:
            raise FileNotFoundError(
                f"Neither '{cred_path}' file nor FIREBASE_SERVICE_ACCOUNT_JSON env var found. "
                "Push notifications are disabled."
            )

    _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def send_bus_notification(topic: str, bus_number: str, message: str):
    """Send push notification to an FCM topic."""
    _get_firebase_app()
    notification = messaging.Message(
        notification=messaging.Notification(
            title=f"Bus {bus_number}",
            body=message,
        ),
        topic=topic,
    )
    response = messaging.send(notification)
    print(f"[FCM BACKEND SUCCESS] Sent notification to topic '{topic}': message_id={response}")
    return response