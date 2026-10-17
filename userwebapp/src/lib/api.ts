import { API_BASE } from "./config";
import type {
  AuthResponse, CallHistoryItem, CallSummary, ChatMsg, Gift, Listener, Me, Plan, Purchase, Thread,
} from "./types";

const TOKEN_KEY = "lw_token";
const USER_KEY = "lw_user";

export const session = {
  get token(): string | null {
    try { return localStorage.getItem(TOKEN_KEY); } catch { return null; }
  },
  get user(): { id: number; name: string } | null {
    try { const v = localStorage.getItem(USER_KEY); return v ? JSON.parse(v) : null; } catch { return null; }
  },
  save(token: string, id: number, name: string) {
    try {
      localStorage.setItem(TOKEN_KEY, token);
      localStorage.setItem(USER_KEY, JSON.stringify({ id, name }));
    } catch { /* storage unavailable */ }
  },
  clear() {
    try { localStorage.removeItem(TOKEN_KEY); localStorage.removeItem(USER_KEY); } catch { /* noop */ }
  },
};

type Listener0 = () => void;
const invalidListeners = new Set<Listener0>();
export const onSessionInvalid = (fn: Listener0) => {
  invalidListeners.add(fn);
  return () => { invalidListeners.delete(fn); };
};

export class ApiError extends Error {
  status: number;
  constructor(message: string, status = 0) {
    super(message);
    this.status = status;
  }
}

export class InsufficientCoinsError extends ApiError {}

function detailOf(data: unknown): string | null {
  if (!data || typeof data !== "object") return null;
  const d = (data as { detail?: unknown }).detail;
  if (typeof d === "string") return d;
  if (Array.isArray(d) && d.length) {
    const first = d[0] as { msg?: string };
    if (typeof first?.msg === "string") return first.msg.replace(/^Value error, /, "");
  }
  return null;
}

interface ReqOpts { auth?: boolean; timeout?: number; token?: string | null }

async function request<T>(method: string, path: string, body?: unknown, opts: ReqOpts = {}): Promise<T> {
  const headers: Record<string, string> = { "X-Client": "web" };
  const isForm = typeof FormData !== "undefined" && body instanceof FormData;
  if (body !== undefined && !isForm) headers["Content-Type"] = "application/json";
  const token = opts.token !== undefined ? opts.token : opts.auth === false ? null : session.token;
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), opts.timeout ?? 20000);
  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : isForm ? (body as FormData) : JSON.stringify(body),
      signal: ctrl.signal,
    });
  } catch (e) {
    const aborted = (e as { name?: string })?.name === "AbortError";
    throw new ApiError(
      aborted
        ? "The server is taking too long to respond. Please try again in a moment."
        : "Could not reach the server. Check your connection and try again.",
    );
  } finally {
    clearTimeout(timer);
  }
  let data: unknown = null;
  const text = await res.text();
  if (text) { try { data = JSON.parse(text); } catch { data = null; } }
  if (!res.ok) {
    if (res.status === 401 && token) invalidListeners.forEach((f) => f());
    const msg = detailOf(data) ?? `Request failed (${res.status})`;
    if (res.status === 402) throw new InsufficientCoinsError(msg, 402);
    throw new ApiError(msg, res.status);
  }
  return data as T;
}

const get = <T>(p: string, o?: ReqOpts) => request<T>("GET", p, undefined, o);
const post = <T>(p: string, b: unknown = {}, o?: ReqOpts) => request<T>("POST", p, b, o);

export const friendly = (e: unknown, fallback = "Something went wrong. Please try again."): string =>
  e instanceof Error && e.message ? e.message : fallback;

export interface Availability { available: boolean; reason: string | null }
export interface GoogleAuth extends AuthResponse { profile_complete: boolean }

export const api = {
  endOrCancelKeepalive: (id: number, path: "end" | "cancel") => {
    const token = session.token;
    if (!token) return Promise.resolve();
    return fetch(`${API_BASE}/call/${id}/${path}`, {
      method: "POST",
      keepalive: true,
      headers: { "X-Client": "web", Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: "{}",
    }).then(() => undefined).catch(() => undefined);
  },
  identifierAvailable: (identifier: string) =>
    get<Availability>(`/user/identifier/available?identifier=${encodeURIComponent(identifier)}`, { auth: false }),
  usernameAvailable: (username: string) =>
    get<Availability>(`/user/username/available?username=${encodeURIComponent(username)}`),
  registerInitiate: (identifier: string, password: string, confirm_password: string) =>
    post<{ identifier: string; otp_sent: boolean }>("/user/register/initiate", { identifier, password, confirm_password }, { auth: false }),
  registerResendOtp: (identifier: string) => post("/user/register/resend-otp", { identifier }, { auth: false }),
  registerVerifyPhone: (identifier: string, otp_code: string) =>
    post<{ signup_token: string }>("/user/register/verify-phone", { identifier, otp_code }, { auth: false }),
  registerComplete: (signup_token: string, username: string, display_name: string) =>
    post<AuthResponse>("/user/register/complete", { signup_token, username, display_name }, { auth: false }),
  login: (identifier: string, password: string) =>
    post<AuthResponse>("/user/login/initiate", { identifier, password }, { auth: false }),
  googleSignIn: (id_token: string) => post<GoogleAuth>("/user/auth/google", { id_token }, { auth: false }),
  forgotRequest: (identifier: string) => post("/user/forgot-password/request-otp", { identifier }, { auth: false }),
  forgotVerify: (identifier: string, otp_code: string) =>
    post("/user/forgot-password/verify-otp", { identifier, otp_code }, { auth: false }),
  forgotReset: (identifier: string, otp_code: string, new_password: string) =>
    post("/user/forgot-password/reset", { identifier, otp_code, new_password }, { auth: false }),
  sessionCheck: (token?: string) => get<{ valid: boolean }>("/user/session/check", token ? { token } : undefined),
  logout: () => post("/user/logout"),
  deleteAccount: (reason?: string) => post("/user/delete-account", reason?.trim() ? { reason: reason.trim() } : {}),
  verifyPassword: (current_password: string) => post("/user/verify-password", { current_password }),
  changePassword: (current_password: string, new_password: string) =>
    post("/user/change-password", { current_password, new_password }),

  me: () => get<Me>("/user/me"),
  listeners: () => get<Listener[]>("/user/listeners"),
  listener: (id: number) => get<Listener>(`/user/listener/${id}`),
  updateProfile: (p: { display_name?: string; username?: string; bio?: string }) =>
    post<Record<string, unknown>>("/user/profile", p),
  updatePhoto: (blob: Blob, filename = "photo.jpg") => {
    const fd = new FormData();
    fd.append("file", blob, filename);
    return post<{ photo_url: string }>("/user/photo", fd, { timeout: 60000 });
  },
  contactRequestOtp: (identifier: string) => post("/user/contact/request-otp", { identifier }),
  contactVerify: (identifier: string, otp_code: string) =>
    post<Record<string, unknown>>("/user/contact/verify", { identifier, otp_code }),
  videoSetting: (enabled: boolean) => post("/user/video-call-setting", { enabled }),
  registerWebPush: (token: string) => post("/user/web-push-token", { token }),
  unregisterWebPush: (token: string) => request("DELETE", "/user/web-push-token", { token }),

  initiateCall: (listener_id: number, call_type: "audio" | "video") =>
    post<{ call_id: number }>("/call/initiate", { listener_id, call_type }),
  callStatus: (id: number) =>
    get<{ status: string; call_type: string; room_name?: string; token?: string; livekit_url?: string; elapsed_seconds?: number }>(`/call/${id}/status`),
  cancelCall: (id: number) => post(`/call/${id}/cancel`),
  timeoutCall: (id: number) => post(`/call/${id}/timeout`),
  endCall: (id: number) => post(`/call/${id}/end`),
  startRecording: (id: number) => post(`/call/${id}/recording/start`),
  coinStatus: (id: number) => get<{ coins: number; max_seconds: number }>(`/call/${id}/coin-status`),
  coinExceeded: (id: number) => post(`/call/${id}/coin-exceeded`),
  callHistory: (beforeId?: number, limit = 25) =>
    get<CallHistoryItem[]>(`/call/user/history?limit=${limit}${beforeId ? `&before_id=${beforeId}` : ""}`),
  callSummary: (id: number) => get<CallSummary>(`/call/${id}/summary`),
  rateCall: (id: number, rating: number, review: string) => post(`/call/${id}/rate`, { rating, review }),

  threads: () => get<Thread[]>("/chat/user/threads"),
  messages: (listenerId: number, beforeId?: number) =>
    get<ChatMsg[]>(`/chat/user/${listenerId}/messages${beforeId ? `?before_id=${beforeId}` : ""}`),
  sendMessage: (listener_id: number, message: string, client_id: string) =>
    post<ChatMsg>("/chat/user/send", { listener_id, message, client_id }),
  sendVoice: (listenerId: number, blob: Blob, filename: string, duration: number, clientId: string) => {
    const fd = new FormData();
    fd.append("listener_id", String(listenerId));
    fd.append("duration", String(duration));
    fd.append("client_id", clientId);
    fd.append("file", blob, filename);
    return post<ChatMsg>("/chat/user/send-voice", fd, { timeout: 60000 });
  },
  markRead: (listenerId: number) => post(`/chat/user/${listenerId}/mark_read`),
  markDelivered: (ids: number[]) => post("/chat/user/delivered", { message_ids: ids }),
  chatSettings: (other_id: number, s: { is_pinned?: boolean; is_archived?: boolean; is_muted?: boolean }) =>
    post("/chat/settings", { other_id, ...s }),

  gifts: () => get<Gift[]>("/gift/catalog"),
  sendGift: (listener_id: number, gift_id: number, call_id?: number) =>
    post<Record<string, unknown>>("/gift/send", { listener_id, gift_id, ...(call_id ? { call_id } : {}) }),

  plans: () => get<Plan[]>("/billing/plans"),
  purchase: (planId: number) =>
    post<{
      purchase_id: number; order_id: string; amount: number; currency: string; key_id: string;
      plan_name: string; coins: number; name?: string; email?: string; contact?: string;
    }>(`/billing/purchase/${planId}`),
  verifyPayment: (razorpay_order_id: string, razorpay_payment_id: string, razorpay_signature: string) =>
    post<{ coins_balance: number; status: string }>("/billing/verify-payment", {
      razorpay_order_id, razorpay_payment_id, razorpay_signature,
    }),
  paymentFailed: (razorpay_order_id: string, reason?: string) =>
    post("/billing/payment-failed", { razorpay_order_id, reason }).catch(() => undefined),
  myPurchases: () => get<Purchase[]>("/billing/my-purchases"),

  upgradeBanner: () => get<{ upgrade_banner_url: string | null }>("/app-settings/upgrade-banner", { auth: false }),
  specialOffers: () => get<{ id: number; image_url: string }[]>("/special-offers", { auth: false }),
  termsPrivacy: () => get<{ terms_of_service: string; privacy_policy: string }>("/app-settings/terms-privacy", { auth: false }),
  enrollContact: () => get<{ whatsapp_number: string | null }>("/app-settings/enroll-contact", { auth: false }),
};
