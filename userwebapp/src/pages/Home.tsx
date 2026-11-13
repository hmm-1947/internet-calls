import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../lib/api";
import { mediaUrl } from "../lib/config";
import { notificationPermission, requestNotificationPermission } from "../lib/notify";
import { enableWebPush } from "../lib/push";
import { cx, isLive } from "../lib/util";
import { useApp } from "../state/app";
import { ListenerCard } from "../components/ListenerCard";
import { Empty, PageLoader } from "../components/ui";
import { IconClose, IconSearch } from "../components/icons";

export default function Home() {
  const { me, listeners, loadingListeners, listenersError, refreshListeners } = useApp();
  const nav = useNavigate();
  const [q, setQ] = useState("");
  const [onlineOnly, setOnlineOnly] = useState(false);
  const [offers, setOffers] = useState<{ id: number; image_url: string }[]>([]);
  const [perm, setPerm] = useState(notificationPermission());
  const [hideBanner, setHideBanner] = useState(false);

  useEffect(() => {
    api.specialOffers().then(setOffers).catch(() => undefined);
  }, []);

  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    return listeners.filter((l) => {
      if (onlineOnly && !isLive(l)) return false;
      if (!s) return true;
      return l.name.toLowerCase().includes(s) || l.tags.some((t) => t.toLowerCase().includes(s)) || (l.occupation ?? "").toLowerCase().includes(s);
    });
  }, [listeners, q, onlineOnly]);

  const enable = async () => {
    const p = await requestNotificationPermission();
    setPerm(p);
    if (p === "granted") void enableWebPush();
  };

  return (
    <div className="mx-auto w-full max-w-7xl px-4 pb-10 pt-5 md:px-8 md:pt-8">
      <div className="mb-5 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-2xl font-extrabold md:text-3xl">Hi{me?.name ? `, ${me.name.split(" ")[0]}` : ""} 👋</h1>
          <p className="mt-1 text-sm text-muted">Pick a listener and start talking.</p>
        </div>
        <div className="flex gap-2">
          <div className="relative flex-1 md:w-80">
            <IconSearch size={18} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-ink/40" />
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search listeners" className="input !pl-10" />
          </div>
          <button
            onClick={() => setOnlineOnly((v) => !v)}
            className={cx("btn shrink-0", onlineOnly ? "bg-online/20 text-online ring-1 ring-online/50" : "btn-ghost")}
          >
            Online
          </button>
        </div>
      </div>

      {perm === "default" && !hideBanner && (
        <div className="mb-5 flex items-center gap-3 rounded-2xl border border-brand-soft/30 bg-brand/10 px-4 py-3">
          <div className="flex-1 text-sm">Turn on notifications to get new messages while this tab is open.</div>
          <button className="btn btn-primary !py-1.5" onClick={() => void enable()}>Enable</button>
          <button onClick={() => setHideBanner(true)} className="rounded-full p-1 text-ink/50 hover:text-ink" aria-label="Dismiss"><IconClose size={16} /></button>
        </div>
      )}

      {offers.length > 0 && (
        <div className="-mx-4 mb-6 flex snap-x gap-3 overflow-x-auto px-4 md:mx-0 md:px-0">
          {offers.map((o) => (
            <button key={o.id} onClick={() => nav("/upgrade")} className="h-28 w-[85%] shrink-0 snap-start overflow-hidden rounded-2xl sm:h-36 sm:w-[420px]">
              <img src={mediaUrl(o.image_url)} alt="Offer" className="h-full w-full object-cover" />
            </button>
          ))}
        </div>
      )}

      {loadingListeners && listeners.length === 0 ? (
        <PageLoader />
      ) : listenersError && listeners.length === 0 ? (
        <Empty title="Could not load listeners" text={listenersError} action={<button className="btn btn-primary" onClick={() => void refreshListeners()}>Try again</button>} />
      ) : shown.length === 0 ? (
        <Empty title={q || onlineOnly ? "No listeners match" : "No listeners yet"} text={q || onlineOnly ? "Try a different search or filter." : "Please check back in a little while."} />
      ) : (
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
          {shown.map((l) => <ListenerCard key={l.id} l={l} />)}
        </div>
      )}
    </div>
  );
}
