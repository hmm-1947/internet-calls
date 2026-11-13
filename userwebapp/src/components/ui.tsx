import { useEffect, useState, type ReactNode, type InputHTMLAttributes } from "react";
import { mediaUrl } from "../lib/config";
import { cx } from "../lib/util";
import type { BadgeTag } from "../lib/types";
import { IconBack, IconClose, IconCoin, IconEye, IconEyeOff, IconStar, IconUser } from "./icons";

export function Spinner({ size = 18, className = "" }: { size?: number; className?: string }) {
  return (
    <span
      className={cx("inline-block animate-spin rounded-full border-2 border-black/20 border-t-white", className)}
      style={{ width: size, height: size }}
    />
  );
}

export function PageLoader() {
  return (
    <div className="flex h-full min-h-[40vh] items-center justify-center">
      <Spinner size={28} />
    </div>
  );
}

export function Avatar({
  src, name, size = 48, className = "", ring = false,
}: { src?: string | null; name?: string; size?: number; className?: string; ring?: boolean }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [src]);
  const url = src && !failed ? mediaUrl(src) : "";
  return (
    <div
      className={cx("relative shrink-0 overflow-hidden rounded-full bg-card2 text-ink/60", ring && "ring-2 ring-brand-soft", className)}
      style={{ width: size, height: size }}
    >
      {url ? (
        <img src={url} alt={name || ""} className="h-full w-full object-cover" onError={() => setFailed(true)} loading="lazy" />
      ) : (
        <div className="flex h-full w-full items-center justify-center">
          <IconUser size={Math.round(size * 0.5)} />
        </div>
      )}
    </div>
  );
}

export function PresenceDot({ online, busy, className = "" }: { online: boolean; busy?: boolean; className?: string }) {
  return (
    <span
      className={cx(
        "inline-block h-3 w-3 rounded-full border-2 border-bg",
        busy ? "bg-gold" : online ? "bg-online" : "bg-neutral-400",
        className,
      )}
    />
  );
}

export function BadgePill({ tag }: { tag?: BadgeTag | null }) {
  if (!tag) return null;
  return (
    <span
      className="inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-ink"
      style={{ background: tag.color || "#0E8F3C" }}
    >
      {tag.name}
    </span>
  );
}

export function Stars({ value, count, size = 14 }: { value: number | null; count?: number; size?: number }) {
  if (value === null || value === undefined) return <span className="text-xs text-muted">New</span>;
  return (
    <span className="inline-flex items-center gap-1 text-xs text-ink/80">
      <IconStar size={size} className="text-gold" />
      {value.toFixed(1)}
      {count !== undefined && <span className="text-muted">({count})</span>}
    </span>
  );
}

export function CoinChip({ coins, onClick, className = "" }: { coins: number | null | undefined; onClick?: () => void; className?: string }) {
  return (
    <button
      onClick={onClick}
      className={cx("inline-flex items-center gap-1.5 rounded-full border border-gold/30 bg-gold/10 px-3 py-1.5 text-sm font-semibold text-gold transition hover:bg-gold/20", className)}
    >
      <IconCoin size={16} />
      {coins ?? "—"}
    </button>
  );
}

export function Switch({ checked, onChange, disabled }: { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cx(
        "relative h-6 w-11 shrink-0 rounded-full transition disabled:opacity-40",
        checked ? "bg-brand-soft" : "bg-black/15",
      )}
    >
      <span className={cx("absolute top-0.5 h-5 w-5 rounded-full bg-white transition-all", checked ? "left-[22px]" : "left-0.5")} />
    </button>
  );
}

export function Modal({
  open, onClose, title, children, sheet = false, width = "max-w-md",
}: { open: boolean; onClose: () => void; title?: string; children: ReactNode; sheet?: boolean; width?: string }) {
  useEffect(() => {
    if (!open) return;
    const h = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div
      className={cx("fixed inset-0 z-50 flex bg-black/40 backdrop-blur-sm", sheet ? "items-end justify-center sm:items-center" : "items-center justify-center", "p-0 sm:p-4")}
      onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        className={cx(
          "slide-up w-full overflow-hidden border border-line bg-card2 shadow-2xl",
          width,
          sheet ? "max-h-[88vh] rounded-t-3xl sm:rounded-3xl" : "mx-4 max-h-[90vh] rounded-3xl",
        )}
      >
        {title !== undefined && (
          <div className="flex items-center justify-between px-5 pb-2 pt-5">
            <h3 className="text-lg font-bold">{title}</h3>
            <button onClick={onClose} className="rounded-full p-1.5 text-brand-soft hover:bg-black/10" aria-label="Close">
              <IconClose size={20} />
            </button>
          </div>
        )}
        <div className="max-h-[78vh] overflow-y-auto px-5 pb-5 pt-2">{children}</div>
      </div>
    </div>
  );
}

export function Confirm({
  open, title, message, confirmLabel = "Confirm", danger, busy, onConfirm, onCancel,
}: {
  open: boolean; title: string; message: ReactNode; confirmLabel?: string; danger?: boolean; busy?: boolean;
  onConfirm: () => void; onCancel: () => void;
}) {
  return (
    <Modal open={open} onClose={onCancel} title={title}>
      <div className="text-sm leading-relaxed text-ink/70">{message}</div>
      <div className="mt-5 flex justify-end gap-2">
        <button className="btn btn-ghost" onClick={onCancel} disabled={busy}>Cancel</button>
        <button className={cx("btn", danger ? "btn-danger" : "btn-primary")} onClick={onConfirm} disabled={busy}>
          {busy && <Spinner size={14} />}
          {confirmLabel}
        </button>
      </div>
    </Modal>
  );
}

export function Notice({ open, title, message, onClose }: { open: boolean; title: string; message: ReactNode; onClose: () => void }) {
  return (
    <Modal open={open} onClose={onClose} title={title}>
      <div className="text-sm leading-relaxed text-ink/70">{message}</div>
      <div className="mt-5 flex justify-end">
        <button className="btn btn-primary" onClick={onClose}>OK</button>
      </div>
    </Modal>
  );
}

export function Field({
  label, error, hint, right, ...p
}: { label?: string; error?: string | null; hint?: string; right?: ReactNode } & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <div>
      {label && <label className="label">{label}</label>}
      <div className="relative">
        <input {...p} className={cx("input", error && "!border-red-500/70", right ? "pr-12" : "", p.className)} />
        {right && <div className="absolute inset-y-0 right-3 flex items-center">{right}</div>}
      </div>
      {error ? <p className="mt-1.5 text-xs text-red-400">{error}</p> : hint ? <p className="mt-1.5 text-xs text-muted">{hint}</p> : null}
    </div>
  );
}

export function PasswordField({ label, error, ...p }: { label?: string; error?: string | null } & InputHTMLAttributes<HTMLInputElement>) {
  const [show, setShow] = useState(false);
  return (
    <Field
      label={label}
      error={error}
      {...p}
      type={show ? "text" : "password"}
      right={
        <button type="button" onClick={() => setShow((s) => !s)} className="text-ink/40 hover:text-ink" tabIndex={-1} aria-label="Toggle password visibility">
          {show ? <IconEyeOff size={18} /> : <IconEye size={18} />}
        </button>
      }
    />
  );
}

export function PhoneField({ label = "Phone number", error, value, onChange, ...p }: { label?: string; error?: string | null; value: string; onChange: (v: string) => void } & Omit<InputHTMLAttributes<HTMLInputElement>, "onChange" | "value">) {
  return (
    <div>
      <label className="label">{label}</label>
      <div className={cx("flex overflow-hidden rounded-xl border border-black/10 bg-card2 transition focus-within:border-brand-soft", error && "!border-red-500/70")}>
        <span className="flex items-center border-r border-black/10 px-3 text-sm text-ink/60">+91</span>
        <input
          {...p}
          inputMode="numeric"
          value={value}
          onChange={(e) => onChange(e.target.value.replace(/[^\d+\s]/g, ""))}
          className="w-full bg-transparent px-3 py-3 text-sm text-ink placeholder-black/30 outline-none"
          placeholder="10-digit mobile number"
        />
      </div>
      {error && <p className="mt-1.5 text-xs text-red-400">{error}</p>}
    </div>
  );
}

export function OtpInput({ value, onChange, length = 4, autoFocus }: { value: string; onChange: (v: string) => void; length?: number; autoFocus?: boolean }) {
  return (
    <input
      autoFocus={autoFocus}
      inputMode="numeric"
      autoComplete="one-time-code"
      maxLength={length}
      value={value}
      onChange={(e) => onChange(e.target.value.replace(/\D/g, "").slice(0, length))}
      className="input text-center text-2xl font-bold tracking-[0.6em]"
      placeholder={"•".repeat(length)}
    />
  );
}

export function useCountdown(initial = 0) {
  const [left, setLeft] = useState(initial);
  useEffect(() => {
    if (left <= 0) return;
    const t = window.setTimeout(() => setLeft((l) => l - 1), 1000);
    return () => window.clearTimeout(t);
  }, [left]);
  return [left, setLeft] as const;
}

export function PageHeader({ title, onBack, right }: { title: string; onBack?: () => void; right?: ReactNode }) {
  return (
    <div className="sticky top-0 z-20 flex items-center gap-2 border-b border-line bg-bg/90 px-3 py-3 backdrop-blur safe-t md:px-6">
      {onBack && (
        <button onClick={onBack} className="rounded-full p-2 hover:bg-black/10" aria-label="Back">
          <IconBack size={22} />
        </button>
      )}
      <h1 className="flex-1 truncate text-lg font-bold">{title}</h1>
      {right}
    </div>
  );
}

export function Empty({ icon, title, text, action }: { icon?: ReactNode; title: string; text?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-16 text-center">
      {icon && <div className="mb-4 text-ink/25">{icon}</div>}
      <h3 className="text-base font-semibold">{title}</h3>
      {text && <p className="mt-1 max-w-sm text-sm text-muted">{text}</p>}
      {action && <div className="mt-5">{action}</div>}
    </div>
  );
}

export function AuthLayout({ title, subtitle, children, onBack }: { title: string; subtitle?: string; children: ReactNode; onBack?: () => void }) {
  return (
    <div className="flex min-h-full items-center justify-center bg-[radial-gradient(ellipse_at_top,rgba(18,160,68,0.18),transparent_60%)] px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-6 flex flex-col items-center text-center">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="MindiCo" className="mb-4 h-14 w-14 rounded-2xl object-cover" />
        </div>
        <div className="card2 p-6 shadow-2xl sm:p-8">
          {onBack && (
            <button onClick={onBack} className="-ml-1 mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
              <IconBack size={16} /> Back
            </button>
          )}
          <h1 className="text-2xl font-bold">{title}</h1>
          {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
          <div className="mt-6 space-y-4">{children}</div>
        </div>
      </div>
    </div>
  );
}

export function PasswordChecklist({ value }: { value: string }) {
  const rules = [
    { label: "At least 8 characters", ok: value.length >= 8 },
    { label: "At least one alphabet", ok: /[A-Za-z]/.test(value) },
    { label: "At least one number", ok: /[0-9]/.test(value) },
    { label: "At least one special character", ok: /[^A-Za-z0-9]/.test(value) },
  ];
  return (
    <ul className="space-y-1">
      {rules.map((r) => (
        <li key={r.label} className={cx("flex items-center gap-2 text-xs", r.ok ? "text-online" : "text-muted")}>
          <span className={cx("inline-block h-1.5 w-1.5 rounded-full", r.ok ? "bg-online" : "bg-black/25")} />
          {r.label}
        </li>
      ))}
    </ul>
  );
}

export function GoogleButton({ onClick, busy }: { onClick: () => void; busy?: boolean }) {
  return (
    <button type="button" onClick={onClick} disabled={busy} className="btn w-full border border-black/15 bg-white text-neutral-900 hover:bg-neutral-100">
      {busy ? <Spinner size={16} className="!border-neutral-300 !border-t-neutral-800" /> : (
        <svg width="18" height="18" viewBox="0 0 48 48">
          <path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.5 5.4 2.6 13.2l7.9 6.1C12.4 13.5 17.7 9.5 24 9.5z" />
          <path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 3-2.3 5.5-4.8 7.2l7.5 5.8c4.4-4.1 7.1-10.1 7.1-17.5z" />
          <path fill="#FBBC05" d="M10.5 28.7A14.5 14.5 0 0 1 9.5 24c0-1.6.3-3.2.9-4.7l-7.9-6.1A24 24 0 0 0 0 24c0 3.9.9 7.5 2.6 10.8l7.9-6.1z" />
          <path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.5-5.8c-2.1 1.4-4.9 2.3-8.4 2.3-6.3 0-11.6-4-13.5-9.8l-7.9 6.1C6.5 42.6 14.6 48 24 48z" />
        </svg>
      )}
      Continue with Google
    </button>
  );
}
