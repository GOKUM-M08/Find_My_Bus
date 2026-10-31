"""
backend/notifications.py

Firebase Cloud Messaging helper for voice-based topic push notifications.
Supports:
1. Multi-language topics (bus_{busId}_stop_{stopId}_{lang} and bus_{busId}_all_{lang}).
2. High priority, 10-minute TTL, versioned channels, and raw sounds.
3. Backward-compatible SEND_LEGACY_TOPICS (default true).
4. Error resilience: catches and logs errors without leaking PII.
"""

import os
import json
import logging
from datetime import timedelta
from typing import Dict, Any, Optional, List

import firebase_admin
from firebase_admin import credentials, messaging

from notification_messages import (
    SUPPORTED_LANGUAGES,
    EVENT_TWO_STOPS_AWAY,
    canonicalize_event,
    get_channel_info,
    get_notification_content,
)

logger = logging.getLogger(__name__)

_firebase_app = None


def _get_firebase_app():
    """
    Lazily initializes Firebase Admin SDK.
    Supports local file credentials and FIREBASE_SERVICE_ACCOUNT_JSON env var.
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


def send_bus_notification(topic: str, bus_number: str, message: str) -> Optional[str]:
    """Legacy helper: send simple text notification to an FCM topic."""
    try:
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
    except Exception as e:
        logger.warning(f"[FCM Warning] Failed to send legacy notification to topic {topic}: {e}")
        return None


def send_alert(
    event: str,
    bus_id: str,
    stop_id: Optional[str] = None,
    variables: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Send voice-ready FCM push alert for a given event across all supported languages.
    Structure:
    - android.priority = high
    - android.ttl = 10 minutes
    - channel_id and raw sound set per event & language
    - data: event, bus_id, stop_id, channel_id
    - SEND_LEGACY_TOPICS (default true): also delivers plain topic for older clients.
    """
    c_event = canonicalize_event(event)
    vars_dict = dict(variables or {})
    results = {}

    try:
        _get_firebase_app()
    except Exception as e:
        logger.warning(f"[FCM Warning] Firebase initialization skipped/failed: {e}")
        return {"error": "firebase_not_available"}

    # 1. Send alert for each supported language
    for lang in SUPPORTED_LANGUAGES:
        try:
            channel_id, sound_name = get_channel_info(c_event, lang)
            title, body = get_notification_content(c_event, lang, vars_dict)

            if c_event == EVENT_TWO_STOPS_AWAY:
                if not stop_id:
                    continue
                topic = f"bus_{bus_id}_stop_{stop_id}_{lang}"
            else:
                topic = f"bus_{bus_id}_all_{lang}"

            android_config = messaging.AndroidConfig(
                priority="high",
                ttl=timedelta(minutes=10),
                notification=messaging.AndroidNotification(
                    channel_id=channel_id,
                    sound=sound_name,
                ),
            )

            data_payload = {
                "event": c_event,
                "bus_id": str(bus_id),
                "stop_id": str(stop_id or ""),
                "channel_id": channel_id,
            }

            msg = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                android=android_config,
                data=data_payload,
                topic=topic,
            )

            response = messaging.send(msg)
            results[lang] = response
            print(f"[FCM Alert Sent] Event: {c_event}, Topic: {topic}, Channel: {channel_id}, MsgId: {response}")
        except Exception as e:
            logger.warning(f"[FCM Alert Error] Failed sending {c_event} for {lang} (topic {topic}): {e}")
            results[lang] = None

    # 2. Legacy topic delivery during rollout (bus_{busId}_stop_{stopId})
    send_legacy = os.getenv("SEND_LEGACY_TOPICS", "true").lower() in ("true", "1", "yes")
    if send_legacy and stop_id and c_event == EVENT_TWO_STOPS_AWAY:
        legacy_topic = f"bus_{bus_id}_stop_{stop_id}"
        bus_name = vars_dict.get("bus", "Your Bus")
        _, legacy_body = get_notification_content(c_event, "en", vars_dict)
        try:
            legacy_resp = send_bus_notification(legacy_topic, bus_name, legacy_body)
            results["legacy"] = legacy_resp
        except Exception as e:
            logger.warning(f"[FCM Alert Error] Legacy topic notification failed for {legacy_topic}: {e}")

    return results