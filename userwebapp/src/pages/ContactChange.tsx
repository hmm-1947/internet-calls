import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { normalizePhone, phoneError } from "../lib/util";
import { useApp } from "../state/app";
import { OtpInput, PageHeader, PhoneField, Spinner, useCountdown } from "../components/ui";

export default function ContactChange() {
  const nav = useNavigate();
  const { me, refreshMe, toast } = useApp();
  const [step, setStep] = useState<1 | 2>(1);
  const [phone, setPhone] = useState("");
  const [sentTo, setSentTo] = useState("");
  const [otp, setOtp] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [left, setLeft] = useCountdown(0);

  

  const send = async (e?: React.FormEvent) => {
    e?.preventDefault();
    const pe = phoneError(phone);
    if (pe) { setError(pe); return; }
    setBusy(true);
    setError(null);
    try {
      const r = (await api.contactRequestOtp(normalizePhone(phone))) as { identifier?: string };
      setSentTo(r?.identifier || normalizePhone(phone));
      setOtp("");
      setStep(2);
      setLeft(30);
    } catch (err) {
      setError(friendly(err));
    } finally {
      setBusy(false);
    }
  };

  const verify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (otp.length !== 4) { setError("Enter the 4-digit code"); return; }
    setBusy(true);
    setError(null);
    try {
      await api.contactVerify(sentTo, otp);
      await refreshMe();
      toast("Phone number verified and saved", "success");
      nav("/settings/profile", { replace: true });
    } catch (err) {
      setError(friendly(err, "Invalid OTP"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <PageHeader title="Phone number" onBack={() => (step === 2 ? setStep(1) : nav("/settings/profile"))} />
      <div className="mx-auto w-full max-w-md px-4 pb-12 pt-8">
        {step === 1 ? (
          <form onSubmit={send} className="space-y-5">
            {me?.phone && (
              <div>
                <label className="label">Current number</label>
                <div className="rounded-xl border border-white/10 bg-card2 px-4 py-3 text-sm text-white/70">+91 {me.phone}</div>
              </div>
            )}
            <PhoneField label="New phone number" value={phone} onChange={setPhone} autoFocus />
            <p className="text-xs text-muted">We will send a 4-digit code to verify the new number. A phone number can only be changed once in a while.</p>
            {error && <p className="text-sm text-red-400">{error}</p>}
            <button className="btn btn-primary w-full" disabled={busy}>{busy && <Spinner size={14} />}Send code</button>
          </form>
        ) : (
          <form onSubmit={verify} className="space-y-5">
            <p className="text-sm text-muted">Enter the 4-digit code sent to +91 {sentTo}.</p>
            <OtpInput value={otp} onChange={setOtp} autoFocus />
            {error && <p className="text-sm text-red-400">{error}</p>}
            <button className="btn btn-primary w-full" disabled={busy || otp.length !== 4}>{busy && <Spinner size={14} />}Verify and save</button>
            <button type="button" className="w-full text-sm font-semibold text-brand-soft disabled:text-muted" disabled={left > 0 || busy} onClick={() => void send()}>
              {left > 0 ? `Resend code in ${left}s` : "Resend code"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
