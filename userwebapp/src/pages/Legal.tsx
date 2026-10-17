import { useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { api, friendly } from "../lib/api";
import { sanitizeHtml } from "../lib/util";
import { Empty, PageHeader, PageLoader } from "../components/ui";

export default function Legal() {
  const { type } = useParams();
  const nav = useNavigate();
  const isTerms = type === "terms";
  const [html, setHtml] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = () => {
    setError(null);
    setHtml(null);
    api.termsPrivacy()
      .then((r) => setHtml((isTerms ? r.terms_of_service : r.privacy_policy) || ""))
      .catch((e) => setError(friendly(e)));
  };

  useEffect(load, [type]);

  const clean = useMemo(() => (html ? sanitizeHtml(html) : ""), [html]);

  return (
    <div>
      <PageHeader title={isTerms ? "Terms of Service" : "Privacy Policy"} onBack={() => nav("/settings")} />
      <div className="mx-auto w-full max-w-3xl px-4 pb-12 pt-6 md:px-8">
        {error ? (
          <Empty title="Could not load document" text={error} action={<button className="btn btn-primary" onClick={load}>Try again</button>} />
        ) : html === null ? (
          <PageLoader />
        ) : !clean ? (
          <Empty title="Nothing here yet" text="This document has not been published." />
        ) : (
          <div className="legal" dangerouslySetInnerHTML={{ __html: clean }} />
        )}
      </div>
    </div>
  );
}
