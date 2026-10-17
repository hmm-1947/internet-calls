import { useNavigate } from "react-router-dom";
import type { Listener } from "../lib/types";
import { useApp } from "../state/app";
import { useCall } from "../state/call";
import { mediaUrl } from "../lib/config";
import { BadgePill, PresenceDot, Stars } from "./ui";
import { IconChat, IconPhone, IconUser, IconVideo } from "./icons";
import { cx, isLive } from "../lib/util";

export function useCallRules(l: Pick<Listener, "is_online" | "is_in_call" | "video_call_enabled"> & { presence_online?: boolean }) {
  const { me } = useApp();
  const { call } = useCall();
  const voice = isLive(l) && !l.is_in_call && !call;
  const videoAllowed = !!me && me.video_call_enabled && !me.video_call_disabled_by_admin && l.video_call_enabled;
  return { voice, video: voice && videoAllowed, videoAllowed };
}

export function ListenerCard({ l }: { l: Listener }) {
  const nav = useNavigate();
  const { startCall } = useCall();
  const rules = useCallRules(l);
  const status = l.is_in_call ? "On a call" : isLive(l) ? "Online" : "Offline";

  return (
    <div
      onClick={() => nav(`/listener/${l.id}`)}
      className="card group flex cursor-pointer flex-col overflow-hidden transition hover:border-brand-soft/40 hover:bg-[#1e1e1e]"
    >
      <div className="relative aspect-[4/3] w-full overflow-hidden bg-card2">
        {l.photo_url ? (
          <img src={mediaUrl(l.photo_url)} alt={l.name} loading="lazy" className="h-full w-full object-cover transition duration-300 group-hover:scale-105" />
        ) : (
          <div className="flex h-full w-full items-center justify-center text-white/20"><IconUser size={56} /></div>
        )}
        <div className="absolute inset-x-0 bottom-0 h-1/2 bg-gradient-to-t from-black/70 to-transparent" />
        <div className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/55 px-2.5 py-1 text-[11px] font-semibold backdrop-blur">
          <PresenceDot online={isLive(l)} busy={l.is_in_call} className="!h-2 !w-2 !border-0" />
          {status}
        </div>
        <div className="absolute bottom-2.5 left-3 right-3 flex items-end justify-between">
          <div className="min-w-0">
            <div className="truncate text-base font-bold drop-shadow">{l.name}{l.age ? `, ${l.age}` : ""}</div>
            {l.occupation && <div className="truncate text-xs text-white/70">{l.occupation}</div>}
          </div>
          <Stars value={l.avg_rating} count={l.rating_count} />
        </div>
      </div>
      <div className="flex flex-1 flex-col gap-3 p-3.5">
        <div className="flex min-h-[22px] flex-wrap items-center gap-1.5">
          <BadgePill tag={l.badge_tag} />
          {l.tags.slice(0, 3).map((t) => (
            <span key={t} className="rounded-full bg-white/8 px-2 py-0.5 text-[11px] text-white/70" style={{ background: "rgba(255,255,255,0.07)" }}>{t}</span>
          ))}
        </div>
        <div className="mt-auto flex gap-2" onClick={(e) => e.stopPropagation()}>
          <button
            disabled={!rules.voice}
            onClick={() => void startCall(l, false)}
            className={cx("btn flex-1 !py-2", rules.voice ? "bg-online/90 text-white hover:bg-online" : "bg-white/5 text-white/40")}
          >
            <IconPhone size={16} /> Call
          </button>
          {l.video_call_enabled && (
            <button
              disabled={!rules.video}
              onClick={() => void startCall(l, true)}
              className={cx("btn flex-1 !py-2", rules.video ? "btn-primary" : "bg-white/5 text-white/40")}
              title={!rules.videoAllowed ? "Video calls are turned off" : undefined}
            >
              <IconVideo size={16} /> Video
            </button>
          )}
          <button onClick={() => nav(`/chats/${l.id}`)} className="btn btn-ghost !px-3 !py-2" aria-label="Chat">
            <IconChat size={16} />
          </button>
        </div>
      </div>
    </div>
  );
}
