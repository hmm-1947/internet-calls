import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { passwordValid } from "../lib/util";
import { useApp } from "../state/app";
import { PageHeader, PasswordChecklist, PasswordField, Spinner } from "../components/ui";

export default function ChangePassword() {
  const nav = useNavigate();
  const { toast } = useApp();
  const [step, setStep] = useState<1 | 2>(1);
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const verify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!current) { setError("Enter your current password"); return; }
    setBusy(true);
    setError(null);
    try {
      await api.verifyPassword(current);
      setStep(2);
    } catch (err) {
      setError(friendly(err, "Current password is incorrect"));
    } finally {
      setBusy(false);
    }
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!passwordValid(next)) { setError("Your new password does not meet all the requirements"); return; }
    if (next !== confirm) { setError("Passwords do not match"); return; }
    if (next === current) { setError("New password must be different from your current password"); return; }
    setBusy(true);
    setError(null);
    try {
      await api.changePassword(current, next);
      toast("Password changed", "success");
      nav("/settings", { replace: true });
    } catch (err) {
      setError(friendly(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <PageHeader title="Change password" onBack={() => (step === 2 ? setStep(1) : nav("/settings"))} />
      <div className="mx-auto w-full max-w-md px-4 pb-12 pt-8">
        {step === 1 ? (
          <form onSubmit={verify} className="space-y-5">
            <p className="text-sm text-muted">Enter your current password to continue.</p>
            <PasswordField label="Current password" value={current} onChange={(e) => setCurrent(e.target.value)} autoFocus autoComplete="current-password" />
            {error && <p className="text-sm text-red-400">{error}</p>}
            <button className="btn btn-primary w-full" disabled={busy || !current}>{busy && <Spinner size={14} />}Continue</button>
          </form>
        ) : (
          <form onSubmit={submit} className="space-y-5">
            <PasswordField label="New password" value={next} onChange={(e) => setNext(e.target.value)} autoFocus autoComplete="new-password" />
            <PasswordChecklist value={next} />
            <PasswordField label="Confirm new password" value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="new-password" error={confirm && next !== confirm ? "Passwords do not match" : null} />
            {error && <p className="text-sm text-red-400">{error}</p>}
            <button className="btn btn-primary w-full" disabled={busy || !passwordValid(next) || next !== confirm}>{busy && <Spinner size={14} />}Update password</button>
          </form>
        )}
      </div>
    </div>
  );
}
