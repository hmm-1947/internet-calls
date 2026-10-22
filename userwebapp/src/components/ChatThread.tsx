import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly, InsufficientCoinsError } from "../lib/api";
import { MAX_CHAT_LENGTH } from "../lib/config";
import { socket, type WsEvent } from "../lib/ws";
import { VoiceRecorder } from "../lib/voice";
import { cx, isLive, dayLabel, formatDuration, humanDuration, parseDate, timeLabel, uuid } from "../lib/util";
import type { ChatMsg, Listener } from "../lib/types";
import { useApp } from "../state/app";
import { useCall } from "../state/call";
import { Avatar, BadgePill, PageLoader, Spinner } from "./ui";
import { GiftIcon, GiftSheet } from "./GiftSheet";
import { VoicePlayer } from "./VoicePlayer";
import { useCallRules } from "./ListenerCard";
import {
  IconBack, IconCheck, IconCheckAll, IconGift, IconMic, IconPhone, IconSend, IconTrash, IconVideo,
} from "./icons";

const PAGE = 25;

function upsert(list: ChatMsg[], msg: ChatMsg): ChatMsg[] {
  const i = list.findIndex((m) => (m.id && msg.id && m.id === msg.id) || (m.client_id && msg.client_id && m.client_id === msg.client_id));
  if (i === -1) return [...list, msg];
  const next = list.slice();
  next[i] = { ...list[i], ...msg, pending: false, failed: false };
  return next;
}

function Ticks({ m }: { m: ChatMsg }) {
  if (m.pending) return <span className="text-[10px] text-white/60">sending…</span>;
  if (m.failed) return <span className="text-[10px] font-bold text-yellow-200">failed · tap to retry</span>;
  if (m.status === "read" || m.is_read) return <IconCheckAll size={14} className="text-sky-300" />;
  if (m.status === "delivered") return <IconCheckAll size={14} className="text-white/60" />;
  return <IconCheck size={14} className="text-white/60" />;
}

function callText(m: ChatMsg): string {
  const kind = m.call_type === "video" ? "Video call" : "Voice call";
  const st = m.call_status;
  if (st === "rejected") return `${kind} · Declined`;
  if (st === "missed") return `${kind} · Not answered`;
  if (st === "cancelled") return `${kind} · Cancelled`;
  if (m.call_duration_seconds) return `${kind} · ${humanDuration(m.call_duration_seconds)}`;
  return kind;
}

export function ChatThread({ listenerId, onBack }: { listenerId: number; onBack: () => void }) {
  const { me, listeners, threads, setActiveChat, refreshMe, refreshThreads, toast } = useApp();
  const { startCall } = useCall();
  const nav = useNavigate();
  const [msgs, setMsgs] = useState<ChatMsg[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [fetched, setFetched] = useState<Listener | null>(null);
  const [typing, setTyping] = useState(false);
  const [text, setText] = useState("");
  const [giftOpen, setGiftOpen] = useState(false);
  const [rec, setRec] = useState<{ seconds: number } | null>(null);
  const [sendingVoice, setSendingVoice] = useState(false);

  const scroller = useRef<HTMLDivElement>(null);
  const stick = useRef(true);
  const recorder = useRef<VoiceRecorder | null>(null);
  const typingTimer = useRef<number | undefined>();
  const typingOff = useRef<number | undefined>();
  const typingSent = useRef(false);
  const taRef = useRef<HTMLTextAreaElement>(null);

  const thread = threads.find((t) => t.listener_id === listenerId);
  const listener: Listener | null = listeners.find((l) => l.id === listenerId) ?? fetched;
  const name = listener?.name ?? thread?.listener_name ?? "Listener";
  const photo = listener?.photo_url ?? thread?.photo_url ?? null;
  const online = listener ? isLive(listener) : !!(thread?.presence_online ?? thread?.is_online);
  const rules = useCallRules(listener ?? { is_online: false, is_in_call: false, video_call_enabled: false });
  const voiceOk = VoiceRecorder.supported();
  const cost = me?.chat_message_coin_cost ?? 0;

  useEffect(() => {
    if (listeners.find((l) => l.id === listenerId)) return;
    api.listener(listenerId).then(setFetched).catch(() => undefined);
  }, [listenerId, listeners.length]);

  const load = useCallback(async () => {
    try {
      const rows = await api.messages(listenerId);
      setMsgs((cur) => {
        const pend = cur.filter((m) => m.pending || m.failed);
        return pend.reduce((acc, m) => upsert(acc, m), rows);
      });
      setHasMore(rows.length >= PAGE);
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setLoading(false);
    }
  }, [listenerId]);

  useEffect(() => {
    setMsgs([]);
    setLoading(true);
    setText("");
    stick.current = true;
    setActiveChat(listenerId);
    void load().then(() => { void refreshThreads(); });
    return () => {
      setActiveChat(null);
      recorder.current?.cancel();
      recorder.current = null;
      window.clearTimeout(typingTimer.current);
      window.clearTimeout(typingOff.current);
      if (typingSent.current) socket.sendTyping(listenerId, false);
      typingSent.current = false;
    };
  }, [listenerId]);

  useEffect(() => {
    const onVis = () => { if (document.visibilityState === "visible") { void api.markRead(listenerId).catch(() => undefined); void refreshThreads(); } };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, [listenerId]);

  useEffect(() => {
    return socket.on((e: WsEvent) => {
      switch (e.type) {
        case "socket_connected":
          void load();
          break;
        case "chat_message": {
          if (e.listener_id !== listenerId) break;
          const m = e as unknown as ChatMsg;
          setMsgs((cur) => upsert(cur, m));
          if (e.sender_type === "listener") {
            setTyping(false);
            if (document.visibilityState === "visible") void api.markRead(listenerId).catch(() => undefined);
          }
          break;
        }
        case "message_status":
          setMsgs((cur) => cur.map((m) => ((e.id && m.id === e.id) || (e.client_id && m.client_id === e.client_id) ? { ...m, id: m.id ?? e.id, status: e.status, pending: false } : m)));
          break;
        case "message_status_bulk": {
          const ids: number[] = e.ids || [];
          setMsgs((cur) => cur.map((m) => (m.id && ids.includes(m.id) ? { ...m, status: e.status } : m)));
          break;
        }
        case "read_receipt": {
          if (e.listener_id !== listenerId) break;
          const ids: number[] = e.message_ids || [];
          setMsgs((cur) => cur.map((m) => (m.id && ids.includes(m.id) ? { ...m, status: "read", is_read: true, read_at: e.read_at } : m)));
          break;
        }
        case "message_edited":
          if (e.listener_id === listenerId) setMsgs((cur) => upsert(cur, e as unknown as ChatMsg));
          break;
        case "message_deleted":
          if (e.listener_id === listenerId) setMsgs((cur) => cur.map((m) => (m.id === e.id ? { ...m, is_deleted: true, message: "", audio_url: null } : m)));
          break;
        case "typing":
          if (e.listener_id === listenerId) {
            setTyping(!!e.is_typing);
            window.clearTimeout(typingOff.current);
            if (e.is_typing) typingOff.current = window.setTimeout(() => setTyping(false), 6000);
          }
          break;
      }
    });
  }, [listenerId, load]);

  useEffect(() => {
    const el = scroller.current;
    if (el && stick.current) el.scrollTop = el.scrollHeight;
  }, [msgs.length, typing, rec, loading]);

  const onScroll = () => {
    const el = scroller.current;
    if (!el) return;
    stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 120;
  };

  const loadOlder = async () => {
    const first = msgs.find((m) => m.id);
    if (!first?.id || loadingOlder) return;
    setLoadingOlder(true);
    const el = scroller.current;
    const prevH = el?.scrollHeight ?? 0;
    try {
      const rows = await api.messages(listenerId, first.id);
      stick.current = false;
      setMsgs((cur) => rows.reduce((acc, m) => (acc.some((x) => x.id === m.id) ? acc : [m, ...acc]), cur).sort((a, b) => (a.id && b.id ? a.id - b.id : 0)));
      setHasMore(rows.length >= PAGE);
      requestAnimationFrame(() => { if (el) el.scrollTop = el.scrollHeight - prevH; });
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setLoadingOlder(false);
    }
  };

  const stopTyping = () => {
    window.clearTimeout(typingTimer.current);
    if (typingSent.current) { typingSent.current = false; socket.sendTyping(listenerId, false); }
  };

  const onType = (v: string) => {
    setText(v.slice(0, MAX_CHAT_LENGTH));
    if (!typingSent.current && v.trim()) { typingSent.current = true; socket.sendTyping(listenerId, true); }
    window.clearTimeout(typingTimer.current);
    typingTimer.current = window.setTimeout(stopTyping, 2500);
  };

  const afterSend = () => { void refreshMe(); void refreshThreads(); };

  const sendText = async (retry?: ChatMsg) => {
    const body = (retry?.message ?? text).trim();
    if (!body) return;
    stopTyping();
    const clientId = retry?.client_id ?? uuid();
    const pending: ChatMsg = retry
      ? { ...retry, pending: true, failed: false }
      : {
          id: null, client_id: clientId, user_id: me?.id ?? 0, listener_id: listenerId, sender_type: "user", message: body, message_type: "text",
          audio_url: null, audio_duration: null, gift_id: null, gift_name: null, gift_icon: null, gift_coins: null, call_id: null, call_type: null,
          call_status: null, call_duration_seconds: null, status: "sending", is_read: false, delivered_at: null, read_at: null, edited_at: null,
          is_deleted: false, created_at: new Date().toISOString(), pending: true,
        };
    stick.current = true;
    setMsgs((cur) => upsert(cur, pending));
    if (!retry) { setText(""); taRef.current?.focus(); }
    try {
      const saved = await api.sendMessage(listenerId, body, clientId);
      setMsgs((cur) => upsert(cur, saved));
      afterSend();
    } catch (e) {
      if (e instanceof InsufficientCoinsError) {
        setMsgs((cur) => cur.filter((m) => m.client_id !== clientId));
        if (!retry) setText(body);
        toast("You need more coins to send messages", "error");
        nav("/upgrade");
        return;
      }
      setMsgs((cur) => cur.map((m) => (m.client_id === clientId ? { ...m, pending: false, failed: true } : m)));
      toast(friendly(e), "error");
    }
  };

  const submit = (e?: React.FormEvent) => {
    e?.preventDefault();
    void sendText();
  };

  const onKey = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); submit(); }
  };

  const startRecording = async () => {
    if (!voiceOk) { toast("Voice notes are not supported in this browser", "error"); return; }
    const r = new VoiceRecorder();
    try {
      await r.start();
    } catch (e) {
      toast(friendly(e), "error");
      return;
    }
    recorder.current = r;
    setRec({ seconds: 0 });
  };

  useEffect(() => {
    if (!rec) return;
    const t = window.setInterval(() => {
      const s = Math.floor(recorder.current?.elapsed() ?? 0);
      if (s >= 300) void finishRecording(true);
      else setRec({ seconds: s });
    }, 250);
    return () => window.clearInterval(t);
  }, [!!rec]);

  const cancelRecording = () => {
    recorder.current?.cancel();
    recorder.current = null;
    setRec(null);
  };

  const finishRecording = async (send: boolean) => {
    const r = recorder.current;
    recorder.current = null;
    setRec(null);
    if (!r) return;
    if (!send) { r.cancel(); return; }
    const out = await r.stop();
    if (!out) return;
    setSendingVoice(true);
    try {
      const saved = await api.sendVoice(listenerId, out.blob, `voice.${out.ext}`, out.seconds, uuid());
      stick.current = true;
      setMsgs((cur) => upsert(cur, saved));
      afterSend();
    } catch (e) {
      if (e instanceof InsufficientCoinsError) { toast("You need more coins to send messages", "error"); nav("/upgrade"); }
      else toast(friendly(e), "error");
    } finally {
      setSendingVoice(false);
    }
  };

  const rows = useMemo(() => {
    const out: { key: string; day?: string; msg?: ChatMsg }[] = [];
    let last = "";
    msgs.forEach((m, i) => {
      const d = parseDate(m.created_at);
      const k = d ? d.toDateString() : "";
      if (k !== last) { last = k; out.push({ key: `d${i}`, day: dayLabel(m.created_at) }); }
      out.push({ key: m.client_id || String(m.id) || `m${i}`, msg: m });
    });
    return out;
  }, [msgs]);

  return (
    <div className="flex h-full flex-col bg-bg">
      <div className="flex items-center gap-3 border-b border-line bg-bg/90 px-3 py-2.5 backdrop-blur safe-t">
        <button onClick={onBack} className="rounded-full p-2 hover:bg-white/10 md:hidden" aria-label="Back"><IconBack size={22} /></button>
        <button onClick={() => nav(`/listener/${listenerId}`)} className="flex min-w-0 flex-1 items-center gap-3 text-left">
          <Avatar src={photo} name={name} size={42} />
          <div className="min-w-0">
            <div className="flex items-center gap-2"><span className="truncate font-semibold">{name}</span><BadgePill tag={listener?.badge_tag ?? thread?.badge_tag} /></div>
            <div className={cx("text-xs", typing ? "text-online" : online ? "text-online" : "text-muted")}>
              {typing ? "typing…" : listener?.is_in_call ? "On a call" : online ? "Online" : "Offline"}
            </div>
          </div>
        </button>
        <button disabled={!rules.voice || !listener} onClick={() => listener && void startCall(listener, false)} className="rounded-full p-2.5 hover:bg-white/10 disabled:opacity-30" aria-label="Voice call"><IconPhone size={20} /></button>
        {listener?.video_call_enabled && (
          <button disabled={!rules.video} onClick={() => listener && void startCall(listener, true)} className="rounded-full p-2.5 hover:bg-white/10 disabled:opacity-30" aria-label="Video call"><IconVideo size={20} /></button>
        )}
        <button onClick={() => setGiftOpen(true)} className="rounded-full p-2.5 text-gold hover:bg-white/10" aria-label="Send gift"><IconGift size={20} /></button>
      </div>

      <div ref={scroller} onScroll={onScroll} className="min-h-0 flex-1 overflow-y-auto px-3 py-4 md:px-6">
        {loading ? <PageLoader /> : (
          <div className="mx-auto flex max-w-3xl flex-col gap-1.5">
            {hasMore && (
              <button onClick={() => void loadOlder()} disabled={loadingOlder} className="mx-auto mb-2 rounded-full bg-white/8 px-4 py-1.5 text-xs text-white/70 hover:bg-white/15" style={{ background: "rgba(255,255,255,0.07)" }}>
                {loadingOlder ? <Spinner size={12} /> : "Load earlier messages"}
              </button>
            )}
            {rows.length === 0 && <p className="py-16 text-center text-sm text-muted">Say hi to {name} 👋</p>}
            {rows.map((r) => {
              if (r.day) return <div key={r.key} className="my-2 self-center rounded-full px-3 py-1 text-[11px] text-white/60" style={{ background: "rgba(255,255,255,0.07)" }}>{r.day}</div>;
              const m = r.msg!;
              if (m.message_type === "call" && !m.is_deleted) {
                return (
                  <div key={r.key} className="my-1 flex items-center gap-2 self-center rounded-full border border-line bg-card px-4 py-1.5 text-xs text-white/70">
                    {m.call_type === "video" ? <IconVideo size={14} /> : <IconPhone size={14} />}
                    {callText(m)}
                    <span className="text-white/40">{timeLabel(m.created_at)}</span>
                  </div>
                );
              }
              const own = m.sender_type === "user";
              return (
                <div key={r.key} className={cx("group flex items-end gap-1.5", own ? "flex-row-reverse" : "")}>
                  <div
                    onClick={() => { if (m.failed) void sendText(m); }}
                    className={cx(
                      "relative max-w-[78%] rounded-2xl px-3.5 py-2 text-[15px] shadow-sm md:max-w-[65%]",
                      own ? "rounded-br-md bg-brand-soft text-white" : "rounded-bl-md bg-card text-white",
                      m.failed && "cursor-pointer opacity-80 ring-1 ring-yellow-300/60",
                    )}
                  >
                    {m.is_deleted ? (
                      <span className="text-sm italic text-white/60">Message deleted</span>
                    ) : m.message_type === "audio" && m.audio_url ? (
                      <VoicePlayer src={m.audio_url} duration={m.audio_duration} />
                    ) : m.message_type === "gift" ? (
                      <div className="flex items-center gap-3 py-1">
                        <GiftIcon icon={m.gift_icon} size={48} />
                        <div>
                          <div className="font-semibold">{own ? "You sent" : "Sent you"} {m.gift_name ?? "a gift"}</div>
                          {m.gift_coins ? <div className="text-xs text-white/70">{m.gift_coins} coins</div> : null}
                        </div>
                      </div>
                    ) : (
                      <span className="whitespace-pre-wrap break-words">{m.message}</span>
                    )}
                    <div className={cx("mt-0.5 flex items-center justify-end gap-1.5 text-[10px]", own ? "text-white/70" : "text-muted")}>
                      {m.edited_at && !m.is_deleted && <span>edited</span>}
                      <span>{timeLabel(m.created_at)}</span>
                      {own && <Ticks m={m} />}
                    </div>
                  </div>
                </div>
              );
            })}
            {typing && (
              <div className="flex w-fit items-center gap-1 rounded-2xl rounded-bl-md bg-card px-4 py-3">
                {[0, 1, 2].map((i) => <span key={i} className="h-1.5 w-1.5 animate-bounce rounded-full bg-white/60" style={{ animationDelay: `${i * 0.15}s` }} />)}
              </div>
            )}
          </div>
        )}
      </div>

      <div className="border-t border-line bg-[#0e0e0e] px-3 py-3 safe-b md:px-6">
        <div className="mx-auto max-w-3xl">
          {rec ? (
            <div className="flex items-center gap-3">
              <button onClick={cancelRecording} className="rounded-full p-3 text-red-400 hover:bg-white/10" aria-label="Discard"><IconTrash size={20} /></button>
              <div className="flex flex-1 items-center gap-3 rounded-full bg-card2 px-4 py-3">
                <span className="h-2.5 w-2.5 animate-pulse rounded-full bg-red-500" />
                <span className="text-sm tabular-nums">{formatDuration(rec.seconds)}</span>
                <span className="text-xs text-muted">Recording…</span>
              </div>
              <button onClick={() => void finishRecording(true)} className="flex h-12 w-12 items-center justify-center rounded-full bg-brand-soft hover:bg-brand" aria-label="Send voice note"><IconSend size={20} /></button>
            </div>
          ) : (
            <form onSubmit={submit}>
              <div className="flex items-end gap-2">
                <textarea
                  ref={taRef}
                  value={text}
                  onChange={(e) => onType(e.target.value)}
                  onKeyDown={onKey}
                  rows={1}
                  maxLength={MAX_CHAT_LENGTH}
                  placeholder="Type a message"
                  className="input max-h-32 min-w-0 flex-1 resize-none !rounded-2xl !py-3"
                />
                {!text.trim() ? (
                  <button type="button" onClick={() => void startRecording()} disabled={sendingVoice} className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-white/10 hover:bg-white/20 disabled:opacity-50" aria-label="Record voice note">
                    {sendingVoice ? <Spinner size={18} /> : <IconMic size={20} />}
                  </button>
                ) : (
                  <button className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-brand-soft hover:bg-brand" aria-label="Send">
                    <IconSend size={20} />
                  </button>
                )}
              </div>
              {(text.length > MAX_CHAT_LENGTH * 0.7 || cost > 0) && (
                <div className="mt-1 flex justify-between px-1 text-[11px] text-muted">
                  <span>{cost > 0 ? `${cost} coin${cost === 1 ? "" : "s"} per message` : ""}</span>
                  <span>{text.length}/{MAX_CHAT_LENGTH}</span>
                </div>
              )}
            </form>
          )}
        </div>
      </div>

      <GiftSheet open={giftOpen} onClose={() => setGiftOpen(false)} listenerId={listenerId} />
    </div>
  );
}
