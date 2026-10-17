import { APP_NAME } from "./config";

const BASE_TITLE = APP_NAME;
let unread = 0;
let beep: HTMLAudioElement | null = null;

export const notificationsSupported = () => typeof Notification !== "undefined";
export const notificationPermission = (): NotificationPermission | "unsupported" =>
  notificationsSupported() ? Notification.permission : "unsupported";

export async function requestNotificationPermission(): Promise<NotificationPermission | "unsupported"> {
  if (!notificationsSupported()) return "unsupported";
  try { return await Notification.requestPermission(); } catch { return Notification.permission; }
}

export function setTitleBadge(count: number) {
  unread = Math.max(0, count);
  document.title = unread > 0 ? `(${unread > 99 ? "99+" : unread}) ${BASE_TITLE}` : BASE_TITLE;
}

export function showChatNotification(opts: { title: string; body: string; tag: string; icon?: string; onClick?: () => void }) {
  if (!notificationsSupported() || Notification.permission !== "granted") return;
  try {
    const n = new Notification(opts.title, { body: opts.body, tag: opts.tag, icon: opts.icon || `${import.meta.env.BASE_URL}logo.png`, silent: false });
    n.onclick = () => { window.focus(); opts.onClick?.(); n.close(); };
  } catch { /* some browsers need a service worker */ }
}

export function playPing() {
  try {
    if (!beep) {
      beep = new Audio(`${import.meta.env.BASE_URL}no_response.mp3`);
      beep.volume = 0.4;
    }
    beep.currentTime = 0;
    void beep.play();
  } catch { /* noop */ }
}
