import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { googleIdToken } from "../lib/firebase";
import { normalizePhone, phoneError } from "../lib/util";
import { useApp } from "../state/app";
import { AuthLayout, GoogleButton, PasswordField, PhoneField, Spinner } from "../components/ui";

export default function Login() {
  const { login, flash, clearFlash } = useApp();
  const nav = useNavigate();
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [gBusy, setGBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [phoneErr, setPhoneErr] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    clearFlash();
    const pe = phoneError(phone);
    setPhoneErr(pe);
    if (pe) return;
    if (!password) { setErr("Enter your password"); return; }
    setErr(null);
    setBusy(true);
    try {
      login(await api.login(normalizePhone(phone), password));
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  const google = async () => {
    clearFlash();
    setErr(null);
    setGBusy(true);
    try {
      const idToken = await googleIdToken();
      const r = await api.googleSignIn(idToken);
      login({ token: r.token, id: r.id, name: r.name });
      if (!r.profile_complete) nav("/setup", { replace: true });
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setGBusy(false);
    }
  };

  return (
    <AuthLayout title="Welcome back" subtitle="Log in to talk to your favourite listeners">
      {flash && <div className="rounded-xl border border-gold/30 bg-gold/10 px-4 py-3 text-sm text-gold">{flash}</div>}
      <form onSubmit={submit} className="space-y-4">
        <PhoneField value={phone} onChange={setPhone} error={phoneErr} autoComplete="tel" />
        <PasswordField label="Password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" placeholder="Your password" />
        {err && <p className="text-sm text-red-400">{err}</p>}
        <div className="text-right">
          <Link to="/forgot" className="text-sm text-brand-soft hover:underline">Forgot password?</Link>
        </div>
        <button className="btn btn-primary w-full" disabled={busy}>{busy && <Spinner size={16} />}Log in</button>
      </form>
      <div className="flex items-center gap-3 text-xs text-muted"><span className="h-px flex-1 bg-white/10" />or<span className="h-px flex-1 bg-white/10" /></div>
      <GoogleButton onClick={google} busy={gBusy} />
      <p className="pt-2 text-center text-sm text-muted">
        New here? <Link to="/register" className="font-semibold text-brand-soft hover:underline">Create an account</Link>
      </p>
    </AuthLayout>
  );
}
