import { useNavigate } from "react-router-dom";
import type { Listener } from "../lib/types";
import { useApp } from "../state/app";
import { useCall } from "../state/call";
import { Avatar, BadgePill, PresenceDot } from "./ui";
import { IconPhone, IconVideo } from "./icons";
import { cx, isLive } from "../lib/util";

export function useCallRules(l: Pick<Listener, "is_online" | "is_in_call" | "video_call_enabled"> & { presence_online?: boolean }) {
  const { me } = useApp();
  const { call } = useCall();
  const voice = l.is_online && !l.is_in_call && !call;
  const videoAllowed = !!me && me.video_call_enabled && !me.video_call_disabled_by_admin && l.video_call_enabled;
  return { voice, video: voice && videoAllowed, videoAllowed };
}

export function ListenerCard({ l }: { l: Listener }) {
  const nav = useNavigate();
  const { startCall } = useCall();
  const rules = useCallRules(l);
  const live = isLive(l);
  const status = l.is_in_call ? "On a call" : live ? "Online now" : "Offline";
  const meta = [l.age ? `Age: ${l.age}` : null, l.occupation].filter(Boolean).join(" · ");
  const circle = "flex h-11 w-11 shrink-0 items-center justify-center rounded-full transition";

  return (
    <div
      onClick={() => nav(`/listener/${l.id}`)}
      className="card flex cursor-pointer items-center gap-4 p-3.5 transition hover:border-brand-soft/40 hover:bg-[#1e1e1e]"
    >
      <div className="relative shrink-0 pt-3">
        <Avatar src={l.photo_url} name={l.name} size={88} />
        {l.badge_tag && <div className="absolute left-1/2 top-0 z-10 -translate-x-1/2"><BadgePill tag={l.badge_tag} /></div>}
        <PresenceDot online={live} busy={l.is_in_call} className="absolute bottom-1 right-1 !h-3.5 !w-3.5" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-start gap-2">
          <div className="min-w-0 flex-1">
            <div className="truncate text-lg font-bold leading-tight">{l.name}</div>
            {meta && <div className="mt-0.5 truncate text-sm text-white/70">{meta}</div>}
            <div className={cx("mt-1 text-sm font-semibold", l.is_in_call ? "text-gold" : live ? "text-online" : "text-white/80")}>{status}</div>
          </div>
          <div className="flex shrink-0 gap-2" onClick={(e) => e.stopPropagation()}>
            {l.video_call_enabled && (
              <button
                disabled={!rules.video}
                onClick={() => void startCall(l, true)}
                className={cx(circle, rules.video ? "bg-brand-soft text-white hover:bg-brand" : "bg-white/5 text-white/30")}
                aria-label="Video call"
                title={!rules.videoAllowed ? "Video calls are turned off" : undefined}
              >
                <IconVideo size={18} />
              </button>
            )}
            <button
              disabled={!rules.voice}
              onClick={() => void startCall(l, false)}
              className={cx(circle, rules.voice ? "bg-brand-soft text-white hover:bg-brand" : "bg-white/5 text-white/30")}
              aria-label="Voice call"
            >
              <IconPhone size={18} />
            </button>
          </div>
        </div>
        {l.tags.length > 0 && (
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            {l.tags.slice(0, 3).map((t) => (
              <span key={t} className="rounded-full px-3 py-1 text-xs text-white/80" style={{ background: "rgba(225,29,72,0.18)" }}>{t}</span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
