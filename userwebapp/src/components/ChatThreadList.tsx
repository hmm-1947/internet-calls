import { useMemo, useState } from "react";
import { api, friendly } from "../lib/api";
import { cx, humanDuration, listTimeLabel } from "../lib/util";
import type { Thread } from "../lib/types";
import { useApp } from "../state/app";
import { Avatar, BadgePill, Empty, PresenceDot } from "./ui";
import { IconArchive, IconChat, IconMore, IconMute, IconPin, IconSearch } from "./icons";

function preview(t: Thread): string {
  if (t.last_message_type === "audio") return "🎤 Voice message";
  if (t.last_message_type === "gift") return `🎁 ${t.last_message || "Gift"}`;
  if (t.last_message_type === "call") {
    const kind = t.last_call_type === "video" ? "Video call" : "Voice call";
    const st = t.last_call_status;
    if (st === "ended" || st === "completed" || st === "accepted") return `${kind}${t.last_call_duration_seconds ? ` · ${humanDuration(t.last_call_duration_seconds)}` : ""}`;
    if (st === "rejected") return `${kind} · Declined`;
    if (st === "missed") return `${kind} · Not answered`;
    if (st === "cancelled") return `${kind} · Cancelled`;
    return kind;
  }
  return t.last_message || "";
}

export function ChatThreadList({ activeId, onOpen }: { activeId: number | null; onOpen: (listenerId: number) => void }) {
  const { threads, setThreads, refreshThreads, toast } = useApp();
  const [q, setQ] = useState("");
  const [archived, setArchived] = useState(false);
  const [menu, setMenu] = useState<number | null>(null);

  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    return threads.filter((t) => t.is_archived === archived && (!s || t.listener_name.toLowerCase().includes(s)));
  }, [threads, q, archived]);
  const archivedCount = threads.filter((t) => t.is_archived).length;

  const setting = async (t: Thread, patch: { is_pinned?: boolean; is_archived?: boolean; is_muted?: boolean }) => {
    setMenu(null);
    const prev = threads;
    setThreads((ts) => ts.map((x) => (x.listener_id === t.listener_id ? { ...x, ...patch } : x)));
    try {
      await api.chatSettings(t.listener_id, patch);
      void refreshThreads();
    } catch (e) {
      setThreads(() => prev);
      toast(friendly(e), "error");
    }
  };

  return (
    <div className="flex h-full flex-col" onClick={() => setMenu(null)}>
      <div className="space-y-3 border-b border-line px-4 pb-3 pt-4 safe-t">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold">{archived ? "Archived" : "Chats"}</h1>
          {(archivedCount > 0 || archived) && (
            <button onClick={(e) => { e.stopPropagation(); setArchived((a) => !a); }} className="text-sm font-semibold text-brand-soft">
              {archived ? "Back to chats" : `Archived (${archivedCount})`}
            </button>
          )}
        </div>
        <div className="relative">
          <IconSearch size={17} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-ink/40" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search chats" className="input !py-2.5 !pl-10" />
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {shown.length === 0 ? (
          <Empty icon={<IconChat size={44} />} title={archived ? "No archived chats" : q ? "No chats found" : "No chats yet"} text={archived || q ? undefined : "Start a conversation from a listener's profile."} />
        ) : (
          shown.map((t) => (
            <div
              key={t.listener_id}
              onClick={() => onOpen(t.listener_id)}
              className={cx(
                "group relative flex cursor-pointer items-center gap-3 border-b border-line px-4 py-3 transition hover:bg-black/5",
                activeId === t.listener_id && "bg-black/8",
              )}
              style={activeId === t.listener_id ? { background: "rgba(255,255,255,0.07)" } : undefined}
            >
              <div className="relative">
                <Avatar src={t.photo_url} name={t.listener_name} size={52} />
                <PresenceDot online={!!(t.presence_online ?? t.is_online)} className="absolute -bottom-0.5 -right-0.5" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="truncate font-semibold">{t.listener_name}</span>
                  <BadgePill tag={t.badge_tag} />
                  {t.is_pinned && <IconPin size={13} className="text-ink/40" />}
                  {t.is_muted && <IconMute size={13} className="text-ink/40" />}
                </div>
                <div className={cx("mt-0.5 truncate text-sm", t.unread_count > 0 && !t.is_muted ? "font-medium text-ink" : "text-muted")}>{preview(t)}</div>
              </div>
              <div className="flex flex-col items-end gap-1.5">
                <span className="text-[11px] text-muted">{listTimeLabel(t.last_message_at)}</span>
                {t.unread_count > 0 ? (
                  <span className={cx("min-w-[20px] rounded-full px-1.5 py-0.5 text-center text-[11px] font-bold", t.is_muted ? "bg-black/20" : "bg-brand-soft")}>{t.unread_count > 99 ? "99+" : t.unread_count}</span>
                ) : <span className="h-5" />}
              </div>
              <button
                onClick={(e) => { e.stopPropagation(); setMenu(menu === t.listener_id ? null : t.listener_id); }}
                className="rounded-full p-1.5 text-ink/40 hover:bg-black/10 hover:text-ink md:opacity-0 md:group-hover:opacity-100"
                aria-label="Chat options"
              >
                <IconMore size={18} />
              </button>
              {menu === t.listener_id && (
                <div onClick={(e) => e.stopPropagation()} className="pop-in absolute right-4 top-14 z-20 w-44 overflow-hidden rounded-xl border border-line bg-card2 shadow-2xl">
                  <button className="flex w-full items-center gap-2 px-4 py-2.5 text-sm hover:bg-black/10" onClick={() => void setting(t, { is_pinned: !t.is_pinned })}><IconPin size={16} />{t.is_pinned ? "Unpin" : "Pin"}</button>
                  <button className="flex w-full items-center gap-2 px-4 py-2.5 text-sm hover:bg-black/10" onClick={() => void setting(t, { is_muted: !t.is_muted })}><IconMute size={16} />{t.is_muted ? "Unmute" : "Mute"}</button>
                  <button className="flex w-full items-center gap-2 px-4 py-2.5 text-sm hover:bg-black/10" onClick={() => void setting(t, { is_archived: !t.is_archived })}><IconArchive size={16} />{t.is_archived ? "Unarchive" : "Archive"}</button>
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
