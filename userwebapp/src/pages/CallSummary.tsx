import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { humanDuration } from "../lib/util";
import type { CallSummary as Summary } from "../lib/types";
import { useApp } from "../state/app";
import { Avatar, BadgePill, PageLoader, Spinner } from "../components/ui";
import { IconCoin, IconStar } from "../components/icons";

export default function CallSummary() {
  const { callId } = useParams();
  const nav = useNavigate();
  const { toast, refreshMe, refreshListeners } = useApp();
  const [s, setS] = useState<Summary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [rating, setRating] = useState(0);
  const [hover, setHover] = useState(0);
  const [review, setReview] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const id = Number(callId);
    if (!id) { setError("Invalid call"); return; }
    api.callSummary(id)
      .then((r) => { setS(r); setRating(r.existing_rating ?? 0); setReview(r.existing_review ?? ""); })
      .catch((e) => setError(friendly(e)));
    void refreshMe();
  }, [callId]);

  const done = () => nav("/", { replace: true });

  const submit = async () => {
    if (!s || !rating) return;
    setBusy(true);
    try {
      await api.rateCall(s.call_id, rating, review.trim());
      toast("Thanks for your feedback", "success");
      void refreshListeners();
      done();
    } catch (e) {
      toast(friendly(e), "error");
    } finally {
      setBusy(false);
    }
  };

  if (error) {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center">
        <p className="text-sm text-muted">{error}</p>
        <button className="btn btn-primary mt-5" onClick={done}>Back to home</button>
      </div>
    );
  }
  if (!s) return <PageLoader />;

  const shown = hover || rating;
  const labels = ["", "Poor", "Fair", "Good", "Very good", "Excellent"];

  return (
    <div className="mx-auto flex w-full max-w-md flex-col items-center px-4 py-10">
      <Avatar src={s.listener_photo_url} name={s.listener_name} size={96} ring />
      <div className="mt-4 flex items-center gap-2">
        <h1 className="text-xl font-bold">{s.listener_name}</h1>
        <BadgePill tag={s.badge_tag} />
      </div>
      <p className="mt-1 text-sm text-muted">Call ended</p>

      <div className="mt-6 grid w-full grid-cols-2 gap-3">
        <div className="card p-4 text-center">
          <div className="text-xs uppercase tracking-wide text-muted">Duration</div>
          <div className="mt-1 text-lg font-bold">{humanDuration(s.duration_seconds ?? 0)}</div>
        </div>
        <div className="card p-4 text-center">
          <div className="text-xs uppercase tracking-wide text-muted">Coins used</div>
          <div className="mt-1 inline-flex items-center gap-1.5 text-lg font-bold text-gold"><IconCoin size={18} />{s.coins_deducted ?? 0}</div>
        </div>
      </div>

      <div className="card mt-6 w-full p-5">
        <h2 className="text-center font-semibold">{s.existing_rating ? "Update your rating" : "Rate your call"}</h2>
        <div className="mt-4 flex justify-center gap-2" onMouseLeave={() => setHover(0)}>
          {[1, 2, 3, 4, 5].map((n) => (
            <button key={n} onMouseEnter={() => setHover(n)} onClick={() => setRating(n)} aria-label={`${n} star`} className="transition hover:scale-110">
              <IconStar size={38} className={n <= shown ? "text-gold" : "text-ink/15"} />
            </button>
          ))}
        </div>
        <div className="mt-2 h-5 text-center text-sm text-gold">{labels[shown]}</div>
        <textarea
          value={review}
          onChange={(e) => setReview(e.target.value.slice(0, 300))}
          rows={3}
          placeholder="Share your experience (optional)"
          className="input mt-3 resize-none"
        />
        <button className="btn btn-primary mt-4 w-full" disabled={!rating || busy} onClick={() => void submit()}>
          {busy && <Spinner size={14} />} Submit
        </button>
      </div>

      <button className="mt-4 text-sm font-semibold text-muted hover:text-ink" onClick={done}>Skip</button>
    </div>
  );
}
