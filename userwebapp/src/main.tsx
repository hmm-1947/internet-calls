import { createRoot } from "react-dom/client";
import App from "./App";
import "./index.css";
import { startCaptureGuard } from "./lib/captureGuard";

startCaptureGuard();
createRoot(document.getElementById("root")!).render(<App />);
