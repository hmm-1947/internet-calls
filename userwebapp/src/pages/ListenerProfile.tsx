import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { mediaUrl } from "../lib/config";
import { isLive, parseDate } from "../lib/util";
import type { Listener } from "../lib/types";
import { useApp } from "../state/app";
import { useCall } from "../state/call";
import { BadgePill, Empty, PageHeader, PageLoader, PresenceDot, Stars } from "../components/ui";
import { useCallRules } from "../components/ListenerCard";
import { IconChat, IconPhone, IconUser, IconVideo } from "../components/icons";

export default function ListenerProfile() {
  const { listenerId } = useParams();
  const nav = useNavigate();
  const { listeners } = useApp();
  const { startCall } = useCall();
  const id = Number(listenerId);
  const live = listeners.find((l) => l.id === id) ?? null;
  const [fetched, setFetched] = useState<Listener | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setError(null);
    api.listener(id).then(setFetched).catch((e) => setError(friendly(e)));
  }, [id]);

  const l: Listener | null = live && fetched ? { ...fetched, ...live, about: fetched.about, languages: fetched.languages, created_at: fetched.created_at } : fetched ?? live;
  const rules = useCallRules(l ?? { is_online: false, is_in_call: false, video_call_enabled: false });

  if (!l) {
    return (
      <>
        <PageHeader title="Profile" onBack={() => nav(-1)} />
        {error ? <Empty title="Listener not found" text={error} /> : <PageLoader />}
      </>
    );
  }

  const since = parseDate(l.created_at);
  const status = l.is_in_call ? "On a call" : isLive(l) ? "Online" : "Offline";

  return (
    <div>
      <PageHeader title="Profile" onBack={() => nav(-1)} />
      <div className="mx-auto w-full max-w-4xl px-4 pb-10 pt-5 md:px-8 md:pt-8">
        <div className="flex flex-col gap-6 md:flex-row">
          <div className="relative aspect-square w-full shrink-0 overflow-hidden rounded-3xl bg-card2 md:w-80">
            {l.photo_url ? (
              <img src={mediaUrl(l.photo_url)} alt={l.name} className="h-full w-full object-cover" />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-white/20"><IconUser size={96} /></div>
            )}
            <div className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/55 px-3 py-1 text-xs font-semibold backdrop-blur">
              <PresenceDot online={isLive(l)} busy={l.is_in_call} className="!h-2 !w-2 !border-0" />
              {status}
            </div>
          </div>

          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="text-2xl font-extrabold md:text-3xl">{l.name}{l.age ? `, ${l.age}` : ""}</h1>
              <BadgePill tag={l.badge_tag} />
            </div>
            {l.occupation && <p className="mt-1 text-white/70">{l.occupation}</p>}
            <div className="mt-3 flex items-center gap-3">
              <Stars value={l.avg_rating} count={l.rating_count} size={18} />
              {since && <span className="text-xs text-muted">Joined {since.toLocaleDateString([], { month: "short", year: "numeric" })}</span>}
            </div>

            <div className="mt-5 flex flex-wrap gap-3">
              <button disabled={!rules.voice} onClick={() => void startCall(l, false)} className="btn flex-1 bg-online/90 text-white hover:bg-online disabled:bg-white/5 disabled:text-white/40 md:flex-none md:px-8">
                <IconPhone size={18} /> Voice call
              </button>
              {l.video_call_enabled && (
                <button disabled={!rules.video} onClick={() => void startCall(l, true)} className="btn btn-primary flex-1 md:flex-none md:px-8" title={!rules.videoAllowed ? "Video calls are turned off" : undefined}>
                  <IconVideo size={18} /> Video call
                </button>
              )}
              <button onClick={() => nav(`/chats/${l.id}`)} className="btn btn-ghost flex-1 md:flex-none md:px-8">
                <IconChat size={18} /> Chat
              </button>
            </div>
            {!isLive(l) && <p className="mt-3 text-xs text-muted">{l.name} is offline right now. You can still leave a message.</p>}
            {l.is_in_call && <p className="mt-3 text-xs text-muted">{l.name} is on another call.</p>}

            {l.about && (
              <section className="mt-7">
                <h2 className="label">About</h2>
                <p className="whitespace-pre-wrap text-sm leading-relaxed text-white/80">{l.about}</p>
              </section>
            )}
            {l.languages && l.languages.length > 0 && (
              <section className="mt-6">
                <h2 className="label">Languages</h2>
                <div className="flex flex-wrap gap-2">
                  {l.languages.map((x) => <span key={x} className="rounded-full px-3 py-1 text-xs text-white/80" style={{ background: "rgba(255,255,255,0.07)" }}>{x}</span>)}
                </div>
              </section>
            )}
            {l.tags.length > 0 && (
              <section className="mt-6">
                <h2 className="label">Topics</h2>
                <div className="flex flex-wrap gap-2">
                  {l.tags.map((x) => <span key={x} className="rounded-full border border-brand-soft/30 bg-brand/10 px-3 py-1 text-xs text-brand-soft">{x}</span>)}
                </div>
              </section>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
