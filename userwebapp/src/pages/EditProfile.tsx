import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { useUsernameCheck } from "../lib/hooks";
import { displayNameError, humanWait, squareCropJpeg, usernameError } from "../lib/util";
import { useApp } from "../state/app";
import { Avatar, Field, PageHeader, PageLoader, Spinner } from "../components/ui";
import { IconCamera, IconLock } from "../components/icons";

export default function EditProfile() {
  const nav = useNavigate();
  const { me, refreshMe, toast } = useApp();
  const [name, setName] = useState("");
  const [username, setUsername] = useState("");
  const [bio, setBio] = useState("");
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [unlockAt, setUnlockAt] = useState<number | null>(null);
  const [, tick] = useState(0);
  const loaded = useRef(false);
  const file = useRef<HTMLInputElement>(null);

  useEffect(() => { void refreshMe(); }, []);

  useEffect(() => {
    if (!me || loaded.current) return;
    loaded.current = true;
    setName(me.name ?? "");
    setUsername(me.username ?? "");
    setBio(me.bio ?? "");
  }, [me]);

  useEffect(() => {
    if (!me) return;
    setUnlockAt(me.username_cooldown_seconds > 0 ? Date.now() + me.username_cooldown_seconds * 1000 : null);
  }, [me?.username_cooldown_seconds]);

  useEffect(() => {
    const t = window.setInterval(() => tick((n) => n + 1), 30000);
    return () => window.clearInterval(t);
  }, []);

  const own = me?.username ?? null;
  const nameChanged = !!me && name.trim() !== (me.name ?? "");
  const userChanged = !!me && username.trim().toLowerCase() !== (own ?? "").toLowerCase();
  const bioChanged = !!me && bio.trim() !== (me.bio ?? "");
  const uCheck = useUsernameCheck(userChanged ? username : "", own);
  const locked = unlockAt !== null && unlockAt > Date.now();
  const waitText = locked ? humanWait(Math.ceil((unlockAt! - Date.now()) / 1000)) : "";

  if (!me) return <PageLoader />;

  const pickPhoto = async (f: File | undefined) => {
    if (!f) return;
    if (!f.type.startsWith("image/")) { toast("Please choose an image file", "error"); return; }
    setUploading(true);
    try {
      const blob = await squareCropJpeg(f);
      await api.updatePhoto(blob);
      await refreshMe();
      toast("Photo updated", "success");
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setUploading(false);
      if (file.current) file.current.value = "";
    }
  };

  const save = async () => {
    if (!nameChanged && !userChanged && !bioChanged) { toast("No changes to save"); return; }
    const err =
      (nameChanged ? displayNameError(name) : null) ??
      (userChanged ? usernameError(username) : null) ??
      (userChanged && uCheck.status === "bad" ? uCheck.message : null);
    if (err) { toast(err, "error"); return; }
    if (userChanged && locked) { toast(`You can change your username again in ${waitText}`, "error"); return; }
    setSaving(true);
    try {
      await api.updateProfile({
        ...(nameChanged ? { display_name: name.trim() } : {}),
        ...(userChanged ? { username: username.trim() } : {}),
        ...(bioChanged ? { bio: bio.trim() } : {}),
      });
      loaded.current = false;
      await refreshMe();
      toast("Changes saved", "success");
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setSaving(false);
    }
  };

  const userHint =
    locked ? `Username can only be changed once every 24 hours. You can change it again in ${waitText}.`
    : uCheck.status === "checking" ? "Checking availability…"
    : uCheck.status === "ok" && userChanged ? `${username.trim()} is available`
    : uCheck.status === "bad" ? uCheck.message ?? undefined
    : "Can only be changed once every 24 hours";

  return (
    <div>
      <PageHeader title="Edit profile" onBack={() => nav("/settings")} />
      <div className="mx-auto w-full max-w-xl px-4 pb-12 pt-6 md:px-8">
        <div className="flex justify-center">
          <button onClick={() => file.current?.click()} disabled={uploading} className="group relative rounded-full" aria-label="Change photo">
            <Avatar src={me.photo_url} name={me.name} size={112} ring />
            <span className="absolute inset-0 flex items-center justify-center rounded-full bg-black/50 opacity-0 transition group-hover:opacity-100">
              {uploading ? <Spinner size={22} /> : <IconCamera size={26} />}
            </span>
            <span className="absolute bottom-0 right-0 flex h-9 w-9 items-center justify-center rounded-full border-2 border-bg bg-brand-soft">
              {uploading ? <Spinner size={14} /> : <IconCamera size={16} />}
            </span>
          </button>
          <input ref={file} type="file" accept="image/*" hidden onChange={(e) => void pickPhoto(e.target.files?.[0])} />
        </div>

        <div className="mt-8 space-y-5">
          <Field
            label="Display name"
            value={name}
            maxLength={30}
            onChange={(e) => setName(e.target.value)}
            error={nameChanged ? displayNameError(name) : null}
          />
          <Field
            label="Username"
            value={username}
            readOnly={locked}
            maxLength={20}
            onChange={(e) => setUsername(e.target.value.replace(/\s/g, ""))}
            right={locked ? <IconLock size={16} className="text-gold" /> : undefined}
            error={uCheck.status === "bad" ? uCheck.message : null}
            hint={uCheck.status === "bad" ? undefined : userHint}
          />
          <div>
            <label className="label">Bio</label>
            <textarea value={bio} onChange={(e) => setBio(e.target.value.slice(0, 2000))} rows={4} placeholder="Tell listeners a little about yourself" className="input resize-none" />
          </div>
          <div>
            <label className="label">Phone number</label>
            <div className="flex items-center gap-3 rounded-xl border border-white/10 bg-card2 px-4 py-3 text-sm">
              <span className="flex-1 text-white/80">{me.phone ? `+91 ${me.phone}` : "Not added"}</span>
              <button type="button" onClick={() => nav("/settings/contact")} className="font-semibold text-brand-soft hover:text-white">{me.phone ? "Change" : "Add"}</button>
            </div>
          </div>
          {me.email && (
            <Field label="Email" value={me.email} readOnly className="opacity-70" hint={me.is_google_account ? "Linked to your Google account" : undefined} />
          )}
        </div>

        <button className="btn btn-primary mt-8 w-full" disabled={saving || (!nameChanged && !userChanged && !bioChanged)} onClick={() => void save()}>
          {saving && <Spinner size={14} />} Save changes
        </button>
      </div>
    </div>
  );
}
