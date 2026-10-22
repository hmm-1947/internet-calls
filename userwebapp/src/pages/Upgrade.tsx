import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { mediaUrl } from "../lib/config";
import { payForPlan } from "../lib/razorpay";
import { listTimeLabel, cx } from "../lib/util";
import type { Plan, Purchase } from "../lib/types";
import { useApp } from "../state/app";
import { Empty, Modal, PageHeader, PageLoader, Spinner } from "../components/ui";
import { IconCoin, IconStar } from "../components/icons";

const RUPEE = "\u20B9";

function PlanIcon({ plan }: { plan: Plan }) {
  const [failed, setFailed] = useState(false);
  const icon = plan.icon || "";
  const hasImg = (icon.startsWith("/") || icon.startsWith("http")) && !failed;
  return (
    <div className={cx("flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-full", plan.is_featured ? "bg-brand/15 text-brand" : "bg-[#13212F] text-gold")}>
      {hasImg ? (
        <img src={mediaUrl(icon)} alt="" className="h-full w-full object-cover" onError={() => setFailed(true)} />
      ) : icon === "star" ? (
        <IconStar size={22} />
      ) : (
        <IconCoin size={22} />
      )}
    </div>
  );
}

export default function Upgrade() {
  const nav = useNavigate();
  const { me, refreshMe, toast } = useApp();
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [banner, setBanner] = useState<string | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [paying, setPaying] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [history, setHistory] = useState<Purchase[] | null>(null);
  const [success, setSuccess] = useState<{ coins: number } | null>(null);

  const load = () => {
    setError(null);
    api
      .plans()
      .then((list) => {
        setPlans(list);
        setSelected((cur) => (cur !== null && list.some((p) => p.id === cur) ? cur : (list.find((p) => p.is_featured) ?? list[0])?.id ?? null));
      })
      .catch((e) => setError(friendly(e)));
  };

  useEffect(() => {
    load();
    api.upgradeBanner().then((b) => setBanner(b.upgrade_banner_url)).catch(() => undefined);
    void refreshMe();
  }, []);

  const buy = async () => {
    const p = plans?.find((x) => x.id === selected);
    if (!p || paying) return;
    setPaying(true);
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
      setPaying(false);
    }
  };

  const openHistory = () => {
    setHistoryOpen(true);
    setHistory(null);
    api.myPurchases().then(setHistory).catch((e) => { toast(friendly(e), "error"); setHistory([]); });
  };

  const hasPlans = !!plans && plans.length > 0;

  return (
    <div className="flex min-h-full flex-col">
      <PageHeader
        title="Buy coins"
        onBack={() => nav(-1)}
        right={<button onClick={openHistory} className="rounded-full px-3 py-1.5 text-sm font-semibold text-brand-soft hover:bg-white/10">History</button>}
      />
      <div className="mx-auto w-full max-w-xl flex-1 px-5 pt-2">
        <div className="relative flex min-h-[140px] items-center justify-center py-3">
          <div className="pointer-events-none absolute h-24 w-24 rounded-full bg-brand/50 blur-3xl" />
          {banner ? (
            <img src={mediaUrl(banner)} alt="" className="relative max-h-[220px] max-w-[260px] rounded-2xl object-contain" />
          ) : (
            <IconStar size={72} className="relative text-gold" />
          )}
        </div>

        <div className="mt-5 text-center">
          <div className="text-xs font-semibold uppercase tracking-widest text-[#9C8484]">My balance</div>
          <div className="mt-1.5 inline-flex items-center justify-center gap-2 text-2xl font-bold text-white">
            <IconCoin size={22} className="text-gold" />
            {me ? me.coins : "\u2014"} Coins
          </div>
        </div>

        <div className="mt-5">
          {error && !plans ? (
            <Empty title="Could not load plans" text={error} action={<button className="btn btn-primary" onClick={load}>Try again</button>} />
          ) : !plans ? (
            <PageLoader />
          ) : plans.length === 0 ? (
            <Empty title="No plans currently available" text="Please check back later." />
          ) : (
            plans.map((p) => {
              const sel = selected === p.id;
              return (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => setSelected(p.id)}
                  className={cx(
                    "relative mb-3.5 flex w-full items-center gap-3.5 rounded-[14px] bg-[#1A1A1A]/80 p-4 text-left transition",
                    sel ? "border-[1.6px] border-brand" : "border border-white/5"
                  )}
                >
                  <PlanIcon plan={p} />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-base font-semibold text-white">{p.name}</div>
                    <div className="mt-0.5 text-xs text-[#9C8484]">{p.coins} Coins</div>
                  </div>
                  <div className={cx("text-[17px] font-bold", p.is_featured ? "text-brand" : "text-white")}>{RUPEE}{p.price}</div>
                  {p.is_featured && (
                    <span className="absolute -top-2 right-3 rounded-md bg-brand px-2 py-0.5 text-[9px] font-bold uppercase tracking-wide text-white">Best seller</span>
                  )}
                </button>
              );
            })
          )}
        </div>
        <p className="mb-4 mt-2 text-center text-xs text-muted">Payments are processed securely by Razorpay.</p>
      </div>

      {hasPlans && (
        <div className="safe-b sticky bottom-0 z-10 bg-bg/95 px-5 pb-5 pt-3 backdrop-blur">
          <div className="mx-auto w-full max-w-xl">
            <button
              className="flex h-[52px] w-full items-center justify-center gap-2 rounded-[14px] bg-brand text-sm font-bold uppercase tracking-wider text-white transition hover:brightness-110 disabled:opacity-40"
              disabled={selected === null || paying}
              onClick={() => void buy()}
            >
              {paying ? <Spinner size={18} /> : "Purchase now"}
            </button>
          </div>
        </div>
      )}

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
                  <div className="text-xs text-muted">{listTimeLabel(h.created_at)} {"\u00B7"} {RUPEE}{h.price_paid}</div>
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
