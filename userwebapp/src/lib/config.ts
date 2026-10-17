const raw = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? "";

export const API_BASE: string = (raw || window.location.origin).replace(/\/+$/, "");

export const WS_BASE: string = API_BASE.replace(/^http/i, "ws");

export function mediaUrl(path?: string | null): string {
  if (!path) return "";
  if (/^https?:\/\//i.test(path)) return path;
  return `${API_BASE}${path.startsWith("/") ? "" : "/"}${path}`;
}

export const FIREBASE_CONFIG = {
  apiKey: (import.meta.env.VITE_FIREBASE_API_KEY as string) || "",
  authDomain: (import.meta.env.VITE_FIREBASE_AUTH_DOMAIN as string) || "lailanowfcm.firebaseapp.com",
  projectId: (import.meta.env.VITE_FIREBASE_PROJECT_ID as string) || "lailanowfcm",
  messagingSenderId: (import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID as string) || "141308428641",
  appId: (import.meta.env.VITE_FIREBASE_APP_ID as string) || "",
};

export const VAPID_KEY: string = (import.meta.env.VITE_FIREBASE_VAPID_KEY as string) || "";
export const APP_NAME = "Lailanow";
export const MAX_CHAT_LENGTH = 100;
export const RING_TIMEOUT_SECONDS = 55;

const lkOverride = ((import.meta.env.VITE_LIVEKIT_URL as string | undefined) ?? "").trim();

export function resolveLivekitUrl(serverUrl: string): string {
  const url = lkOverride || serverUrl;
  if (window.location.protocol === "https:" && /^ws:\/\//i.test(url)) {
    throw new Error("Call server must use wss:// when the app is opened over https. Set VITE_LIVEKIT_URL.");
  }
  return url;
}
