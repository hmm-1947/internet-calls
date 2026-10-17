import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import {
  ConnectionQuality, createLocalTracks, DisconnectReason, Room, RoomEvent, Track,
  type LocalTrack, type RemoteTrack,
} from "livekit-client";
import { api, ApiError, friendly, InsufficientCoinsError } from "../lib/api";
import { resolveLivekitUrl, RING_TIMEOUT_SECONDS } from "../lib/config";
import { socket, type WsEvent } from "../lib/ws";
import { useApp } from "./app";
import type { BadgeTag, Listener } from "../lib/types";

export type CallPhase = "starting" | "ringing" | "connecting" | "connected" | "noAnswer";

export interface CallParty { id: number; name: string; photo_url: string | null; badge_tag: BadgeTag | null }

export interface CallState {
  callId: number | null;
  party: CallParty;
  video: boolean;
  phase: CallPhase;
  micOn: boolean;
  camOn: boolean;
  reconnecting: boolean;
  remoteJoined: boolean;
  remoteVideo: Track | null;
  remoteVideoMuted: boolean;
  localVideo: Track | null;
  quality: string;
  seconds: number;
  remoteLevel: number;
  message: string | null;
}

interface CallApi {
  call: CallState | null;
  startCall: (l: Listener | (CallParty & Partial<Listener>), video: boolean) => Promise<void>;
  hangUp: () => Promise<void>;
  toggleMic: () => Promise<void>;
  toggleCam: () => Promise<void>;
  redial: () => Promise<void>;
  dismiss: () => void;
  minimized: boolean;
  setMinimized: (v: boolean) => void;
}

const Ctx = createContext<CallApi | null>(null);
export const useCall = () => {
  const c = useContext(Ctx);
  if (!c) throw new Error("useCall outside provider");
  return c;
};

interface Internal {
  callId: number | null;
  phase: CallPhase | "idle";
  acceptHandled: boolean;
  ending: boolean;
  room: Room | null;
  localTracks: LocalTrack[];
  tone: HTMLAudioElement | null;
  audioEls: HTMLMediaElement[];
  timers: Record<string, number | undefined>;
  durationStart: number | null;
  video: boolean;
  party: CallParty | null;
  micOn: boolean;
}

const fresh = (): Internal => ({
  callId: null, phase: "idle", acceptHandled: false, ending: false, room: null, localTracks: [], tone: null,
  audioEls: [], timers: {}, durationStart: null, video: false, party: null, micOn: true,
});

export function CallProvider({ children }: { children: ReactNode }) {
  const { toast, refreshMe, refreshThreads, refreshListeners } = useApp();
  const nav = useNavigate();
  const [call, setCall] = useState<CallState | null>(null);
  const [minimized, setMinimized] = useState(false);
  const I = useRef<Internal>(fresh());

  const patch = useCallback((p: Partial<CallState>) => setCall((c) => (c ? { ...c, ...p } : c)), []);

  const clearTimers = () => {
    Object.values(I.current.timers).forEach((t) => { if (t) { window.clearTimeout(t); window.clearInterval(t); } });
    I.current.timers = {};
  };

  const stopTone = () => {
    const t = I.current.tone;
    if (t) { t.pause(); t.currentTime = 0; }
    I.current.tone = null;
  };

  const startTone = () => {
    try {
      const a = new Audio(`${import.meta.env.BASE_URL}ringing_tone.mp3`);
      a.loop = true;
      a.volume = 0.5;
      I.current.tone = a;
      void a.play().catch(() => undefined);
    } catch { /* noop */ }
  };

  const releaseMedia = () => {
    const s = I.current;
    s.localTracks.forEach((t) => { try { t.stop(); } catch { /* noop */ } });
    s.localTracks = [];
    const room = s.room;
    s.room = null;
    if (room) { room.removeAllListeners(); void room.disconnect().catch(() => undefined); }
    s.audioEls.forEach((e) => { try { e.pause(); e.remove(); } catch { /* noop */ } });
    s.audioEls = [];
  };

  const releaseAll = () => {
    clearTimers();
    stopTone();
    releaseMedia();
  };

  const closeOverlay = () => {
    I.current = fresh();
    setMinimized(false);
    setCall(null);
  };

  const afterCall = (connected: boolean, id: number | null) => {
    closeOverlay();
    void refreshMe();
    void refreshThreads();
    void refreshListeners();
    if (connected && id) nav(`/call-summary/${id}`);
  };

  const finishConnectedOrNot = (id: number | null, wasConnected: boolean, message?: string) => {
    releaseAll();
    if (message) toast(message, "info");
    afterCall(wasConnected, id);
  };

  const onRejected = () => {
    const s = I.current;
    if (s.ending) return;
    s.ending = true;
    releaseAll();
    s.phase = "noAnswer";
    patch({ phase: "noAnswer", localVideo: null, remoteVideo: null, remoteJoined: false, message: "No answer" });
    try { const a = new Audio(`${import.meta.env.BASE_URL}no_response.mp3`); void a.play().catch(() => undefined); } catch { /* noop */ }
    s.timers.noAnswer = window.setTimeout(() => closeOverlay(), 10000);
  };

  const onMissed = async () => {
    const s = I.current;
    if (s.ending) return;
    s.ending = true;
    const id = s.callId;
    releaseAll();
    if (id) { try { await api.timeoutCall(id); } catch { /* noop */ } }
    try { const a = new Audio(`${import.meta.env.BASE_URL}no_response.mp3`); void a.play().catch(() => undefined); } catch { /* noop */ }
    toast("No answer", "info");
    afterCall(false, id);
  };

  const onEnded = () => {
    const s = I.current;
    if (s.ending) return;
    s.ending = true;
    const connected = s.phase === "connected";
    finishConnectedOrNot(s.callId, connected);
  };

  const hangUp = useCallback(async () => {
    const s = I.current;
    if (s.phase === "noAnswer") { closeOverlay(); return; }
    if (s.ending) return;
    s.ending = true;
    const id = s.callId;
    const wasConnected = s.phase === "connected";
    const early = s.phase === "starting" || s.phase === "ringing" || s.phase === "connecting";
    releaseAll();
    if (id) {
      try { if (early) await api.cancelCall(id); else await api.endCall(id); } catch { /* noop */ }
    }
    afterCall(wasConnected, id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const forceEndForCoins = async () => {
    const s = I.current;
    if (s.ending) return;
    s.ending = true;
    const id = s.callId;
    if (id) { try { await api.coinExceeded(id); } catch { /* noop */ } }
    releaseAll();
    toast("Not enough coins to continue the call", "error");
    afterCall(true, id);
  };

  const startDuration = (seed: number) => {
    const s = I.current;
    if (s.durationStart !== null) return;
    s.durationStart = Date.now() - seed * 1000;
    patch({ seconds: seed });
    s.timers.duration = window.setInterval(() => {
      if (I.current.durationStart !== null) patch({ seconds: Math.floor((Date.now() - I.current.durationStart) / 1000) });
    }, 500);
  };

  const bindRoom = (room: Room) => {
    const s = I.current;
    const attachAudio = (track: RemoteTrack) => {
      const el = track.attach() as HTMLMediaElement;
      el.style.display = "none";
      document.body.appendChild(el);
      s.audioEls.push(el);
    };
    room
      .on(RoomEvent.TrackSubscribed, (track) => {
        if (track.kind === Track.Kind.Audio) attachAudio(track);
        else if (track.kind === Track.Kind.Video) patch({ remoteVideo: track, remoteVideoMuted: false });
      })
      .on(RoomEvent.TrackUnsubscribed, (track) => {
        if (track.kind === Track.Kind.Video) patch({ remoteVideo: null });
        else track.detach().forEach((e) => { e.remove(); });
      })
      .on(RoomEvent.TrackMuted, (pub, p) => {
        if (pub.kind === Track.Kind.Video && p !== room.localParticipant) patch({ remoteVideoMuted: true });
      })
      .on(RoomEvent.TrackUnmuted, (pub, p) => {
        if (pub.kind === Track.Kind.Video && p !== room.localParticipant) patch({ remoteVideoMuted: false });
      })
      .on(RoomEvent.ParticipantConnected, () => {
        window.clearTimeout(s.timers.remoteLeft);
        window.clearTimeout(s.timers.remoteJoin);
        patch({ remoteJoined: true });
        s.timers.durationFallback = window.setTimeout(() => {
          if (!s.ending && s.room && s.room.remoteParticipants.size > 0) startDuration(0);
        }, 3000);
      })
      .on(RoomEvent.ParticipantDisconnected, () => {
        window.clearTimeout(s.timers.remoteLeft);
        s.timers.remoteLeft = window.setTimeout(() => {
          if (s.ending || !s.room) return;
          if (s.room.remoteParticipants.size > 0) return;
          void hangUp();
        }, 25000);
      })
      .on(RoomEvent.ConnectionQualityChanged, (q, p) => {
        if (p === room.localParticipant) {
          patch({ quality: q === ConnectionQuality.Excellent ? "Excellent connection" : q === ConnectionQuality.Good ? "Good connection" : q === ConnectionQuality.Poor ? "Poor connection" : "" });
        }
      })
      .on(RoomEvent.Reconnecting, () => patch({ reconnecting: true }))
      .on(RoomEvent.Reconnected, () => patch({ reconnecting: false }))
      .on(RoomEvent.Disconnected, (reason) => {
        if (s.ending) return;
        if (reason === DisconnectReason.JOIN_FAILURE || reason === DisconnectReason.SERVER_SHUTDOWN || reason === undefined) {
          toast("Call ended due to a network issue", "error");
        }
        void hangUp();
      });
  };

  const onAccepted = async (url: string, token: string) => {
    const s = I.current;
    if (s.acceptHandled || s.ending) return;
    s.acceptHandled = true;
    window.clearInterval(s.timers.poll);
    window.clearTimeout(s.timers.ring);
    stopTone();
    s.phase = "connecting";
    patch({ phase: "connecting" });
    const callId = s.callId!;
    try {
      const room = new Room({ adaptiveStream: true, dynacast: true });
      s.room = room;
      bindRoom(room);
      await room.connect(resolveLivekitUrl(url), token, { autoSubscribe: true, maxRetries: 1 });
      if (s.ending) { void room.disconnect(); return; }
      for (const t of s.localTracks) {
        if (t.kind === Track.Kind.Audio && !s.micOn) await t.mute();
        await room.localParticipant.publishTrack(t);
      }
      const camPub = room.localParticipant.getTrackPublication(Track.Source.Camera);
      s.phase = "connected";
      patch({
        phase: "connected",
        camOn: !!camPub && !camPub.isMuted,
        localVideo: camPub?.videoTrack ?? null,
        remoteJoined: room.remoteParticipants.size > 0,
      });
      room.remoteParticipants.forEach((p) => {
        p.trackPublications.forEach((pub) => {
          if (pub.kind === Track.Kind.Video && pub.track) patch({ remoteVideo: pub.track, remoteVideoMuted: pub.isMuted });
        });
      });
      void api.startRecording(callId).catch(() => undefined);
      void api.coinStatus(callId).then((c) => {
        if (I.current.callId !== callId || I.current.ending) return;
        if (!c.max_seconds || c.max_seconds <= 0) { void forceEndForCoins(); return; }
        s.timers.coin = window.setTimeout(() => { void forceEndForCoins(); }, c.max_seconds * 1000);
      }).catch(() => undefined);
      s.timers.statusPoll = window.setInterval(async () => {
        if (I.current.ending) return;
        try {
          const st = await api.callStatus(callId);
          if (st.status === "ended" || st.status === "cancelled" || st.status === "missed") onEnded();
          else if (st.elapsed_seconds !== undefined && I.current.durationStart === null && st.elapsed_seconds >= 0) startDuration(st.elapsed_seconds);
        } catch { /* transient */ }
      }, 3000);
      s.timers.remoteJoin = window.setTimeout(() => {
        if (I.current.ending || !I.current.room) return;
        if (I.current.room.remoteParticipants.size > 0) return;
        toast("Could not connect to the listener.", "error");
        void hangUp();
      }, 25000);
      s.timers.level = window.setInterval(() => {
        const r = I.current.room;
        if (!r) return;
        let lvl = 0;
        r.remoteParticipants.forEach((p) => { lvl = Math.max(lvl, p.audioLevel); });
        setCall((c) => (c && Math.abs(c.remoteLevel - lvl) > 0.02 ? { ...c, remoteLevel: lvl } : c));
      }, 150);
    } catch (e) {
      if (I.current.ending) return;
      toast(friendly(e, "Could not connect the call. Please try again."), "error");
      void hangUp();
    }
  };

  const confirmMissed = async () => {
    const s = I.current;
    if (s.ending || s.acceptHandled || !s.callId) return;
    try {
      const st = await api.callStatus(s.callId);
      if (s.ending || s.acceptHandled) return;
      if (st.status === "accepted" && st.token && st.livekit_url) { void onAccepted(st.livekit_url, st.token); return; }
      if (st.status === "rejected") { onRejected(); return; }
    } catch { /* fall through */ }
    if (I.current.phase === "ringing") void onMissed();
  };

  const startCall: CallApi["startCall"] = useCallback(async (l, video) => {
    if (I.current.phase !== "idle") { toast("You are already on a call", "info"); return; }
    const party: CallParty = { id: l.id, name: l.name, photo_url: l.photo_url ?? null, badge_tag: (l as Listener).badge_tag ?? null };
    I.current = { ...fresh(), phase: "starting", video, party };
    setMinimized(false);
    setCall({
      callId: null, party, video, phase: "starting", micOn: true, camOn: video, reconnecting: false, remoteJoined: false,
      remoteVideo: null, remoteVideoMuted: false, localVideo: null, quality: "", seconds: 0, remoteLevel: 0, message: null,
    });
    const s = I.current;
    try {
      if (!navigator.mediaDevices?.getUserMedia) throw new Error("Calls need a secure (https) connection and a browser with microphone access.");
      const tracks = await createLocalTracks({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: video ? { facingMode: "user" } : false });
      s.localTracks = tracks;
      const cam = tracks.find((t) => t.kind === Track.Kind.Video) ?? null;
      patch({ localVideo: cam });
    } catch (e) {
      const name = (e as { name?: string })?.name;
      toast(
        name === "NotAllowedError" || name === "PermissionDeniedError"
          ? video ? "Allow microphone and camera access to start a video call" : "Allow microphone access to start a call"
          : friendly(e, "Could not access your microphone or camera"),
        "error",
      );
      closeOverlay();
      return;
    }
    try {
      const res = await api.initiateCall(l.id, video ? "video" : "audio");
      if (s.ending) { void api.cancelCall(res.call_id).catch(() => undefined); return; }
      s.callId = res.call_id;
      s.phase = "ringing";
      patch({ callId: res.call_id, phase: "ringing" });
      startTone();
      s.timers.ring = window.setTimeout(() => { void confirmMissed(); }, RING_TIMEOUT_SECONDS * 1000);
      s.timers.poll = window.setInterval(async () => {
        const cur = I.current;
        if (cur.ending || cur.acceptHandled || cur.phase !== "ringing" || !cur.callId) return;
        try {
          const st = await api.callStatus(cur.callId);
          if (cur.ending || cur.acceptHandled) return;
          if (st.status === "accepted" && st.token && st.livekit_url) void onAccepted(st.livekit_url, st.token);
          else if (st.status === "rejected") onRejected();
          else if (st.status === "missed") void onMissed();
          else if (st.status === "ended") onEnded();
        } catch { /* keep polling */ }
      }, 1000);
    } catch (e) {
      releaseAll();
      closeOverlay();
      if (e instanceof InsufficientCoinsError) {
        toast("You need more coins to start this call", "error");
        nav("/upgrade");
      } else if (e instanceof ApiError && e.status === 409) {
        toast("This listener is busy right now", "error");
      } else {
        toast(friendly(e, "Could not start the call"), "error");
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const redial = useCallback(async () => {
    const s = I.current;
    if (s.phase !== "noAnswer" || !s.party) return;
    const party = s.party;
    const video = s.video;
    window.clearTimeout(s.timers.noAnswer);
    I.current = fresh();
    setCall(null);
    await startCall({ ...party, video_call_enabled: true } as CallParty & Partial<Listener>, video);
  }, [startCall]);

  useEffect(() => {
    return socket.on((e: WsEvent) => {
      const s = I.current;
      if (!s.callId || e.call_id !== s.callId) return;
      if (e.type === "call_accepted" && e.livekit_url && e.token) void onAccepted(e.livekit_url, e.token);
      else if (e.type === "call_connected") startDuration(typeof e.elapsed_seconds === "number" ? e.elapsed_seconds : 0);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const toggleMic = useCallback(async () => {
    const s = I.current;
    const next = !s.micOn;
    s.micOn = next;
    patch({ micOn: next });
    if (s.room) { try { await s.room.localParticipant.setMicrophoneEnabled(next); } catch { /* noop */ } }
    else s.localTracks.filter((t) => t.kind === Track.Kind.Audio).forEach((t) => { void (next ? t.unmute() : t.mute()); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const toggleCam = useCallback(async () => {
    const s = I.current;
    const room = s.room;
    if (!room) return;
    const on = !!room.localParticipant.getTrackPublication(Track.Source.Camera) && !room.localParticipant.getTrackPublication(Track.Source.Camera)!.isMuted;
    try {
      await room.localParticipant.setCameraEnabled(!on);
      const pub = room.localParticipant.getTrackPublication(Track.Source.Camera);
      patch({ camOn: !on, localVideo: !on ? pub?.videoTrack ?? null : null });
    } catch {
      toast("Could not access the camera", "error");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const onUnload = () => {
      const s = I.current;
      if (s.phase === "idle" || !s.callId) return;
      const path = s.phase === "connected" ? "end" : "cancel";
      void api.endOrCancelKeepalive(s.callId, path);
    };
    const warn = (e: BeforeUnloadEvent) => {
      if (I.current.phase !== "idle") { e.preventDefault(); e.returnValue = ""; }
    };
    window.addEventListener("pagehide", onUnload);
    window.addEventListener("beforeunload", warn);
    return () => {
      window.removeEventListener("pagehide", onUnload);
      window.removeEventListener("beforeunload", warn);
      const s = I.current;
      if (s.phase !== "idle" && s.callId) { void (s.phase === "connected" ? api.endCall(s.callId) : api.cancelCall(s.callId)).catch(() => undefined); }
      releaseAll();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const dismiss = useCallback(() => { window.clearTimeout(I.current.timers.noAnswer); closeOverlay(); }, []);

  const value: CallApi = { call, startCall, hangUp, toggleMic, toggleCam, redial, dismiss, minimized, setMinimized };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
