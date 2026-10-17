import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { cx, isLive, humanDuration, listTimeLabel, parseDate, timeLabel } from "../lib/util";
import type { CallHistoryItem } from "../lib/types";
import { useApp } from "../state/app";
import { useCall } from "../state/call";
import { Avatar, BadgePill, Empty, PageLoader, Spinner } from "../components/ui";
import { IconChat, IconCoin, IconPhone, IconVideo } from "../components/icons";

const PAGE = 25;
type Filter = "all" | "audio" | "video" | "missed";
const FILTERS: { id: Filter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "audio", label: "Voice" },
  { id: "video", label: "Video" },
  { id: "missed", label: "Missed" },
];

const MISSED = ["missed", "rejected", "cancelled", "timeout", "no_answer"];

function statusText(c: CallHistoryItem): { text: string; bad: boolean } {
  switch (c.status) {
    case "missed":
    case "timeout":
    case "no_answer":
      return { text: "Not answered", bad: true };
    case "rejected":
      return { text: "Declined", bad: true };
    case "cancelled":
      return { text: "Cancelled", bad: true };
    case "ringing":
    case "initiated":
      return { text: "Ringing", bad: false };
    default:
      return { text: c.duration_seconds ? humanDuration(c.duration_seconds) : "Completed", bad: false };
  }
}

export default function Calls() {
  const { listeners, toast } = useApp();
  const { startCall, call } = useCall();
  const nav = useNavigate();
  const [items, setItems] = useState<CallHistoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [more, setMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>("all");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const rows = await api.callHistory(undefined, PAGE);
      setItems(rows);
      setMore(rows.length >= PAGE);
      setError(null);
    } catch (e) {
      setError(friendly(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const loadMore = async () => {
    const last = items[items.length - 1];
    if (!last || loadingMore) return;
    setLoadingMore(true);
    try {
      const rows = await api.callHistory(last.id, PAGE);
      setItems((cur) => [...cur, ...rows.filter((r) => !cur.some((c) => c.id === r.id))]);
      setMore(rows.length >= PAGE);
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setLoadingMore(false);
    }
  };

  const shown = items.filter((c) => {
    if (filter === "audio") return c.call_type === "audio";
    if (filter === "video") return c.call_type === "video";
    if (filter === "missed") return MISSED.includes(c.status);
    return true;
  });

  const callBack = (c: CallHistoryItem) => {
    const l = listeners.find((x) => x.id === c.listener_id);
    if (!l) { toast("This listener is not available right now", "error"); return; }
    if (!isLive(l) || l.is_in_call) { toast(l.is_in_call ? `${l.name} is on another call` : `${l.name} is offline`, "info"); return; }
    void startCall(l, c.call_type === "video");
  };

  let lastDay = "";

  return (
    <div className="mx-auto w-full max-w-3xl px-4 pb-10 pt-5 md:px-8 md:pt-8">
      <h1 className="text-2xl font-extrabold md:text-3xl">Calls</h1>
      <div className="mb-4 mt-4 flex gap-2 overflow-x-auto">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            onClick={() => setFilter(f.id)}
            className={cx("shrink-0 rounded-full px-4 py-1.5 text-sm font-semibold transition", filter === f.id ? "bg-brand-soft text-white" : "bg-white/5 text-white/60 hover:bg-white/10")}
          >
            {f.label}
          </button>
        ))}
      </div>

      {loading ? (
        <PageLoader />
      ) : error && items.length === 0 ? (
        <Empty title="Could not load calls" text={error} action={<button className="btn btn-primary" onClick={() => void load()}>Try again</button>} />
      ) : shown.length === 0 ? (
        <Empty icon={<IconPhone size={44} />} title={filter === "all" ? "No calls yet" : "No calls found"} text={filter === "all" ? "Your call history will show up here." : "Try a different filter."} />
      ) : (
        <div className="card overflow-hidden">
          {shown.map((c) => {
            const st = statusText(c);
            const day = parseDate(c.created_at)?.toDateString() ?? "";
            const showDay = day !== lastDay;
            lastDay = day;
            const tone = st.bad ? "text-red-400" : "text-online";
            return (
              <div key={c.id}>
                {showDay && <div className="border-b border-line bg-white/[0.03] px-4 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted">{listTimeLabel(c.created_at)}</div>}
                <div className="flex items-center gap-3 border-b border-line px-4 py-3">
                  <button onClick={() => nav(`/listener/${c.listener_id}`)} className="shrink-0">
                    <Avatar src={c.other_party_photo_url} name={c.listener_name} size={48} />
                  </button>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="truncate font-semibold">{c.listener_name}</span>
                      <BadgePill tag={c.badge_tag} />
                    </div>
                    <div className="mt-0.5 flex flex-wrap items-center gap-x-2 text-xs">
                      {c.call_type === "video" ? <IconVideo size={13} className={tone} /> : <IconPhone size={13} className={tone} />}
                      <span className={st.bad ? "text-red-400" : "text-white/70"}>{st.text}</span>
                      <span className="text-muted">{timeLabel(c.created_at)}</span>
                      {c.coins_deducted ? <span className="inline-flex items-center gap-1 text-gold"><IconCoin size={12} />{c.coins_deducted}</span> : null}
                    </div>
                  </div>
                  <button onClick={() => nav(`/chats/${c.listener_id}`)} className="rounded-full p-2.5 text-white/60 hover:bg-white/10 hover:text-white" aria-label="Chat"><IconChat size={18} /></button>
                  <button
                    disabled={!!call}
                    onClick={() => callBack(c)}
                    className="rounded-full bg-online/15 p-2.5 text-online hover:bg-online/25 disabled:opacity-40"
                    aria-label="Call again"
                  >
                    {c.call_type === "video" ? <IconVideo size={18} /> : <IconPhone size={18} />}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {more && !loading && (
        <div className="mt-4 flex justify-center">
          <button className="btn btn-ghost" onClick={() => void loadMore()} disabled={loadingMore}>
            {loadingMore ? <Spinner size={14} /> : "Load more"}
          </button>
        </div>
      )}
    </div>
  );
}
