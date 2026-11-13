import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { googleIdToken } from "../lib/firebase";
import { useUsernameCheck } from "../lib/hooks";
import { displayNameError, normalizePhone, passwordValid, phoneError, usernameError } from "../lib/util";
import { useApp } from "../state/app";
import {
  AuthLayout, Field, GoogleButton, OtpInput, PasswordChecklist, PasswordField, PhoneField, Spinner, useCountdown,
} from "../components/ui";

type Step = "details" | "otp" | "profile";

export default function Register() {
  const { login } = useApp();
  const nav = useNavigate();
  const [step, setStep] = useState<Step>("details");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [otp, setOtp] = useState("");
  const [signupToken, setSignupToken] = useState("");
  const [username, setUsername] = useState("");
  const [display, setDisplay] = useState("");
  const [busy, setBusy] = useState(false);
  const [gBusy, setGBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [phoneErr, setPhoneErr] = useState<string | null>(null);
  const [left, setLeft] = useCountdown(0);
  const uname = useUsernameCheck(username);
  const id = normalizePhone(phone);

  const sendOtp = async (e?: React.FormEvent) => {
    e?.preventDefault();
    const pe = phoneError(phone);
    setPhoneErr(pe);
    if (pe) return;
    if (!passwordValid(password)) { setErr("Password does not meet all the requirements"); return; }
    if (password !== confirm) { setErr("Passwords do not match"); return; }
    setErr(null);
    setBusy(true);
    try {
      await api.registerInitiate(id, password, confirm);
      setOtp("");
      setLeft(30);
      setStep("otp");
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  const resend = async () => {
    setErr(null);
    setBusy(true);
    try {
      await api.registerResendOtp(id);
      setOtp("");
      setLeft(30);
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  const verify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (otp.length !== 4) { setErr("Enter the 4-digit code"); return; }
    setErr(null);
    setBusy(true);
    try {
      const r = await api.registerVerifyPhone(id, otp);
      setSignupToken(r.signup_token);
      setStep("profile");
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  const complete = async (e: React.FormEvent) => {
    e.preventDefault();
    const ue = usernameError(username) || (uname.status === "bad" ? uname.message : null);
    const de = displayNameError(display);
    if (ue || de) { setErr(ue || de); return; }
    setErr(null);
    setBusy(true);
    try {
      login(await api.registerComplete(signupToken, username.trim(), display.trim()));
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  const google = async () => {
    setErr(null);
    setGBusy(true);
    try {
      const r = await api.googleSignIn(await googleIdToken());
      login({ token: r.token, id: r.id, name: r.name });
      if (!r.profile_complete) nav("/setup", { replace: true });
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setGBusy(false);
    }
  };

  if (step === "otp") {
    return (
      <AuthLayout title="Verify phone" subtitle={`Enter the 4-digit code sent to +91 ${id}`} onBack={() => { setErr(null); setStep("details"); }}>
        <form onSubmit={verify} className="space-y-4">
          <OtpInput value={otp} onChange={setOtp} autoFocus />
          {err && <p className="text-sm text-red-400">{err}</p>}
          <button className="btn btn-primary w-full" disabled={busy || otp.length !== 4}>{busy && <Spinner size={16} />}Verify</button>
          <div className="text-center text-sm text-muted">
            {left > 0 ? `Resend code in ${left}s` : <button type="button" onClick={resend} disabled={busy} className="font-semibold text-brand-soft hover:underline">Resend code</button>}
          </div>
        </form>
      </AuthLayout>
    );
  }

  if (step === "profile") {
    return (
      <AuthLayout title="Set up your profile" subtitle="Pick a unique username and the name others will see">
        <form onSubmit={complete} className="space-y-4">
          <Field
            label="Username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoComplete="username"
            maxLength={20}
            placeholder="e.g. sam.rao"
            error={uname.status === "bad" ? uname.message : null}
            hint={uname.status === "checking" ? "Checking…" : uname.status === "ok" ? "Username is available" : undefined}
          />
          <Field label="Display name" value={display} onChange={(e) => setDisplay(e.target.value)} maxLength={30} placeholder="Your name" />
          {err && <p className="text-sm text-red-400">{err}</p>}
          <button className="btn btn-primary w-full" disabled={busy || uname.status === "checking"}>{busy && <Spinner size={16} />}Finish</button>
        </form>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout title="Create account" subtitle="Sign up with your phone number">
      <form onSubmit={sendOtp} className="space-y-4">
        <PhoneField value={phone} onChange={setPhone} error={phoneErr} autoComplete="tel" />
        <PasswordField label="Password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" placeholder="Create a password" />
        {password && <PasswordChecklist value={password} />}
        <PasswordField label="Confirm password" value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="new-password" placeholder="Repeat password" />
        {err && <p className="text-sm text-red-400">{err}</p>}
        <button className="btn btn-primary w-full" disabled={busy}>{busy && <Spinner size={16} />}Send code</button>
      </form>
      <div className="flex items-center gap-3 text-xs text-muted"><span className="h-px flex-1 bg-black/10" />or<span className="h-px flex-1 bg-black/10" /></div>
      <GoogleButton onClick={google} busy={gBusy} />
      <p className="pt-2 text-center text-sm text-muted">
        Already have an account? <Link to="/login" className="font-semibold text-brand-soft hover:underline">Log in</Link>
      </p>
    </AuthLayout>
  );
}
