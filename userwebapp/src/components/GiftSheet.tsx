import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly, InsufficientCoinsError } from "../lib/api";
import { mediaUrl } from "../lib/config";
import type { Gift } from "../lib/types";
import { useApp } from "../state/app";
import { IconCoin, IconGift } from "./icons";
import { Confirm, Modal, Spinner } from "./ui";

export function GiftIcon({ icon, size = 44 }: { icon: string | null | undefined; size?: number }) {
  const [failed, setFailed] = useState(false);
  if (icon && (icon.startsWith("/") || icon.startsWith("http")) && !failed) {
    return (
      <img src={mediaUrl(icon)} alt="" width={size} height={size} className="rounded-2xl object-cover" style={{ width: size, height: size }} onError={() => setFailed(true)} />
    );
  }
  return <IconGift size={size * 0.8} className="text-brand-soft" />;
}

export function GiftSheet({
  open, onClose, listenerId, callId, zIndex, onTopUp,
}: { open: boolean; onClose: () => void; listenerId: number; callId?: number | null; zIndex?: number; onTopUp?: () => void }) {
  const { me, refreshMe, toast, refreshThreads } = useApp();
  const nav = useNavigate();
  const [gifts, setGifts] = useState<Gift[]>([]);
  const [loading, setLoading] = useState(true);
  const [pick, setPick] = useState<Gift | null>(null);
  const [sending, setSending] = useState(false);
  const [balance, setBalance] = useState<number | null>(null);

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    void refreshMe();
    api.gifts().then(setGifts).catch((e) => toast(friendly(e), "error")).finally(() => setLoading(false));
  }, [open]);

  const coins = balance ?? me?.coins ?? 0;
  useEffect(() => { if (me) setBalance(me.coins); }, [me?.coins]);

  const topUp = () => {
    onClose();
    onTopUp?.();
    nav("/upgrade");
  };

  const choose = (g: Gift) => {
    if (coins < g.coins) { topUp(); return; }
    setPick(g);
  };

  const send = async () => {
    if (!pick || sending) return;
    setSending(true);
    try {
      const r = await api.sendGift(listenerId, pick.id, callId ?? undefined);
      const left = typeof r.coins === "number" ? r.coins : null;
      if (left !== null) setBalance(left);
      toast(`You sent ${(r.gift_name as string) || pick.name}`, "success");
      setPick(null);
      onClose();
      void refreshMe();
      void refreshThreads();
    } catch (e) {
      setPick(null);
      if (e instanceof InsufficientCoinsError) topUp();
      else toast(friendly(e), "error");
    } finally {
      setSending(false);
    }
  };

  return (
    <div style={{ position: "relative", zIndex: zIndex ?? 60 }}>
      <Modal open={open && !pick} onClose={onClose} title="Send a Gift" sheet width="max-w-lg">
        {loading ? (
          <div className="flex justify-center py-10"><Spinner size={26} /></div>
        ) : gifts.length === 0 ? (
          <p className="py-8 text-center text-sm text-muted">No gifts available right now.</p>
        ) : (
          <div className="grid grid-cols-3 gap-3">
            {gifts.map((g) => (
              <button key={g.id} onClick={() => choose(g)} className="group flex flex-col items-center rounded-2xl bg-card2 p-3 text-center transition hover:bg-[#262c3a]">
                <div className="flex h-16 items-center justify-center"><GiftIcon icon={g.icon} /></div>
                <div className="mt-2 w-full truncate text-xs">{g.name}</div>
                <div className="mt-1 flex items-center gap-1 text-xs text-ink/70"><IconCoin size={13} className="text-gold" />{g.coins}</div>
                <div className="mt-2 w-full rounded-lg bg-brand-soft py-1.5 text-[11px] font-bold group-hover:bg-brand">SEND</div>
              </button>
            ))}
          </div>
        )}
        <div className="mt-5 flex items-center justify-between border-t border-line pt-4">
          <div>
            <div className="text-xs text-ink/50">Balance</div>
            <div className="mt-0.5 flex items-center gap-1.5 font-bold"><IconCoin size={18} className="text-gold" />{coins} Coins</div>
          </div>
          <button className="btn btn-gold !rounded-full" onClick={topUp}>Top up</button>
        </div>
      </Modal>
      <Confirm
        open={!!pick}
        title="Send Gift?"
        message={pick ? `Send ${pick.name} for ${pick.coins} coins?` : ""}
        confirmLabel="Send"
        busy={sending}
        onConfirm={send}
        onCancel={() => setPick(null)}
      />
    </div>
  );
}
