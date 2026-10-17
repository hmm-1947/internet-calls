import { useEffect, useState } from "react";
import { api } from "./api";
import { usernameError } from "./util";

export type UsernameState = { status: "idle" | "checking" | "ok" | "bad"; message: string | null };

export function useUsernameCheck(username: string, skip?: string | null): UsernameState {
  const [state, setState] = useState<UsernameState>({ status: "idle", message: null });
  useEffect(() => {
    const v = username.trim();
    if (!v) { setState({ status: "idle", message: null }); return; }
    const local = usernameError(v);
    if (local) { setState({ status: "bad", message: local }); return; }
    if (skip && v.toLowerCase() === skip.toLowerCase()) { setState({ status: "ok", message: null }); return; }
    setState({ status: "checking", message: null });
    let live = true;
    const t = window.setTimeout(async () => {
      try {
        const r = await api.usernameAvailable(v);
        if (live) setState(r.available ? { status: "ok", message: null } : { status: "bad", message: r.reason || "Username is taken" });
      } catch {
        if (live) setState({ status: "idle", message: null });
      }
    }, 400);
    return () => { live = false; window.clearTimeout(t); };
  }, [username, skip]);
  return state;
}
