from datetime import datetime, timezone

from app.core.ws_manager import manager


async def broadcast_listener_presence(listener) -> None:
    online = listener.effective_online
    event = {"type": "listener_online" if online else "listener_offline", "listener_id": listener.id}
    if not online and listener.last_seen:
        event["last_seen"] = listener.last_seen.isoformat()
    await manager.broadcast_to_all_users(event)
    await manager.broadcast_to_all_users({
        "type": "listener_presence",
        "listener_id": listener.id,
        "presence_online": online,
    })
    await manager.broadcast_to_admins({
        "type": "listener_status",
        "id": listener.id,
        "is_online": online,
        "admin_forced_offline": bool(listener.admin_forced_offline),
        "status_on": bool(listener.is_online) and not bool(listener.admin_forced_offline),
    })


async def reject_calls_if_offline(db, listener) -> None:
    if listener.effective_online:
        return
    from app.routers.call import reject_ringing_calls_for_listener
    await reject_ringing_calls_for_listener(db, listener.id)


async def broadcast_listener_live(listener_id: int, live: bool) -> None:
    await manager.broadcast_to_all_users({
        "type": "listener_live",
        "listener_id": listener_id,
        "is_live": live,
        "active_at": datetime.now(timezone.utc).isoformat(),
    })
