import { api, friendly } from "./api";
import type { Plan } from "./types";

declare global {
  interface Window { Razorpay?: any }
}

let loading: Promise<void> | null = null;

function loadCheckout(): Promise<void> {
  if (window.Razorpay) return Promise.resolve();
  if (loading) return loading;
  loading = new Promise<void>((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://checkout.razorpay.com/v1/checkout.js";
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => { loading = null; reject(new Error("Could not load the payment window. Check your connection.")); };
    document.body.appendChild(s);
  });
  return loading;
}

export type PayResult =
  | { status: "success"; coins: number }
  | { status: "cancelled" }
  | { status: "failed"; message: string };

export async function payForPlan(plan: Plan): Promise<PayResult> {
  await loadCheckout();
  const order = await api.purchase(plan.id);
  return new Promise<PayResult>((resolve) => {
    let settled = false;
    let lastFailure: string | null = null;
    const done = (r: PayResult) => { if (!settled) { settled = true; resolve(r); } };
    const rzp = new window.Razorpay({
      key: order.key_id,
      amount: order.amount,
      currency: order.currency,
      name: "MindiCo",
      description: `${order.plan_name} · ${order.coins} coins`,
      order_id: order.order_id,
      image: `${import.meta.env.BASE_URL}logo.png`,
      prefill: { name: order.name || "", email: order.email || "", contact: order.contact || "" },
      theme: { color: "#0E8F3C" },
      handler: async (resp: { razorpay_order_id: string; razorpay_payment_id: string; razorpay_signature: string }) => {
        try {
          const r = await api.verifyPayment(resp.razorpay_order_id, resp.razorpay_payment_id, resp.razorpay_signature);
          done({ status: "success", coins: r.coins_balance });
        } catch (e) {
          done({ status: "failed", message: friendly(e, "Payment verification failed") });
        }
      },
      modal: {
        ondismiss: () => {
          if (lastFailure) { done({ status: "failed", message: lastFailure }); return; }
          void api.paymentFailed(order.order_id, "Checkout dismissed by user");
          done({ status: "cancelled" });
        },
      },
    });
    rzp.on("payment.failed", (resp: { error?: { description?: string } }) => {
      const reason = resp?.error?.description || "Payment failed";
      lastFailure = reason;
      void api.paymentFailed(order.order_id, reason);
    });
    rzp.open();
  });
}
