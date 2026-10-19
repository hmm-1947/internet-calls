let holds = 0;
let timer: number | undefined;

function apply() {
  const on = holds > 0;
  if (on) document.documentElement.setAttribute("data-shield", "1");
  else document.documentElement.removeAttribute("data-shield");
}

function hold() {
  holds += 1;
  apply();
}

function release() {
  holds = Math.max(0, holds - 1);
  apply();
}

function pulse(ms: number) {
  hold();
  window.setTimeout(release, ms);
}

function wipeClipboard() {
  try {
    void navigator.clipboard?.writeText("");
  } catch {}
}

export function startCaptureGuard() {
  let blurHeld = false;
  const setBlur = (on: boolean) => {
    if (on && !blurHeld) { blurHeld = true; hold(); }
    else if (!on && blurHeld) { blurHeld = false; release(); }
  };

  const onKey = (e: KeyboardEvent) => {
    const k = e.key;
    const code = e.code;
    const snip =
      k === "PrintScreen" ||
      code === "PrintScreen" ||
      k === "Snapshot" ||
      (e.metaKey && e.shiftKey && (k === "S" || k === "s")) ||
      (e.metaKey && e.shiftKey && ["3", "4", "5", "#", "$", "%"].includes(k)) ||
      (e.ctrlKey && e.shiftKey && (k === "S" || k === "s")) ||
      (e.altKey && k === "PrintScreen");
    if (snip) {
      pulse(4000);
      wipeClipboard();
      if (e.type === "keydown") e.preventDefault();
    }
    if (e.metaKey && e.shiftKey) setBlur(true);
    if ((e.ctrlKey || e.metaKey) && (k === "p" || k === "P")) {
      e.preventDefault();
      pulse(1500);
    }
  };

  const onBlur = () => setBlur(true);
  const onFocus = () => window.setTimeout(() => setBlur(false), 250);
  const onVis = () => {
    if (document.visibilityState === "hidden") setBlur(true);
    else onFocus();
  };
  const onBeforePrint = () => hold();
  const onAfterPrint = () => release();

  window.addEventListener("keydown", onKey, true);
  window.addEventListener("keyup", onKey, true);
  window.addEventListener("blur", onBlur);
  window.addEventListener("focus", onFocus);
  document.addEventListener("visibilitychange", onVis);
  window.addEventListener("beforeprint", onBeforePrint);
  window.addEventListener("afterprint", onAfterPrint);

  const md = navigator.mediaDevices as MediaDevices | undefined;
  if (md && typeof md.getDisplayMedia === "function") {
    const orig = md.getDisplayMedia.bind(md);
    md.getDisplayMedia = async (...args: Parameters<MediaDevices["getDisplayMedia"]>) => {
      const stream = await orig(...args);
      hold();
      let done = false;
      const end = () => { if (!done) { done = true; release(); } };
      stream.getTracks().forEach((t) => t.addEventListener("ended", end));
      stream.addEventListener("inactive", end);
      return stream;
    };
  }

  const mq = window.matchMedia?.("(display-mode: picture-in-picture)");
  void mq;
}
