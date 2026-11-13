import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { api, friendly, onSessionInvalid, session } from "../lib/api";
import { socket, type WsEvent } from "../lib/ws";
import { setTitleBadge, showChatNotification } from "../lib/notify";
import { disableWebPush, enableWebPush } from "../lib/push";
import type { AuthResponse, Listener, Me, Thread } from "../lib/types";

interface Toast { id: number; text: string; kind: "info" | "error" | "success" }

interface AppCtx {
  token: string | null;
  authUser: { id: number; name: string } | null;
  me: Me | null;
  listeners: Listener[];
  threads: Thread[];
  loadingListeners: boolean;
  listenersError: string | null;
  socketUp: boolean;
  unreadTotal: number;
  flash: string | null;
  login: (a: AuthResponse) => void;
  logout: (flash?: string) => Promise<void>;
  refreshMe: () => Promise<Me | null>;
  refreshListeners: () => Promise<void>;
  refreshThreads: () => Promise<void>;
  setThreads: (fn: (t: Thread[]) => Thread[]) => void;
  setActiveChat: (listenerId: number | null) => void;
  toast: (text: string, kind?: Toast["kind"]) => void;
  clearFlash: () => void;
  openChatRef: React.MutableRefObject<((listenerId: number) => void) | null>;
}

const Ctx = createContext<AppCtx | null>(null);
export const useApp = () => {
  const c = useContext(Ctx);
  if (!c) throw new Error("useApp outside provider");
  return c;
};

const FLASH_KEY = "lw_flash";

function sortListeners(list: Listener[]): Listener[] {
  return list
    .map((l, i) => ({ l, i }))
    .sort((a, b) => {
      const ai = !!a.l.last_interacted_at;
      const bi = !!b.l.last_interacted_at;
      if (ai !== bi) return ai ? -1 : 1;
      if (a.l.presence_online !== b.l.presence_online) return a.l.presence_online ? -1 : 1;
      return a.i - b.i;
    })
    .map((x) => x.l);
}

export function AppProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(session.token);
  const [authUser, setAuthUser] = useState(session.user);
  const [me, setMe] = useState<Me | null>(null);
  const [listeners, setListeners] = useState<Listener[]>([]);
  const [threads, setThreadsState] = useState<Thread[]>([]);
  const [loadingListeners, setLoadingListeners] = useState(false);
  const [listenersError, setListenersError] = useState<string | null>(null);
  const [socketUp, setSocketUp] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [flash, setFlash] = useState<string | null>(() => {
    try { const f = sessionStorage.getItem(FLASH_KEY); sessionStorage.removeItem(FLASH_KEY); return f; } catch { return null; }
  });
  const activeChat = useRef<number | null>(null);
  const toastId = useRef(0);
  const loggingOut = useRef(false);
  const openChatRef = useRef<((listenerId: number) => void) | null>(null);

  const toast = useCallback((text: string, kind: Toast["kind"] = "info") => {
    const id = ++toastId.current;
    setToasts((t) => [...t.slice(-3), { id, text, kind }]);
    window.setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4000);
  }, []);

  const refreshMe = useCallback(async () => {
    try { const m = await api.me(); setMe(m); return m; } catch { return null; }
  }, []);

  const refreshListeners = useCallback(async () => {
    setLoadingListeners(true);
    try {
      const l = await api.listeners();
      setListeners(sortListeners(l));
      setListenersError(null);
    } catch (e) {
      setListenersError(friendly(e));
    } finally {
      setLoadingListeners(false);
    }
  }, []);

  const refreshThreads = useCallback(async () => {
    try { setThreadsState(await api.threads()); } catch { /* keep old */ }
  }, []);

  const setThreads = useCallback((fn: (t: Thread[]) => Thread[]) => setThreadsState(fn), []);

  const login = useCallback((a: AuthResponse) => {
    session.save(a.token, a.id, a.name);
    loggingOut.current = false;
    setToken(a.token);
    setAuthUser({ id: a.id, name: a.name });
  }, []);

  const logout = useCallback(async (flashMsg?: string) => {
    if (loggingOut.current) return;
    loggingOut.current = true;
    if (flashMsg) { try { sessionStorage.setItem(FLASH_KEY, flashMsg); } catch { /* noop */ } setFlash(flashMsg); }
    const t = session.token;
    if (t && !flashMsg) { try { await disableWebPush(); } catch { /* noop */ } }
    socket.stop();
    session.clear();
    setToken(null);
    setAuthUser(null);
    setMe(null);
    setListeners([]);
    setThreadsState([]);
    setTitleBadge(0);
    if (t && !flashMsg) { try { await api.logout(); } catch { /* already gone */ } }
  }, []);

  useEffect(() => onSessionInvalid(() => { void logout("Your session has ended. Please log in again."); }), [logout]);

  useEffect(() => {
    if (!token) return;
    socket.start();
    void refreshMe();
    void refreshListeners();
    void refreshThreads();
    void enableWebPush();
    const onSw = (ev: MessageEvent) => {
      const d = ev.data;
      if (d && d.type === "open-chat" && d.listener_id) openChatRef.current?.(Number(d.listener_id));
    };
    navigator.serviceWorker?.addEventListener("message", onSw);
    return () => { socket.stop(); navigator.serviceWorker?.removeEventListener("message", onSw); };
  }, [token, refreshMe, refreshListeners, refreshThreads]);

  useEffect(() => {
    if (!token) return;
    const off = socket.on((e: WsEvent) => {
      switch (e.type) {
        case "socket_connected":
          setSocketUp(true);
          void refreshListeners();
          void refreshThreads();
          void refreshMe();
          break;
        case "socket_disconnected":
          setSocketUp(false);
          break;
        case "force_logout":
          void logout("You were signed out because your account was used on another device.");
          break;
        case "coins_updated":
          if (typeof e.coins === "number") setMe((m) => (m ? { ...m, coins: e.coins } : m));
          break;
        case "video_call_setting_changed":
          setMe((m) => (m ? { ...m, video_call_disabled_by_admin: !!e.video_call_disabled_by_admin } : m));
          break;
        case "listener_online":
        case "listener_offline": {
          const on = e.type === "listener_online";
          setListeners((ls) => sortListeners(ls.map((l) => (l.id === e.listener_id ? { ...l, is_online: on, presence_online: on } : l))));
          setThreadsState((ts) => ts.map((t) => (t.listener_id === e.listener_id ? { ...t, is_online: on, presence_online: on } : t)));
          break;
        }
        case "listener_presence":
          setListeners((ls) => sortListeners(ls.map((l) => (l.id === e.listener_id ? { ...l, presence_online: !!e.presence_online } : l))));
          break;
        case "listener_call_status":
          setListeners((ls) => ls.map((l) => (l.id === e.listener_id ? { ...l, is_in_call: !!e.is_in_call } : l)));
          break;
        case "listener_rating_updated":
          setListeners((ls) => ls.map((l) => (l.id === e.listener_id ? { ...l, avg_rating: e.avg_rating, rating_count: e.rating_count } : l)));
          break;
        case "listener_video_call_changed":
          setListeners((ls) => ls.map((l) => (l.id === e.listener_id ? { ...l, video_call_enabled: e.video_call_enabled !== false } : l)));
          break;
        case "chat_message": {
          const incoming = e.sender_type === "listener";
          const viewing = activeChat.current === e.listener_id && document.visibilityState === "visible";
          setThreadsState((ts) => {
            const idx = ts.findIndex((t) => t.listener_id === e.listener_id);
            if (idx === -1) { void refreshThreads(); return ts; }
            const preview = e.message_type === "audio" ? "🎤 Voice message" : e.message_type === "gift" ? `🎁 ${e.gift_name ?? "Gift"}` : e.is_deleted ? "" : e.message;
            const t = ts[idx];
            const updated: Thread = {
              ...t,
              last_message: preview,
              last_message_at: e.created_at,
              last_message_type: e.message_type || "text",
              last_call_type: e.call_type ?? null,
              last_call_status: e.call_status ?? null,
              last_call_duration_seconds: e.call_duration_seconds ?? null,
              unread_count: incoming && !viewing ? t.unread_count + 1 : t.unread_count,
            };
            const rest = ts.filter((_, i) => i !== idx);
            return [...rest, updated].sort((a, b) => Number(b.is_pinned) - Number(a.is_pinned) || +new Date(b.last_message_at) - +new Date(a.last_message_at));
          });
          if (incoming && e.id) void api.markDelivered([e.id]).catch(() => undefined);
          if (incoming && !viewing && e.message_type !== "call") {
            const lname = (listenersRef.current.find((l) => l.id === e.listener_id)?.name) || "New message";
            const body = e.message_type === "audio" ? "🎤 Voice message" : e.message_type === "gift" ? "🎁 Sent you a gift" : e.message;
            if (document.visibilityState !== "visible" || activeChat.current !== e.listener_id) {
              showChatNotification({ title: lname, body, tag: `chat-${e.listener_id}`, onClick: () => openChatRef.current?.(e.listener_id) });
            }
          }
          break;
        }
      }
    });
    return off;
  }, [token, logout, refreshListeners, refreshThreads, refreshMe]);

  const listenersRef = useRef<Listener[]>([]);
  listenersRef.current = listeners;

  const unreadTotal = useMemo(
    () => threads.filter((t) => !t.is_muted).reduce((n, t) => n + (t.unread_count || 0), 0),
    [threads],
  );
  useEffect(() => { setTitleBadge(token ? unreadTotal : 0); }, [unreadTotal, token]);

  const setActiveChat = useCallback((id: number | null) => {
    activeChat.current = id;
    if (id !== null) setThreadsState((ts) => ts.map((t) => (t.listener_id === id ? { ...t, unread_count: 0 } : t)));
  }, []);

  const value: AppCtx = {
    token, authUser, me, listeners, threads, loadingListeners, listenersError, socketUp, unreadTotal, flash,
    login, logout, refreshMe, refreshListeners, refreshThreads, setThreads, setActiveChat, toast,
    clearFlash: () => setFlash(null), openChatRef,
  };

  return (
    <Ctx.Provider value={value}>
      {children}
      <div className="pointer-events-none fixed inset-x-0 top-3 z-[100] flex flex-col items-center gap-2 px-3">
        {toasts.map((t) => (
          <div
            key={t.id}
            className={`pointer-events-auto max-w-md rounded-full border px-4 py-2 text-sm shadow-lg backdrop-blur ${
              t.kind === "error" ? "border-red-500/40 bg-red-50 text-red-700" : t.kind === "success" ? "border-emerald-500/40 bg-emerald-50 text-emerald-700" : "border-black/10 bg-neutral-800 text-white"
            }`}
          >
            {t.text}
          </div>
        ))}
      </div>
    </Ctx.Provider>
  );
}
