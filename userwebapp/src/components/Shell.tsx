import { NavLink, Outlet, useNavigate, useLocation } from "react-router-dom";
import { useApp } from "../state/app";
import { useCall } from "../state/call";
import { CallOverlay } from "./CallOverlay";
import { Avatar, CoinChip } from "./ui";
import { IconChat, IconHome, IconPhone, IconSettings } from "./icons";
import { cx } from "../lib/util";

const items = [
  { to: "/", label: "Home", icon: IconHome, end: true },
  { to: "/chats", label: "Chats", icon: IconChat, end: false },
  { to: "/calls", label: "Calls", icon: IconPhone, end: false },
  { to: "/settings", label: "Settings", icon: IconSettings, end: false },
];

export function Shell() {
  const { me, unreadTotal, socketUp } = useApp();
  const { call } = useCall();
  const nav = useNavigate();
  const loc = useLocation();
  const inThread = /^\/chats\/\d+/.test(loc.pathname);

  const tab = (it: (typeof items)[number]) => (
    <NavLink
      key={it.to}
      to={it.to}
      end={it.end}
      className={({ isActive }) =>
        cx("relative flex flex-col items-center gap-1 py-2.5 text-[11px] font-semibold", isActive ? "text-brand-soft" : "text-ink/50")
      }
    >
      <it.icon size={22} />
      {it.label}
      {it.to === "/chats" && unreadTotal > 0 && (
        <span className="absolute right-[28%] top-1.5 rounded-full bg-brand-soft px-1.5 text-[10px] font-bold text-white">{unreadTotal > 99 ? "99+" : unreadTotal}</span>
      )}
    </NavLink>
  );

  return (
    <div className="flex h-full bg-bg">
      <aside className="hidden w-64 shrink-0 flex-col border-r border-line bg-bg p-4 md:flex">
        <div className="mb-8 flex items-center gap-3 px-2 pt-2">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" className="h-10 w-10 rounded-xl object-cover" />
          <span className="text-xl font-extrabold tracking-tight">MindiCo</span>
        </div>
        <nav className="flex flex-1 flex-col gap-1">
          {items.map((it) => (
            <NavLink
              key={it.to}
              to={it.to}
              end={it.end}
              className={({ isActive }) =>
                cx(
                  "flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold transition",
                  isActive ? "bg-brand/15 text-brand-soft" : "text-ink/60 hover:bg-black/5 hover:text-ink",
                )
              }
            >
              <it.icon size={20} />
              <span className="flex-1">{it.label}</span>
              {it.to === "/chats" && unreadTotal > 0 && (
                <span className="rounded-full bg-brand-soft px-2 py-0.5 text-[11px] font-bold text-white">{unreadTotal > 99 ? "99+" : unreadTotal}</span>
              )}
            </NavLink>
          ))}
        </nav>
        <div className="space-y-3 border-t border-line pt-4">
          <button onClick={() => nav("/upgrade")} className="btn btn-gold w-full">Buy coins</button>
          <div className="flex items-center gap-3 rounded-xl bg-black/5 p-2.5">
            <Avatar src={me?.photo_url} name={me?.name} size={36} />
            <div className="min-w-0 flex-1">
              <div className="truncate text-sm font-semibold">{me?.name ?? "…"}</div>
              <div className="flex items-center gap-1.5 text-[11px] text-muted">
                <span className={cx("inline-block h-1.5 w-1.5 rounded-full", socketUp ? "bg-online" : "bg-gold")} />
                {socketUp ? "Connected" : "Reconnecting…"}
              </div>
            </div>
            <CoinChip coins={me?.coins} onClick={() => nav("/upgrade")} className="!px-2.5 !py-1 text-xs" />
          </div>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        {!inThread && (
          <header className="flex items-center justify-between border-b border-line bg-bg/90 px-4 py-3 backdrop-blur safe-t md:hidden">
            <div className="flex items-center gap-2">
              <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" className="h-8 w-8 rounded-lg object-cover" />
              <span className="text-lg font-extrabold">MindiCo</span>
            </div>
            <div className="flex items-center gap-2">
              {!socketUp && <span className="text-[11px] text-gold">Reconnecting…</span>}
              <CoinChip coins={me?.coins} onClick={() => nav("/upgrade")} />
            </div>
          </header>
        )}
        <main className="min-h-0 flex-1 overflow-y-auto">
          <Outlet />
        </main>
        {!inThread && (
          <nav className="relative z-20 grid grid-cols-5 border-t border-line bg-bg safe-b md:hidden">
            {items.slice(0, 2).map(tab)}
            <div />
            {items.slice(2).map(tab)}
            <button
              onClick={() => nav("/upgrade")}
              aria-label="Buy coins"
              className="absolute left-1/2 top-0 h-[72px] w-[72px] -translate-x-1/2 -translate-y-[55%] overflow-hidden rounded-full active:scale-95"
              style={{ boxShadow: "0 0 16px 2px rgba(18,160,68,0.5)" }}
            >
              <img src={`${import.meta.env.BASE_URL}rupee-256.png`} alt="" className="h-full w-full object-cover" />
            </button>
          </nav>
        )}
      </div>
      {call && <CallOverlay />}
    </div>
  );
}
