#fcm.py
import firebase_admin
from firebase_admin import credentials, messaging
from app.core.config import settings

if not firebase_admin._apps:
    cred = credentials.Certificate(settings.firebase_credentials_path)
    firebase_admin.initialize_app(cred)

def _send_data_only(token: str, data: dict):
    """Send a HIGH-priority data-only message.
    Used for call notifications going to the listener — flutter_callkit_incoming
    handles its own UI, so we must NOT include a notification block which would
    cause Android to show a duplicate system notification that fights callkit."""
    message = messaging.Message(
        data=data,
        token=token,
        android=messaging.AndroidConfig(
            priority="high",
            ttl=30,
        ),
    )
    response = messaging.send(message)
    print(f"[FCM] Sent '{data.get('type')}' (data-only) → {token[:20]}... | {response}")

def _send_with_notification(token: str, data: dict, title: str, body: str):
    """Send a HIGH-priority message WITH a notification block.
    Used for non-call signals (accepted/rejected/cancelled) where the app may
    be killed and we need the notification block to wake it, and there is no
    callkit UI conflict."""
    message = messaging.Message(
        data=data,
        notification=messaging.Notification(title=title, body=body),
        token=token,
        android=messaging.AndroidConfig(
            priority="high",
            ttl=30,
            notification=messaging.AndroidNotification(
                channel_id="call_notifications",
                priority="max",
                visibility="public",
                default_vibrate_timings=True,
                default_sound=True,
            ),
        ),
    )
    response = messaging.send(message)
    print(f"[FCM] Sent '{data.get('type')}' (notify) → {token[:20]}... | {response}")

def send_call_notification(fcm_token: str, room_name: str, caller_name: str, caller_id: int, call_id: int, call_type: str = "audio"):
    """Notify the listener of an incoming call.
    Data-only so flutter_callkit_incoming can render its own native call UI
    without conflicting with an Android system notification."""
    _send_data_only(
        token=fcm_token,
        data={
            "type": "call",
            "room_name": room_name,
            "caller_name": caller_name,
            "caller_id": str(caller_id),
            "call_id": str(call_id),
            "call_type": call_type,
        },
    )

def send_call_accepted(fcm_token: str, call_id: int, room_name: str, user_token: str, livekit_url: str):
    """Notify the user that the listener accepted — includes their LiveKit token so they can join."""
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "call_accepted",
            "call_id": str(call_id),
            "room_name": room_name,
            "token": user_token,
            "livekit_url": livekit_url,
        },
        title="Call Accepted",
        body="The listener accepted your call.",
    )

def send_call_cancelled(fcm_token: str, call_id: int):
    """Notify the listener that the user cancelled before they answered."""
    _send_data_only(
        token=fcm_token,
        data={
            "type": "call_cancelled",
            "call_id": str(call_id),
        },
    )

def send_call_rejected(fcm_token: str, call_id: int):
    """Notify the user that the listener rejected their call."""
    _send_data_only(
        token=fcm_token,
        data={
            "type": "call_rejected",
            "call_id": str(call_id),
        },
    )

def send_call_ended(fcm_token: str, call_id: int):
    """Notify a participant that the call has ended."""
    _send_data_only(
        token=fcm_token,
        data={
            "type": "call_ended",
            "call_id": str(call_id),
        },
    )


def send_call_coin_exceeded(fcm_token: str, call_id: int):
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "call_coin_exceeded",
            "call_id": str(call_id),
        },
        title="Call Ended",
        body="User ran out of coins",
    )


def send_force_logout(fcm_token: str):
    """Tell a device to log out immediately — used when admin deactivates the account."""
    _send_data_only(
        token=fcm_token,
        data={
            "type": "force_logout",
        },
    )


def send_chat_message(fcm_token: str, sender_name: str, message: str, user_id: int, listener_id: int, sender_type: str):
    """Notify the other party of a new chat message."""
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "chat_message",
            "user_id": str(user_id),
            "listener_id": str(listener_id),
            "sender_type": sender_type,
        },
        title=sender_name,
        body=message,
    )
