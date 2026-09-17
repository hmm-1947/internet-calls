#fcm.py
from concurrent.futures import ThreadPoolExecutor

import firebase_admin
from firebase_admin import credentials, messaging
from app.core.config import settings

if not firebase_admin._apps:
    cred = credentials.Certificate(settings.firebase_credentials_path)
    firebase_admin.initialize_app(cred)

_executor = ThreadPoolExecutor(max_workers=16, thread_name_prefix="fcm")


def is_invalid_token_error(error: Exception) -> bool:
    text = str(error).lower()
    return "not found" in text or "registration-token-not-registered" in text or "invalid-registration-token" in text


def send_async(fn, *args, on_error=None, **kwargs):
    """Dispatch a blocking FCM send onto a worker thread.

    `messaging.send()` is a synchronous HTTPS round trip. Called inline from an
    `async def` endpoint it stalls the event loop, so everything else in flight
    (the caller's status poll, both websockets) waits behind it. Call-setup
    pushes are latency critical and nothing in the request needs their result,
    so they go through here instead."""
    def _run():
        try:
            fn(*args, **kwargs)
        except Exception as e:
            print(f"[FCM ERROR] background send {getattr(fn, '__name__', fn)} failed: {e}")
            if on_error is not None:
                try:
                    on_error(e)
                except Exception as hook_error:
                    print(f"[FCM ERROR] on_error hook failed: {hook_error}")

    _executor.submit(_run)

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

def send_call_missed(fcm_token: str, call_id: int, caller_name: str = ""):
    _send_data_only(
        token=fcm_token,
        data={
            "type": "call_missed",
            "call_id": str(call_id),
            "caller_name": caller_name or "",
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


def send_gift_received(fcm_token: str, gift_name: str, gift_coins: int, credited_coins: int, from_user_id: int, from_user_name: str):
    """Notify a listener that they received a gift."""
    _send_with_notification(
        token=fcm_token,
        data={
            "type": "gift_received",
            "gift_name": gift_name,
            "coins": str(gift_coins),
            "credited_coins": str(credited_coins),
            "from_user_id": str(from_user_id),
            "from_user_name": from_user_name,
        },
        title="You received a gift!",
        body=f"{from_user_name} sent you {gift_name} (+{credited_coins} coins)",
        channel_id="gift_notifications",
    )



def _send_chat_push(token: str, data: dict, title: str, body: str, thread_id: str, collapse_key: str | None = None, ttl: int = 86400):
    """Send a chat push.

    Android gets a DATA-ONLY message on purpose. A `notification` block makes
    the OS post one tray notification — with its own sound — per message, which
    is exactly the behaviour we are replacing. Without it the app's FCM handler
    (foreground and background isolate alike) receives the data and renders a
    single stacked MessagingStyle notification per conversation, alerting only
    once per cooldown window. Data-only wake-ups are already proven in this app
    by the incoming-call path.

    iOS has no equivalent client-side rendering hook while backgrounded, so it
    still gets an APNs alert; `thread-id` at least groups a conversation into
    one stack in Notification Center."""
    apns_headers = {"apns-priority": "10", "apns-push-type": "alert"}
    if collapse_key:
        apns_headers["apns-collapse-id"] = collapse_key[:64]
    message = messaging.Message(
        data=data,
        token=token,
        android=messaging.AndroidConfig(
            priority="high",
            ttl=ttl,
            **({"collapse_key": collapse_key} if collapse_key else {}),
        ),
        apns=messaging.APNSConfig(
            headers=apns_headers,
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(title=title, body=body),
                    sound="default",
                    thread_id=thread_id,
                    content_available=True,
                ),
            ),
        ),
    )
    response = messaging.send(message)
    print(f"[FCM] Sent '{data.get('type')}' (chat) → {token[:20]}... | {response}")


def send_chat_message(fcm_token: str, sender_name: str, message: str, user_id: int, listener_id: int, sender_type: str, message_id: int, client_id: str | None = None, sender_photo_url: str | None = None):
    """Notify the other party of a new chat message.
    Includes full message content so the background isolate can cache it
    offline, ack delivery and render the stacked notification even if the app
    is fully closed.

    Deliberately NOT collapsible: the client now stacks messages itself, so
    every message needs to survive the trip. The collapsible variant is
    `send_chat_summary`, used when the recipient is offline."""
    _send_chat_push(
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
            "sender_photo_url": sender_photo_url or "",
        },
        title=sender_name,
        body=message,
        thread_id=f"chat_{sender_type}_{user_id}_{listener_id}",
    )


def send_chat_summary(fcm_token: str, sender_name: str, messages: list[dict], user_id: int, listener_id: int, sender_type: str, sender_photo_url: str | None = None):
    """Notify the other party of one or more undelivered chat messages in a
    single collapsible push. `messages` is a list of dicts each containing
    id, client_id, message. When several of these are sent in quick succession
    while the recipient is offline, FCM/Android collapse them into just the
    last one delivered — since every push here carries the FULL undelivered
    set, whichever push survives still lets the client ack every message and
    rebuild the complete stacked notification."""
    import json
    count = len(messages)
    body = messages[-1]["message"] if count == 1 else f"{count} new messages"
    _send_chat_push(
        token=fcm_token,
        data={
            "type": "chat_summary",
            "user_id": str(user_id),
            "listener_id": str(listener_id),
            "sender_type": sender_type,
            "sender_name": sender_name,
            "sender_photo_url": sender_photo_url or "",
            "messages": json.dumps(messages),
        },
        title=sender_name,
        body=body,
        thread_id=f"chat_{sender_type}_{user_id}_{listener_id}",
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

