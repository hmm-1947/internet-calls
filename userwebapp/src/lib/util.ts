export const uuid = (): string =>
  typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0;
        return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
      });

export function normalizePhone(phone: string): string {
  let d = phone.replace(/\D/g, "");
  if (d.length === 12 && d.startsWith("91")) d = d.slice(2);
  if (d.length === 11 && d.startsWith("0")) d = d.slice(1);
  return d;
}

export function phoneError(value: string): string | null {
  const v = value.trim();
  if (!v) return "Enter your phone number";
  if (v.includes("@")) return "Use your phone number, or continue with Google";
  const n = normalizePhone(v);
  if (n.length !== 10 || !/^[6-9]/.test(n)) return "Enter a valid 10-digit phone number";
  return null;
}

export const passwordRules: { label: string; test: (p: string) => boolean }[] = [
  { label: "At least 8 characters", test: (p) => p.length >= 8 },
  { label: "At least one alphabet", test: (p) => /[A-Za-z]/.test(p) },
  { label: "At least one number", test: (p) => /[0-9]/.test(p) },
  { label: "At least one special character", test: (p) => /[^A-Za-z0-9]/.test(p) },
];
export const passwordValid = (p: string) => !!p && passwordRules.every((r) => r.test(p));

export function usernameError(u: string): string | null {
  const v = u.trim();
  if (!v) return "Choose a username";
  if (v.length < 3) return "Username must be at least 3 characters long";
  if (v.length > 20) return "Username must be at most 20 characters long";
  if (!/^[A-Za-z0-9._]+$/.test(v)) return "Only letters, numbers, dots and underscores are allowed";
  if (!/[A-Za-z]/.test(v)) return "Username must contain at least one letter";
  if (v.startsWith(".") || v.endsWith(".")) return "Username cannot start or end with a dot";
  return null;
}

export function displayNameError(n: string): string | null {
  const v = n.trim();
  if (v.length < 2) return "Display name must be at least 2 characters long";
  if (v.length > 30) return "Display name must be at most 30 characters long";
  return null;
}

export function formatDuration(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const mm = String(m).padStart(2, "0");
  const ss = String(sec).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

export function humanDuration(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds || 0));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  const r = s % 60;
  return r ? `${m}m ${r}s` : `${m}m`;
}

export function humanWait(seconds: number): string {
  const days = Math.ceil(seconds / 86400);
  if (seconds >= 86400) return `${days} day${days === 1 ? "" : "s"}`;
  const hours = Math.ceil(seconds / 3600);
  if (seconds >= 3600) return `${hours} hour${hours === 1 ? "" : "s"}`;
  return `${Math.max(1, Math.ceil(seconds / 60))} min`;
}

export function parseDate(s: string | null | undefined): Date | null {
  if (!s) return null;
  const hasTz = /(Z|[+-]\d\d:?\d\d)$/.test(s);
  const d = new Date(hasTz ? s : `${s}Z`);
  return isNaN(d.getTime()) ? null : d;
}

export function timeLabel(s: string | null | undefined): string {
  const d = parseDate(s);
  if (!d) return "";
  return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

export function listTimeLabel(s: string | null | undefined): string {
  const d = parseDate(s);
  if (!d) return "";
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  if (sameDay) return timeLabel(s);
  const y = new Date(now);
  y.setDate(now.getDate() - 1);
  if (d.toDateString() === y.toDateString()) return "Yesterday";
  return d.toLocaleDateString([], { day: "numeric", month: "short", year: d.getFullYear() === now.getFullYear() ? undefined : "numeric" });
}

export function dayLabel(s: string | null | undefined): string {
  const d = parseDate(s);
  if (!d) return "";
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return "Today";
  const y = new Date(now);
  y.setDate(now.getDate() - 1);
  if (d.toDateString() === y.toDateString()) return "Yesterday";
  return d.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" });
}

export function sanitizeHtml(html: string): string {
  const doc = new DOMParser().parseFromString(html, "text/html");
  doc.querySelectorAll("script,style,iframe,object,embed,link,meta,form").forEach((n) => n.remove());
  doc.body.querySelectorAll("*").forEach((el) => {
    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase();
      if (name.startsWith("on") || (["href", "src"].includes(name) && /^\s*javascript:/i.test(attr.value))) {
        el.removeAttribute(attr.name);
      }
    }
    if (el.tagName === "A") { el.setAttribute("target", "_blank"); el.setAttribute("rel", "noopener noreferrer"); }
  });
  return doc.body.innerHTML;
}

export async function squareCropJpeg(file: File, size = 640): Promise<Blob> {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((res, rej) => {
      const i = new Image();
      i.onload = () => res(i);
      i.onerror = () => rej(new Error("Could not read this image"));
      i.src = url;
    });
    const side = Math.min(img.width, img.height);
    const sx = (img.width - side) / 2;
    const sy = (img.height - side) / 2;
    const out = Math.min(size, side);
    const canvas = document.createElement("canvas");
    canvas.width = out;
    canvas.height = out;
    canvas.getContext("2d")!.drawImage(img, sx, sy, side, side, 0, 0, out, out);
    return await new Promise<Blob>((res, rej) =>
      canvas.toBlob((b) => (b ? res(b) : rej(new Error("Could not process image"))), "image/jpeg", 0.9),
    );
  } finally {
    URL.revokeObjectURL(url);
  }
}

export const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");
export const isLive = (l: { is_online: boolean; presence_online?: boolean }): boolean => l.presence_online ?? l.is_online;
