"""
backend/notification_messages.py

Centralized bilingual notification text templates, titles, channels, and sounds.
Supported languages: Tamil ('ta') and English ('en').
"""

from typing import Dict, Tuple, Optional

# Supported languages list - keep in sync with app
SUPPORTED_LANGUAGES = ["ta", "en"]

# Canonical event names
EVENT_BUS_STARTED = "bus_started"
EVENT_TWO_STOPS_AWAY = "two_stops_away"
EVENT_REACHED_COLLEGE = "reached_college"

# Aliases for CLI convenience
EVENT_ALIASES = {
    "started": EVENT_BUS_STARTED,
    "bus_started": EVENT_BUS_STARTED,
    "near": EVENT_TWO_STOPS_AWAY,
    "two_stops_away": EVENT_TWO_STOPS_AWAY,
    "2_stops_away": EVENT_TWO_STOPS_AWAY,
    "arrived": EVENT_REACHED_COLLEGE,
    "reached_college": EVENT_REACHED_COLLEGE,
}

# Android notification channels (versioned) and raw sound asset names
EVENT_CHANNELS: Dict[str, Dict[str, Dict[str, str]]] = {
    EVENT_BUS_STARTED: {
        "ta": {"channel_id": "bus_started_ta_v3", "sound": "bus_started_ta"},
        "en": {"channel_id": "bus_started_en_v3", "sound": "bus_started_en"},
    },
    EVENT_TWO_STOPS_AWAY: {
        "ta": {"channel_id": "bus_near_ta_v3", "sound": "bus_near_ta"},
        "en": {"channel_id": "bus_near_en_v3", "sound": "bus_near_en"},
    },
    EVENT_REACHED_COLLEGE: {
        "ta": {"channel_id": "bus_arrived_ta_v3", "sound": "bus_arrived_ta"},
        "en": {"channel_id": "bus_arrived_en_v3", "sound": "bus_arrived_en"},
    },
}

TITLES: Dict[str, str] = {
    "en": "Bus {bus}",
    "ta": "பேருந்து {bus}",
}

MESSAGES: Dict[str, Dict[str, str]] = {
    EVENT_BUS_STARTED: {
        "en": "Bus has started from {stop}.",
        "ta": "பேருந்து {stop} நிறுத்தத்திலிருந்து புறப்பட்டது.",
    },
    EVENT_TWO_STOPS_AWAY: {
        "en": "Bus is 2 stops away from {stop}. Arriving in about {min} min.",
        "ta": "{stop} நிறுத்தத்திற்கு பேருந்து இன்னும் 2 நிறுத்தங்களில் உள்ளது. சுமார் {min} நிமிடங்களில் வரும்.",
    },
    f"{EVENT_TWO_STOPS_AWAY}_no_min": {
        "en": "Bus is 2 stops away from {stop}.",
        "ta": "{stop} நிறுத்தத்திற்கு பேருந்து இன்னும் 2 நிறுத்தங்களில் உள்ளது.",
    },
    EVENT_REACHED_COLLEGE: {
        "en": "Bus has reached {college}.",
        "ta": "பேருந்து {college} அடைந்தது.",
    },
}


def canonicalize_event(event: str) -> str:
    """Normalize input event name or alias to canonical form."""
    norm = str(event).strip().lower()
    return EVENT_ALIASES.get(norm, norm)


def get_channel_info(event: str, lang: str) -> Tuple[str, str]:
    """Retrieve (channel_id, sound_name) for an event and language."""
    c_event = canonicalize_event(event)
    info = EVENT_CHANNELS.get(c_event, {}).get(lang)
    if not info:
        info = EVENT_CHANNELS.get(c_event, {}).get("en", {"channel_id": "bus_near_en_v3", "sound": "bus_near_en"})
    return info["channel_id"], info["sound"]


def get_notification_content(event: str, lang: str, variables: dict) -> Tuple[str, str]:
    """
    Format (title, body) for given event, language, and variables.
    Supported variables: {bus}, {stop}, {college}, {min}.
    If {min} is None or missing for two_stops_away, falls back to version without minutes.
    """
    c_event = canonicalize_event(event)
    lang_code = lang if lang in SUPPORTED_LANGUAGES else "en"

    # Title
    bus_val = str(variables.get("bus", "")).strip() or "Bus"
    title_tpl = TITLES.get(lang_code, TITLES["en"])
    title = title_tpl.format(bus=bus_val)

    # Body
    if c_event == EVENT_TWO_STOPS_AWAY and (variables.get("min") is None or variables.get("min") == ""):
        body_tpl = MESSAGES.get(f"{EVENT_TWO_STOPS_AWAY}_no_min", {}).get(lang_code)
    else:
        body_tpl = MESSAGES.get(c_event, {}).get(lang_code)

    if not body_tpl:
        body_tpl = MESSAGES[c_event]["en"]

    safe_vars = {
        "bus": bus_val,
        "stop": str(variables.get("stop", "")),
        "college": str(variables.get("college", "")),
        "min": str(variables.get("min", "")),
    }

    body = body_tpl.format(**safe_vars)
    return title, body
