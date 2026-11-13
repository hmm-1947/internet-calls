import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { useUsernameCheck } from "../lib/hooks";
import { displayNameError, usernameError } from "../lib/util";
import { useApp } from "../state/app";
import { AuthLayout, Field, Spinner } from "../components/ui";

export default function ProfileSetup() {
  const nav = useNavigate();
  const { authUser, refreshMe, logout } = useApp();
  const [username, setUsername] = useState("");
  const [display, setDisplay] = useState(authUser?.name ?? "");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const uname = useUsernameCheck(username);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const ue = usernameError(username) || (uname.status === "bad" ? uname.message : null);
    const de = displayNameError(display);
    if (ue || de) { setErr(ue || de); return; }
    setErr(null);
    setBusy(true);
    try {
      await api.updateProfile({ username: username.trim(), display_name: display.trim() });
      await refreshMe();
      nav("/", { replace: true });
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthLayout title="Set up your profile" subtitle="Pick a unique username and the name others will see">
      <form onSubmit={submit} className="space-y-4">
        <Field
          label="Username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          maxLength={20}
          placeholder="e.g. sam.rao"
          error={uname.status === "bad" ? uname.message : null}
          hint={uname.status === "checking" ? "Checking…" : uname.status === "ok" ? "Username is available" : undefined}
        />
        <Field label="Display name" value={display} onChange={(e) => setDisplay(e.target.value)} maxLength={30} />
        {err && <p className="text-sm text-red-400">{err}</p>}
        <button className="btn btn-primary w-full" disabled={busy || uname.status === "checking"}>{busy && <Spinner size={16} />}Continue</button>
        <button type="button" onClick={() => void logout()} className="w-full text-center text-sm text-muted hover:text-ink">Use a different account</button>
      </form>
    </AuthLayout>
  );
}
