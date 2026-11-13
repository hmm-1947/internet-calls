import { lazy, Suspense, useEffect, useRef, useState, type ReactNode } from "react";
import { HashRouter, Navigate, Route, Routes, useNavigate } from "react-router-dom";
import { AppProvider, useApp } from "./state/app";
import { CallProvider } from "./state/call";
import { startTabGuard, type TabState } from "./lib/tabGuard";
import { Shell } from "./components/Shell";
import { PageLoader } from "./components/ui";
import Login from "./pages/Login";
import Register from "./pages/Register";
import Forgot from "./pages/Forgot";
import ProfileSetup from "./pages/ProfileSetup";
import Home from "./pages/Home";

const Chats = lazy(() => import("./pages/Chats"));
const Calls = lazy(() => import("./pages/Calls"));
const CallSummary = lazy(() => import("./pages/CallSummary"));
const ListenerProfile = lazy(() => import("./pages/ListenerProfile"));
const Upgrade = lazy(() => import("./pages/Upgrade"));
const Settings = lazy(() => import("./pages/Settings"));
const EditProfile = lazy(() => import("./pages/EditProfile"));
const ChangePassword = lazy(() => import("./pages/ChangePassword"));
const ContactChange = lazy(() => import("./pages/ContactChange"));
const Legal = lazy(() => import("./pages/Legal"));

function Protected() {
  const { token } = useApp();
  return token ? <Shell /> : <Navigate to="/login" replace />;
}

function Public({ children }: { children: ReactNode }) {
  const { token } = useApp();
  return token ? <Navigate to="/" replace /> : <>{children}</>;
}

function Private({ children }: { children: ReactNode }) {
  const { token } = useApp();
  return token ? <>{children}</> : <Navigate to="/login" replace />;
}

function Bridge() {
  const nav = useNavigate();
  const { openChatRef } = useApp();
  useEffect(() => {
    openChatRef.current = (id) => nav(`/chats/${id}`);
    return () => { openChatRef.current = null; };
  }, [nav, openChatRef]);
  return null;
}

function Blocked({ onSwitch }: { onSwitch: () => void }) {
  return (
    <div className="flex min-h-full items-center justify-center bg-[radial-gradient(ellipse_at_top,rgba(18,160,68,0.18),transparent_60%)] px-4">
      <div className="card2 w-full max-w-md p-8 text-center shadow-2xl">
        <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" className="mx-auto mb-5 h-14 w-14 rounded-2xl object-cover" />
        <h1 className="text-xl font-bold">MindiCo is open in another tab</h1>
        <p className="mt-2 text-sm text-muted">
          Only one tab can be active at a time so your chats and calls stay in sync. Switch to use MindiCo here instead.
        </p>
        <button className="btn btn-primary mt-6 w-full" onClick={onSwitch}>Use MindiCo in this tab</button>
      </div>
    </div>
  );
}

function Routed() {
  return (
    <>
      <Bridge />
      <Suspense fallback={<PageLoader />}>
        <Routes>
          <Route path="/login" element={<Public><Login /></Public>} />
          <Route path="/register" element={<Public><Register /></Public>} />
          <Route path="/forgot" element={<Public><Forgot /></Public>} />
          <Route path="/setup" element={<Private><ProfileSetup /></Private>} />
          <Route element={<Protected />}>
            <Route index element={<Home />} />
            <Route path="chats" element={<Chats />} />
            <Route path="chats/:listenerId" element={<Chats />} />
            <Route path="calls" element={<Calls />} />
            <Route path="call-summary/:callId" element={<CallSummary />} />
            <Route path="listener/:listenerId" element={<ListenerProfile />} />
            <Route path="upgrade" element={<Upgrade />} />
            <Route path="settings" element={<Settings />} />
            <Route path="settings/profile" element={<EditProfile />} />
            <Route path="settings/password" element={<ChangePassword />} />
            <Route path="settings/contact" element={<ContactChange />} />
            <Route path="legal/:type" element={<Legal />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </>
  );
}

export default function App() {
  const [tab, setTab] = useState<TabState>("checking");
  const guard = useRef<ReturnType<typeof startTabGuard> | null>(null);

  useEffect(() => {
    const g = startTabGuard(setTab);
    guard.current = g;
    return () => g.dispose();
  }, []);

  if (tab === "checking") return <PageLoader />;
  if (tab === "blocked") return <Blocked onSwitch={() => guard.current?.takeOver()} />;

  return (
    <HashRouter>
      <AppProvider>
        <CallProvider>
          <Routed />
        </CallProvider>
      </AppProvider>
    </HashRouter>
  );
}
