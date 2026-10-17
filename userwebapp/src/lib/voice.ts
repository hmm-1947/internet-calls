export function pickRecorderMime(): { mime: string; ext: string } | null {
  if (typeof MediaRecorder === "undefined") return null;
  const candidates: [string, string][] = [
    ["audio/webm;codecs=opus", "webm"],
    ["audio/webm", "webm"],
    ["audio/mp4", "m4a"],
    ["audio/ogg;codecs=opus", "ogg"],
  ];
  for (const [mime, ext] of candidates) {
    if (MediaRecorder.isTypeSupported(mime)) return { mime, ext };
  }
  return null;
}

export class VoiceRecorder {
  private rec: MediaRecorder | null = null;
  private stream: MediaStream | null = null;
  private chunks: Blob[] = [];
  private startedAt = 0;
  private cancelled = false;
  private finish: ((r: { blob: Blob; ext: string; seconds: number } | null) => void) | null = null;
  private ext = "webm";

  static supported() {
    return !!navigator.mediaDevices?.getUserMedia && pickRecorderMime() !== null;
  }

  async start(): Promise<void> {
    const picked = pickRecorderMime();
    if (!picked) throw new Error("Voice notes are not supported in this browser");
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
    } catch {
      throw new Error("Microphone permission is needed to record a voice note");
    }
    this.ext = picked.ext;
    this.chunks = [];
    this.cancelled = false;
    this.rec = new MediaRecorder(this.stream, { mimeType: picked.mime });
    this.rec.ondataavailable = (e) => { if (e.data.size > 0) this.chunks.push(e.data); };
    this.rec.onstop = () => {
      const seconds = Math.max(1, Math.round((Date.now() - this.startedAt) / 1000));
      this.stream?.getTracks().forEach((t) => t.stop());
      this.stream = null;
      const f = this.finish;
      this.finish = null;
      if (this.cancelled || !this.chunks.length) f?.(null);
      else f?.({ blob: new Blob(this.chunks, { type: picked.mime.split(";")[0] }), ext: this.ext, seconds });
    };
    this.startedAt = Date.now();
    this.rec.start(250);
  }

  elapsed() { return this.startedAt ? (Date.now() - this.startedAt) / 1000 : 0; }

  stop(): Promise<{ blob: Blob; ext: string; seconds: number } | null> {
    return new Promise((resolve) => {
      if (!this.rec || this.rec.state === "inactive") { resolve(null); return; }
      this.finish = resolve;
      this.rec.stop();
    });
  }

  cancel() {
    this.cancelled = true;
    if (this.rec && this.rec.state !== "inactive") this.rec.stop();
    else this.stream?.getTracks().forEach((t) => t.stop());
  }
}
