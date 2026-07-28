#fcm.py
import firebase_admin
from firebase_admin import credentials, messaging
from app.core.config import settings

if not firebase_admin._apps:
    cred = credentials.Certificate(settings.firebase_credentials_path)
    firebase_admin.initialize_app(cred)

def _send_data_only(token: str, data: dict, ttl: int = 30):
    """Send a HIGH-priority data-only message.
    Used for call notifications going to the listener — flutter_callkit_incoming
    handles its own UI, so we must NOT include a notification block which would
    cause Android to show a duplicate system notification that fights callkit."""
    message = messaging.Message(
        data=data,
        token=token,
        android=messaging.AndroidConfig(
            priority="high",
            ttl=ttl,
        ),
    )
    response = messaging.send(message)
    print(f"[FCM] Sent '{data.get('type')}' (data-only) → {token[:20]}... | {response}")

def _send_with_notification(token: str, data: dict, title: str, body: str, channel_id: str = "call_notifications", ttl: int = 30, collapse_key: str | None = None):
    """Send a HIGH-priority message WITH a notification block.
    Used for non-call signals (accepted/rejected/cancelled) where the app may
    be killed and we need the notification block to wake it, and there is no
    callkit UI conflict."""
    android_kwargs = {"priority": "high", "ttl": ttl}
    if collapse_key:
        android_kwargs["collapse_key"] = collapse_key
    message = messaging.Message(
        data=data,
        notification=messaging.Notification(title=title, body=body),
        token=token,
        android=messaging.AndroidConfig(
            notification=messaging.AndroidNotification(
                channel_id=channel_id,
                priority="max",
                visibility="public",
                default_vibrate_timings=True,
                default_sound=True,
            ),
            **android_kwargs,
        ),
    )
    response = messaging.send(message)
    print(f"[FCM] Sent '{data.get('type')}' (notify) → {token[:20]}... | {response}")

def send_call_notification(fcm_token: str, room_name: str, caller_name: str, caller_id: int, call_id: int, call_type: str = "audio", caller_photo_url: str = ""):
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
            "caller_photo_url": caller_photo_url or "",
        },
    )

def send_call_accepted(fcm_token: str, call_id: int, room_name: str, user_token: str, livekit_url: str):
    """Notify the user that the listener accepted — includes their LiveKit token so they can join.
    Data-only: the user is actively on the call screen listening for this signal in real time;
    a notification block risks the OS tray intercepting delivery instead of firing onMessage."""
    _send_data_only(
        token=fcm_token,
        data={
            "type": "call_accepted",
            "call_id": str(call_id),
            "room_name": room_name,
            "token": user_token,
            "livekit_url": livekit_url,
        },
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

def send_call_missed(fcm_token: str, call_id: int):
    """Notify the listener that they missed a call (did not respond in time)."""
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "call_missed",
            "call_id": str(call_id),
        },
        title="Missed Call",
        body="You missed a call.",
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


def send_withdrawal_decision(fcm_token: str, request_id: int, status: str, coins: int):
    """Notify a listener that their withdrawal request was approved or rejected."""
    if status == "approved":
        title = "Withdrawal Approved"
        body = f"Your withdrawal request for {coins} coins was approved."
    else:
        title = "Withdrawal Rejected"
        body = f"Your withdrawal request for {coins} coins was rejected."
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "withdrawal_decision",
            "request_id": str(request_id),
            "status": status,
        },
        title=title,
        body=body,
    )


def send_chat_message(fcm_token: str, sender_name: str, message: str, user_id: int, listener_id: int, sender_type: str, message_id: int, client_id: str | None = None):
    """Notify the other party of a new chat message.
    Includes full message content so the background isolate can cache it
    offline and ack delivery even if the app is fully closed."""
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "chat_message",
            "id": str(message_id),
            "client_id": client_id or "",
            "user_id": str(user_id),
            "listener_id": str(listener_id),
            "sender_type": sender_type,
            "message": message,
            "sender_name": sender_name,
        },
        title=sender_name,
        body=message,
        channel_id="chat_messages",
        ttl=86400,
        collapse_key=f"chat_{sender_type}_{user_id}_{listener_id}",
    )


def send_chat_summary(fcm_token: str, sender_name: str, messages: list[dict], user_id: int, listener_id: int, sender_type: str):
    """Notify the other party of one or more undelivered chat messages in a
    single collapsible push. `messages` is a list of dicts each containing
    id, client_id, message. When several of these are sent in quick succession
    while the recipient is offline, FCM/Android collapse them into just the
    last one delivered — since every push here carries the FULL undelivered
    set, whichever push survives still lets the client ack every message."""
    import json
    count = len(messages)
    body = messages[-1]["message"] if count == 1 else f"{count} new messages"
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "chat_summary",
            "user_id": str(user_id),
            "listener_id": str(listener_id),
            "sender_type": sender_type,
            "sender_name": sender_name,
            "messages": json.dumps(messages),
        },
        title=sender_name,
        body=body,
        channel_id="chat_messages",
        ttl=86400,
        collapse_key=f"chat_{sender_type}_{user_id}_{listener_id}",
    )


def send_delivery_status(fcm_token: str, message_ids: list[int], status: str, user_id: int, listener_id: int):
    _send_data_only(
        token=fcm_token,
        data={
            "type": "message_status_bulk",
            "ids": ",".join(str(i) for i in message_ids),
            "status": status,
            "user_id": str(user_id),
            "listener_id": str(listener_id),
        },
        ttl=86400,
    )

