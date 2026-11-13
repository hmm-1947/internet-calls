import { useEffect, useRef, useState } from "react";
import type { Track } from "livekit-client";
import { useCall } from "../state/call";
import { formatDuration, cx } from "../lib/util";
import { Avatar, BadgePill, Spinner } from "./ui";
import { GiftSheet } from "./GiftSheet";
import { IconGift, IconMic, IconMicOff, IconMinimize, IconPhoneEnd, IconVideo, IconVideoOff } from "./icons";

function VideoView({ track, mirror, className }: { track: Track | null; mirror?: boolean; className?: string }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || !track) return;
    track.attach(el);
    return () => { track.detach(el); };
  }, [track]);
  return <video ref={ref} autoPlay playsInline muted className={cx("object-cover", mirror && "-scale-x-100", className)} />;
}

function RoundBtn({ onClick, active = true, danger, label, children, disabled }: { onClick: () => void; active?: boolean; danger?: boolean; label: string; children: React.ReactNode; disabled?: boolean }) {
  return (
    <div className="flex flex-col items-center gap-1.5">
      <button
        onClick={onClick}
        disabled={disabled}
        aria-label={label}
        className={cx(
          "flex h-14 w-14 items-center justify-center rounded-full transition disabled:opacity-40",
          danger ? "bg-red-600 hover:bg-red-500" : active ? "bg-white/15 hover:bg-white/25" : "bg-white text-neutral-900",
        )}
      >
        {children}
      </button>
      <span className="text-[11px] text-white/60">{label}</span>
    </div>
  );
}

export function CallOverlay() {
  const { call, hangUp, toggleMic, toggleCam, redial, dismiss, minimized, setMinimized } = useCall();
  const [giftOpen, setGiftOpen] = useState(false);
  if (!call) return null;

  const connected = call.phase === "connected";
  const status =
    call.phase === "starting" ? "Starting…"
    : call.phase === "ringing" ? "Ringing…"
    : call.phase === "connecting" ? "Connecting…"
    : call.phase === "noAnswer" ? "No answer"
    : call.remoteJoined || call.seconds > 0 ? formatDuration(call.seconds)
    : "Waiting for listener…";

  if (minimized) {
    return (
      <div className="fixed bottom-20 right-3 z-[55] flex items-center gap-3 rounded-2xl border border-white/10 bg-[#212823] p-2.5 pr-3 shadow-2xl md:bottom-6 md:right-6">
        {call.video && call.remoteVideo ? (
          <VideoView track={call.remoteVideo} className="h-16 w-12 rounded-xl" />
        ) : (
          <Avatar src={call.party.photo_url} name={call.party.name} size={44} />
        )}
        <button className="text-left" onClick={() => setMinimized(false)}>
          <div className="max-w-[120px] truncate text-sm font-semibold">{call.party.name}</div>
          <div className="text-xs text-online">{status}</div>
        </button>
        <button onClick={() => void hangUp()} className="flex h-10 w-10 items-center justify-center rounded-full bg-red-600" aria-label="End call">
          <IconPhoneEnd size={18} />
        </button>
      </div>
    );
  }

  const showVideo = call.video && connected;

  return (
    <div className="fixed inset-0 z-[55] flex flex-col overflow-hidden bg-[#0E1210] text-white safe-t safe-b">
      {showVideo && call.remoteVideo && !call.remoteVideoMuted && (
        <VideoView track={call.remoteVideo} className="absolute inset-0 h-full w-full" />
      )}
      <div className={cx("absolute inset-0", showVideo && call.remoteVideo && !call.remoteVideoMuted ? "bg-gradient-to-b from-black/60 via-transparent to-black/70" : "bg-[radial-gradient(ellipse_at_top,rgba(18,160,68,0.25),transparent_65%)]")} />

      <div className="relative z-10 flex items-center justify-between px-5 pt-4">
        <div className="text-xs text-white/60">{call.video ? "Video call" : "Voice call"}{call.quality ? ` · ${call.quality}` : ""}</div>
        <button onClick={() => setMinimized(true)} className="rounded-full bg-white/10 p-2.5 hover:bg-white/20" aria-label="Minimize">
          <IconMinimize size={18} />
        </button>
      </div>

      <div className="relative z-10 flex flex-1 flex-col items-center justify-center px-6 text-center">
        {!(showVideo && call.remoteVideo && !call.remoteVideoMuted) && (
          <div className="relative mb-6">
            {(call.phase === "ringing" || call.phase === "connecting" || call.phase === "starting") && (
              <>
                <span className="pulse-ring absolute inset-0 rounded-full bg-brand-soft/40" />
                <span className="pulse-ring absolute inset-0 rounded-full bg-brand-soft/30 [animation-delay:0.6s]" />
              </>
            )}
            <div style={{ boxShadow: connected ? `0 0 0 ${Math.min(18, call.remoteLevel * 60)}px rgba(34,197,94,0.25)` : undefined }} className="relative rounded-full transition-all duration-100">
              <Avatar src={call.party.photo_url} name={call.party.name} size={140} ring />
            </div>
          </div>
        )}
        <h2 className="text-2xl font-bold drop-shadow">{call.party.name}</h2>
        <div className="mt-2"><BadgePill tag={call.party.badge_tag} /></div>
        <div className={cx("mt-3 flex items-center gap-2 text-base drop-shadow", call.phase === "noAnswer" ? "text-red-300" : "text-white/80")}>
          {(call.phase === "starting" || call.phase === "connecting") && <Spinner size={14} />}
          {call.reconnecting ? "Reconnecting…" : status}
        </div>
        {call.phase === "connected" && call.video && call.remoteVideoMuted && (
          <div className="mt-2 text-xs text-white/50">Listener turned their camera off</div>
        )}
      </div>

      {showVideo && call.localVideo && call.camOn && (
        <div className="absolute right-4 top-16 z-10 h-40 w-28 overflow-hidden rounded-2xl border border-white/20 shadow-xl sm:h-48 sm:w-36">
          <VideoView track={call.localVideo} mirror className="h-full w-full" />
        </div>
      )}

      <div className="relative z-10 flex items-end justify-center gap-5 px-4 pb-8 pt-4">
        {call.phase === "noAnswer" ? (
          <>
            <RoundBtn onClick={dismiss} label="Close" active><IconPhoneEnd size={22} /></RoundBtn>
            <RoundBtn onClick={() => void redial()} label="Call again" active={false}>{call.video ? <IconVideo size={22} /> : <IconMic size={22} />}</RoundBtn>
          </>
        ) : (
          <>
            <RoundBtn onClick={() => void toggleMic()} label={call.micOn ? "Mute" : "Unmute"} active={call.micOn}>
              {call.micOn ? <IconMic size={22} /> : <IconMicOff size={22} />}
            </RoundBtn>
            {call.video && (
              <RoundBtn onClick={() => void toggleCam()} label="Camera" active={call.camOn} disabled={!connected}>
                {call.camOn ? <IconVideo size={22} /> : <IconVideoOff size={22} />}
              </RoundBtn>
            )}
            <RoundBtn onClick={() => setGiftOpen(true)} label="Gift" disabled={!connected}><IconGift size={22} /></RoundBtn>
            <RoundBtn onClick={() => void hangUp()} label="End" danger><IconPhoneEnd size={22} /></RoundBtn>
          </>
        )}
      </div>

      <GiftSheet open={giftOpen} onClose={() => setGiftOpen(false)} listenerId={call.party.id} callId={call.callId} zIndex={70} onTopUp={() => setMinimized(true)} />
    </div>
  );
}
