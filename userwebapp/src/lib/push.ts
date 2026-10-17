import { getMessaging, getToken, deleteToken, isSupported } from "firebase/messaging";
import { api } from "./api";
import { FIREBASE_CONFIG, VAPID_KEY } from "./config";
import { firebaseApp, firebaseConfigured } from "./firebase";

const KEY = "lailanow_web_push_token";

export const pushConfigured = () => firebaseConfigured() && !!VAPID_KEY;

async function registration() {
  const p = new URLSearchParams({
    apiKey: FIREBASE_CONFIG.apiKey,
    authDomain: FIREBASE_CONFIG.authDomain,
    projectId: FIREBASE_CONFIG.projectId,
    messagingSenderId: FIREBASE_CONFIG.messagingSenderId,
    appId: FIREBASE_CONFIG.appId,
    base: import.meta.env.BASE_URL,
  });
  return navigator.serviceWorker.register(`${import.meta.env.BASE_URL}firebase-messaging-sw.js?${p.toString()}`, {
    scope: import.meta.env.BASE_URL,
  });
}

export async function enableWebPush(): Promise<boolean> {
  try {
    if (!pushConfigured() || !("serviceWorker" in navigator) || !(await isSupported())) return false;
    if (typeof Notification === "undefined" || Notification.permission !== "granted") return false;
    const reg = await registration();
    const token = await getToken(getMessaging(firebaseApp()), { vapidKey: VAPID_KEY, serviceWorkerRegistration: reg });
    if (!token) return false;
    if (localStorage.getItem(KEY) !== token) {
      await api.registerWebPush(token);
      localStorage.setItem(KEY, token);
    } else {
      await api.registerWebPush(token).catch(() => undefined);
    }
    return true;
  } catch {
    return false;
  }
}

export async function disableWebPush(): Promise<void> {
  let token: string | null = null;
  try { token = localStorage.getItem(KEY); } catch { /* noop */ }
  if (!token) return;
  try { await api.unregisterWebPush(token); } catch { /* noop */ }
  try { localStorage.removeItem(KEY); } catch { /* noop */ }
  try { if (await isSupported()) await deleteToken(getMessaging(firebaseApp())); } catch { /* noop */ }
}
