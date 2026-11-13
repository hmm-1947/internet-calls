import { useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { useApp } from "../state/app";
import { Avatar, Confirm, Modal, Notice, Spinner, Switch } from "../components/ui";
import { IconChevron, IconDoc, IconEdit, IconHeadset, IconLock, IconLogout, IconShield, IconTrash, IconPhone, IconVideo } from "../components/icons";

function Label({ children }: { children: ReactNode }) {
  return <div className="px-1 pb-2 pt-6 text-xs font-semibold uppercase tracking-widest text-ink/50">{children}</div>;
}

function Row({
  icon, title, onClick, busy, trailing, danger,
}: { icon: ReactNode; title: string; onClick?: () => void; busy?: boolean; trailing?: ReactNode; danger?: boolean }) {
  return (
    <div
      role={onClick ? "button" : undefined}
      onClick={busy ? undefined : onClick}
      className={`flex items-center gap-3.5 border-b border-line px-4 py-3.5 last:border-b-0 ${onClick ? "cursor-pointer hover:bg-black/5" : ""}`}
    >
      <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${danger ? "bg-red-500/15 text-red-500" : "bg-brand/15 text-brand"}`}>{icon}</div>
      <div className={`flex-1 text-[15px] ${danger ? "font-semibold text-red-500" : ""}`}>{title}</div>
      {busy ? <Spinner size={16} /> : trailing ?? (onClick && !danger ? <IconChevron size={18} className="text-ink/35" /> : null)}
    </div>
  );
}

export default function Settings() {
  const nav = useNavigate();
  const { me, logout, refreshMe, toast } = useApp();
  const [savingVideo, setSavingVideo] = useState(false);
  const [wa, setWa] = useState<"enroll" | "support" | null>(null);
  const [notice, setNotice] = useState<{ title: string; message: string } | null>(null);
  const [pwNotice, setPwNotice] = useState(false);
  const [delOpen, setDelOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [logoutOpen, setLogoutOpen] = useState(false);
  const [loggingOut, setLoggingOut] = useState(false);

  const videoDisabled = !!me?.video_call_disabled_by_admin;
  const videoOn = videoDisabled ? false : me?.video_call_enabled ?? true;

  const toggleVideo = async (v: boolean) => {
    if (savingVideo || videoDisabled) return;
    setSavingVideo(true);
    try {
      await api.videoSetting(v);
      await refreshMe();
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setSavingVideo(false);
    }
  };

  const openWhatsapp = async (kind: "enroll" | "support") => {
    if (wa) return;
    setWa(kind);
    try {
      const r = await api.enrollContact();
      const number = (r.whatsapp_number || "").replace(/\D/g, "");
      if (!number) {
        setNotice({
          title: "Not available yet",
          message: kind === "enroll" ? "Listener enrollment is not set up yet. Please try again later." : "Support contact is not set up yet. Please try again later.",
        });
        return;
      }
      const who = [me?.name?.trim(), me?.phone?.trim()].filter(Boolean).join(", ");
      const text =
        kind === "enroll"
          ? `Hi, I would like to enroll as a listener on the app.${who ? ` My account details: ${who}.` : ""} Please let me know the next steps.`
          : `Hi, I need help and support with the app.${who ? ` My account details: ${who}.` : ""}`;
      const url = `https://wa.me/${number}?text=${encodeURIComponent(text)}`;
      const w = window.open(url, "_blank", "noopener,noreferrer");
      if (!w) window.location.href = url;
    } catch (e) {
      setNotice({ title: "Could not open WhatsApp", message: friendly(e, "Something went wrong. Please check your connection and try again.") });
    } finally {
      setWa(null);
    }
  };

  const changePassword = () => {
    if (me?.is_google_account) setPwNotice(true);
    else nav("/settings/password");
  };

  const doDelete = async () => {
    setDeleting(true);
    try {
      await api.deleteAccount(reason);
      setDelOpen(false);
      setReason("");
      setNotice({ title: "Deletion requested", message: "The admins have been notified about your account deletion. Your account will be removed once they process the request." });
    } catch {
      toast("Could not send your deletion request. Please try again.", "error");
    } finally {
      setDeleting(false);
    }
  };

  const doLogout = async () => {
    setLoggingOut(true);
    await logout();
  };

  return (
    <div className="mx-auto w-full max-w-2xl px-4 pb-12 pt-6 md:px-8 md:pt-8">
      <div className="flex flex-col items-center text-center">
        <Avatar src={me?.photo_url} name={me?.name} size={96} ring />
        <h1 className="mt-3 text-lg font-bold">{me?.name ?? "…"}</h1>
        <p className="text-sm text-muted">{me?.phone ?? me?.email ?? ""}</p>
      </div>

      <Label>Account</Label>
      <div className="card2 overflow-hidden">
        <Row icon={<IconHeadset size={18} />} title="Enroll as a listener" onClick={() => void openWhatsapp("enroll")} busy={wa === "enroll"} />
        <Row icon={<IconEdit size={18} />} title="Edit profile" onClick={() => nav("/settings/profile")} />
        <Row icon={<IconPhone size={18} />} title="Phone number and email" onClick={() => nav("/settings/contact")} />
        <Row icon={<IconLock size={18} />} title="Change password" onClick={changePassword} />
      </div>

      <Label>Preferences</Label>
      <div className="card2 overflow-hidden">
        <Row
          icon={<IconVideo size={18} />}
          title={videoDisabled ? "Video calls (disabled by admin)" : "Video calls"}
          trailing={<Switch checked={videoOn} disabled={videoDisabled || savingVideo} onChange={(v) => void toggleVideo(v)} />}
        />
      </div>

      <Label>Support</Label>
      <div className="card2 overflow-hidden">
        <Row icon={<IconHeadset size={18} />} title="Help and support" onClick={() => void openWhatsapp("support")} busy={wa === "support"} />
        <Row icon={<IconDoc size={18} />} title="Terms of service" onClick={() => nav("/legal/terms")} />
        <Row icon={<IconShield size={18} />} title="Privacy policy" onClick={() => nav("/legal/privacy")} />
      </div>

      <div className="card2 mt-6 overflow-hidden">
        <Row icon={<IconTrash size={18} />} title="Delete account" danger onClick={() => setDelOpen(true)} />
        <Row icon={<IconLogout size={18} />} title="Logout" danger onClick={() => setLogoutOpen(true)} />
      </div>

      <Notice open={!!notice} title={notice?.title ?? ""} message={notice?.message} onClose={() => setNotice(null)} />
      <Notice
        open={pwNotice}
        title="No password on this account"
        message="You signed in with Google, so this account does not have a password to change. Manage it from your Google account instead."
        onClose={() => setPwNotice(false)}
      />
      <Confirm open={logoutOpen} title="Log out?" message="You will need to sign in again to use MindiCo." confirmLabel="Logout" danger busy={loggingOut} onConfirm={() => void doLogout()} onCancel={() => setLogoutOpen(false)} />
      <Modal open={delOpen} onClose={() => (deleting ? undefined : setDelOpen(false))} title="Delete account">
        <p className="text-sm leading-relaxed text-ink/70">
          Are you sure you want to delete your account? The admins will be notified about your account deletion and will process it. This cannot be undone once it is done.
        </p>
        <textarea value={reason} onChange={(e) => setReason(e.target.value.slice(0, 300))} rows={3} placeholder="Reason (optional)" className="input mt-4 resize-none" />
        <div className="mt-5 flex justify-end gap-2">
          <button className="btn btn-ghost" onClick={() => setDelOpen(false)} disabled={deleting}>Cancel</button>
          <button className="btn btn-danger" onClick={() => void doDelete()} disabled={deleting}>{deleting && <Spinner size={14} />}Delete account</button>
        </div>
      </Modal>
    </div>
  );
}
