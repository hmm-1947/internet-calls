import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { normalizePhone, passwordValid, phoneError } from "../lib/util";
import { AuthLayout, OtpInput, PasswordChecklist, PasswordField, PhoneField, Spinner, useCountdown } from "../components/ui";
import { useApp } from "../state/app";

type Step = "phone" | "otp" | "reset";

export default function Forgot() {
  const nav = useNavigate();
  const { toast } = useApp();
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [phoneErr, setPhoneErr] = useState<string | null>(null);
  const [left, setLeft] = useCountdown(0);
  const id = normalizePhone(phone);

  const request = async (e?: React.FormEvent) => {
    e?.preventDefault();
    const pe = phoneError(phone);
    setPhoneErr(pe);
    if (pe) return;
    setErr(null);
    setBusy(true);
    try {
      await api.forgotRequest(id);
      setOtp("");
      setLeft(30);
      setStep("otp");
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
      await api.forgotVerify(id, otp);
      setStep("reset");
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  const reset = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!passwordValid(pw)) { setErr("Password does not meet all the requirements"); return; }
    if (pw !== pw2) { setErr("Passwords do not match"); return; }
    setErr(null);
    setBusy(true);
    try {
      await api.forgotReset(id, otp, pw);
      toast("Password updated. Log in with your new password.", "success");
      nav("/login", { replace: true });
    } catch (e2) {
      setErr(friendly(e2));
    } finally {
      setBusy(false);
    }
  };

  if (step === "otp") {
    return (
      <AuthLayout title="Enter code" subtitle={`We sent a 4-digit code to +91 ${id}`} onBack={() => { setErr(null); setStep("phone"); }}>
        <form onSubmit={verify} className="space-y-4">
          <OtpInput value={otp} onChange={setOtp} autoFocus />
          {err && <p className="text-sm text-red-400">{err}</p>}
          <button className="btn btn-primary w-full" disabled={busy || otp.length !== 4}>{busy && <Spinner size={16} />}Verify</button>
          <div className="text-center text-sm text-muted">
            {left > 0 ? `Resend code in ${left}s` : <button type="button" onClick={() => void request()} disabled={busy} className="font-semibold text-brand-soft hover:underline">Resend code</button>}
          </div>
        </form>
      </AuthLayout>
    );
  }

  if (step === "reset") {
    return (
      <AuthLayout title="New password" subtitle="Choose a strong password you have not used before">
        <form onSubmit={reset} className="space-y-4">
          <PasswordField label="New password" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="new-password" />
          {pw && <PasswordChecklist value={pw} />}
          <PasswordField label="Confirm password" value={pw2} onChange={(e) => setPw2(e.target.value)} autoComplete="new-password" />
          {err && <p className="text-sm text-red-400">{err}</p>}
          <button className="btn btn-primary w-full" disabled={busy}>{busy && <Spinner size={16} />}Update password</button>
        </form>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout title="Forgot password" subtitle="Enter your phone number and we will send you a code" onBack={() => nav("/login")}>
      <form onSubmit={request} className="space-y-4">
        <PhoneField value={phone} onChange={setPhone} error={phoneErr} autoComplete="tel" />
        {err && <p className="text-sm text-red-400">{err}</p>}
        <button className="btn btn-primary w-full" disabled={busy}>{busy && <Spinner size={16} />}Send code</button>
      </form>
      <p className="text-center text-sm text-muted">
        Remembered it? <Link to="/login" className="font-semibold text-brand-soft hover:underline">Log in</Link>
      </p>
    </AuthLayout>
  );
}
