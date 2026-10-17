type Msg = { type: "hello" | "active" | "takeover"; from: string };

const CHANNEL = "lailanow-user-web-tab";
const tabId = Math.random().toString(36).slice(2);

export type TabState = "checking" | "active" | "blocked";

export function startTabGuard(onChange: (s: TabState) => void) {
  if (typeof BroadcastChannel === "undefined") {
    onChange("active");
    return { takeOver() {}, dispose() {} };
  }
  const ch = new BroadcastChannel(CHANNEL);
  let state: TabState = "checking";
  const set = (s: TabState) => { state = s; onChange(s); };

  ch.onmessage = (ev: MessageEvent<Msg>) => {
    const m = ev.data;
    if (!m || m.from === tabId) return;
    if (m.type === "hello" && state === "active") ch.postMessage({ type: "active", from: tabId } as Msg);
    else if (m.type === "active" && state === "checking") set("blocked");
    else if (m.type === "takeover" && state === "active") set("blocked");
  };

  ch.postMessage({ type: "hello", from: tabId } as Msg);
  const timer = window.setTimeout(() => { if (state === "checking") set("active"); }, 500);

  return {
    takeOver() {
      ch.postMessage({ type: "takeover", from: tabId } as Msg);
      set("active");
    },
    dispose() {
      window.clearTimeout(timer);
      ch.close();
    },
  };
}
