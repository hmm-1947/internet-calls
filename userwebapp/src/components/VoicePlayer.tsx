import { useEffect, useRef, useState } from "react";
import { mediaUrl } from "../lib/config";
import { formatDuration } from "../lib/util";
import { IconPause, IconPlay } from "./icons";

let current: HTMLAudioElement | null = null;

export function VoicePlayer({ src, duration }: { src: string; duration?: number | null }) {
  const ref = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);
  const [pos, setPos] = useState(0);
  const [total, setTotal] = useState(duration || 0);
  const [error, setError] = useState(false);

  useEffect(() => {
    const a = new Audio();
    a.preload = "metadata";
    a.src = mediaUrl(src);
    ref.current = a;
    a.onloadedmetadata = () => { if (isFinite(a.duration) && a.duration > 0) setTotal(a.duration); };
    a.ontimeupdate = () => setPos(a.currentTime);
    a.onended = () => { setPlaying(false); setPos(0); };
    a.onpause = () => setPlaying(false);
    a.onplay = () => setPlaying(true);
    a.onerror = () => setError(true);
    return () => { a.pause(); a.src = ""; if (current === a) current = null; };
  }, [src]);

  const toggle = () => {
    const a = ref.current;
    if (!a) return;
    if (a.paused) {
      if (current && current !== a) current.pause();
      current = a;
      void a.play().catch(() => setError(true));
    } else a.pause();
  };

  const seek = (e: React.MouseEvent<HTMLDivElement>) => {
    const a = ref.current;
    if (!a || !total) return;
    const r = e.currentTarget.getBoundingClientRect();
    a.currentTime = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * total;
  };

  const pct = total ? Math.min(100, (pos / total) * 100) : 0;

  return (
    <div className="flex w-56 items-center gap-3">
      <button onClick={toggle} className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-black/20 hover:bg-black/30" aria-label={playing ? "Pause" : "Play"}>
        {playing ? <IconPause size={16} /> : <IconPlay size={16} />}
      </button>
      <div className="flex-1">
        <div className="h-1.5 cursor-pointer rounded-full bg-black/20" onClick={seek}>
          <div className="h-full rounded-full bg-white" style={{ width: `${pct}%` }} />
        </div>
        <div className="mt-1 text-[11px] text-ink/70">{error ? "Cannot play on this browser" : formatDuration(playing || pos > 0 ? pos : total)}</div>
      </div>
    </div>
  );
}
