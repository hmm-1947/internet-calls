import { WS_BASE } from "./config";
import { api, session } from "./api";

export type WsEvent = { type: string; [k: string]: any };
type Handler = (e: WsEvent) => void;

class Socket {
  private ws: WebSocket | null = null;
  private handlers = new Set<Handler>();
  private pingTimer: number | undefined;
  private reconnectTimer: number | undefined;
  private attempts = 0;
  private stopped = true;
  connected = false;

  on(h: Handler) {
    this.handlers.add(h);
    return () => { this.handlers.delete(h); };
  }

  private emit(e: WsEvent) {
    this.handlers.forEach((h) => { try { h(e); } catch (err) { console.error(err); } });
  }

  start() {
    this.stopped = false;
    this.open();
  }

  stop() {
    this.stopped = true;
    this.connected = false;
    window.clearInterval(this.pingTimer);
    window.clearTimeout(this.reconnectTimer);
    const w = this.ws;
    this.ws = null;
    if (w) { w.onclose = null; w.onmessage = null; w.onerror = null; try { w.close(); } catch { /* noop */ } }
  }

  send(data: unknown) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(data));
  }

  sendTyping(listenerId: number, isTyping: boolean) {
    this.send({ type: "typing", listener_id: listenerId, is_typing: isTyping });
  }

  private open() {
    if (this.stopped) return;
    const token = session.token;
    if (!token) return;
    window.clearTimeout(this.reconnectTimer);
    const old = this.ws;
    if (old) { old.onclose = null; try { old.close(); } catch { /* noop */ } }
    const ws = new WebSocket(`${WS_BASE}/chat/ws/user?token=${encodeURIComponent(token)}`);
    this.ws = ws;
    ws.onopen = () => {
      this.attempts = 0;
      this.connected = true;
      window.clearInterval(this.pingTimer);
      this.pingTimer = window.setInterval(() => this.send({ type: "ping" }), 10000);
      this.emit({ type: "socket_connected" });
    };
    ws.onmessage = (ev) => {
      let data: WsEvent;
      try { data = JSON.parse(ev.data); } catch { return; }
      if (data.type === "ping") { this.send({ type: "ping" }); return; }
      this.emit(data);
    };
    ws.onerror = () => { /* onclose follows */ };
    ws.onclose = (ev) => {
      if (this.ws !== ws) return;
      this.connected = false;
      window.clearInterval(this.pingTimer);
      this.emit({ type: "socket_disconnected" });
      if (this.stopped) return;
      if (ev.code === 4001 || ev.code === 4003) {
        this.verifyThenReconnect();
        return;
      }
      this.schedule();
    };
  }

  private async verifyThenReconnect() {
    try {
      await api.sessionCheck();
      this.schedule();
    } catch (e) {
      const status = (e as { status?: number }).status;
      if (status === 401) { this.emit({ type: "force_logout" }); return; }
      this.schedule();
    }
  }

  private schedule() {
    if (this.stopped) return;
    const delay = Math.min(30, 1 + this.attempts * 2) * 1000;
    this.attempts += 1;
    window.clearTimeout(this.reconnectTimer);
    this.reconnectTimer = window.setTimeout(() => this.open(), delay);
  }

  ensureConnected() {
    if (this.stopped) return;
    if (!this.ws || this.ws.readyState === WebSocket.CLOSED) this.open();
  }
}

export const socket = new Socket();
