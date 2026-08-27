"""
Firebase Cloud Messaging helper.
See guide STEP 6 — Firebase Push Notifications, section 5.3
"Send Notification from Backend".
"""
import os
import firebase_admin
from firebase_admin import credentials, messaging

_firebase_app = None


def _get_firebase_app():
    """
    Lazily initializes Firebase only when a notification is actually
    sent, instead of at import time. This lets the rest of the
    backend run fine even before you've set up
    firebase_service_account.json.
    """
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    cred_path = os.getenv("FIREBASE_CREDENTIALS", "firebase_service_account.json")
    if not os.path.exists(cred_path):
        raise FileNotFoundError(
            f"'{cred_path}' not found. Push notifications are disabled until "
            "you download your Firebase service account key (see STEP 6 / "
            "Phase 8 of the setup guide) and place it in the backend folder."
        )

    cred = credentials.Certificate(cred_path)
    _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def send_bus_notification(fcm_token: str, bus_number: str, message: str):
    """Send push notification to a parent."""
    _get_firebase_app()
    notification = messaging.Message(
        notification=messaging.Notification(
            title=f"Bus {bus_number}",
            body=message,
        ),
        token=fcm_token,
    )
    messaging.send(notification)

# Example: call this when bus is near student's stop
# send_bus_notification(token, "TN09AB1234", "Your bus is 2 stops away!")