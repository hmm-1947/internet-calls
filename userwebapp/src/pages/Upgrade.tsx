import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { mediaUrl } from "../lib/config";
import { payForPlan } from "../lib/razorpay";
import { listTimeLabel, cx } from "../lib/util";
import type { Plan, Purchase } from "../lib/types";
import { useApp } from "../state/app";
import { Empty, Modal, PageHeader, PageLoader, Spinner } from "../components/ui";
import { IconCoin } from "../components/icons";

function PlanIcon({ icon }: { icon: string }) {
  const [failed, setFailed] = useState(false);
  if (icon && (icon.startsWith("/") || icon.startsWith("http")) && !failed) {
    return <img src={mediaUrl(icon)} alt="" className="h-12 w-12 rounded-xl object-cover" onError={() => setFailed(true)} />;
  }
  return <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gold/15 text-gold"><IconCoin size={28} /></div>;
}

export default function Upgrade() {
  const nav = useNavigate();
  const { me, refreshMe, toast } = useApp();
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [banner, setBanner] = useState<string | null>(null);
  const [paying, setPaying] = useState<number | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [history, setHistory] = useState<Purchase[] | null>(null);
  const [success, setSuccess] = useState<{ coins: number } | null>(null);

  const load = () => {
    setError(null);
    api.plans().then(setPlans).catch((e) => setError(friendly(e)));
  };

  useEffect(() => {
    load();
    api.upgradeBanner().then((b) => setBanner(b.upgrade_banner_url)).catch(() => undefined);
    void refreshMe();
  }, []);

  const buy = async (p: Plan) => {
    if (paying !== null) return;
    setPaying(p.id);
    try {
      const r = await payForPlan(p);
      if (r.status === "success") {
        setSuccess({ coins: r.coins });
        void refreshMe();
      } else if (r.status === "failed") {
        toast(r.message, "error");
      }
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setPaying(null);
    }
  };

  const openHistory = () => {
    setHistoryOpen(true);
    setHistory(null);
    api.myPurchases().then(setHistory).catch((e) => { toast(friendly(e), "error"); setHistory([]); });
  };

  return (
    <div>
      <PageHeader
        title="Buy coins"
        onBack={() => nav(-1)}
        right={<button onClick={openHistory} className="rounded-full px-3 py-1.5 text-sm font-semibold text-brand-soft hover:bg-white/10">History</button>}
      />
      <div className="mx-auto w-full max-w-5xl px-4 pb-10 pt-5 md:px-8 md:pt-8">
        <div className="mb-6 flex items-center justify-between rounded-2xl border border-gold/25 bg-gold/10 px-5 py-4">
          <div>
            <div className="text-xs uppercase tracking-wide text-gold/80">Your balance</div>
            <div className="mt-0.5 inline-flex items-center gap-2 text-3xl font-extrabold text-gold"><IconCoin size={28} />{me?.coins ?? "â€”"}</div>
          </div>
          <p className="hidden max-w-xs text-right text-sm text-white/60 sm:block">Coins are used for calls, chats and gifts.</p>
        </div>

        {banner && <img src={mediaUrl(banner)} alt="" className="mb-6 w-full rounded-2xl object-cover" />}

        {error && !plans ? (
          <Empty title="Could not load plans" text={error} action={<button className="btn btn-primary" onClick={load}>Try again</button>} />
        ) : !plans ? (
          <PageLoader />
        ) : plans.length === 0 ? (
          <Empty title="No plans available" text="Please check back soon." />
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {plans.map((p) => (
              <div key={p.id} className={cx("card relative flex flex-col gap-4 p-5", p.is_featured && "!border-gold/60 shadow-[0_0_0_1px_rgba(255,201,74,0.25)]")}>
                {p.is_featured && <span className="absolute right-4 top-4 rounded-full bg-gold px-2.5 py-0.5 text-[10px] font-extrabold uppercase text-black">Best value</span>}
                <PlanIcon icon={p.icon} />
                <div>
                  <div className="text-sm text-muted">{p.name}</div>
                  <div className="mt-1 inline-flex items-center gap-2 text-2xl font-extrabold text-gold"><IconCoin size={22} />{p.coins}</div>
                </div>
                <button className="btn btn-primary mt-auto w-full" disabled={paying !== null} onClick={() => void buy(p)}>
                  {paying === p.id ? <Spinner size={14} /> : null}
                  Pay â‚¹{p.price}
                </button>
              </div>
            ))}
          </div>
        )}
        <p className="mt-6 text-center text-xs text-muted">Payments are processed securely by Razorpay.</p>
      </div>

      <Modal open={historyOpen} onClose={() => setHistoryOpen(false)} title="Purchase history" sheet>
        {history === null ? (
          <PageLoader />
        ) : history.length === 0 ? (
          <Empty title="No purchases yet" />
        ) : (
          <div className="divide-y divide-line">
            {history.map((h) => (
              <div key={h.id} className="flex items-center justify-between py-3">
                <div>
                  <div className="text-sm font-semibold">{h.plan_name}</div>
                  <div className="text-xs text-muted">{listTimeLabel(h.created_at)} Â· â‚¹{h.price_paid}</div>
                </div>
                <div className="text-right">
                  <div className="inline-flex items-center gap-1 text-sm font-bold text-gold"><IconCoin size={14} />{h.coins_purchased}</div>
                  <div className={cx("text-[11px] capitalize", h.status === "completed" || h.status === "paid" || h.status === "success" ? "text-online" : h.status === "failed" ? "text-red-400" : "text-muted")}>{h.status}</div>
                </div>
              </div>
            ))}
          </div>
        )}
      </Modal>

      <Modal open={!!success} onClose={() => setSuccess(null)} title="Payment successful">
        <div className="flex flex-col items-center py-2 text-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-online/15 text-online"><IconCoin size={36} /></div>
          <p className="mt-4 text-sm text-white/70">Your new balance</p>
          <div className="mt-1 inline-flex items-center gap-2 text-3xl font-extrabold text-gold"><IconCoin size={26} />{success?.coins}</div>
          <button className="btn btn-primary mt-6 w-full" onClick={() => { setSuccess(null); nav("/"); }}>Start talking</button>
        </div>
      </Modal>
    </div>
  );
}
