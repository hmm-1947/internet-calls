import { initializeApp, getApps } from "firebase/app";
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut } from "firebase/auth";
import { FIREBASE_CONFIG } from "./config";

export const firebaseConfigured = () => !!FIREBASE_CONFIG.apiKey && !!FIREBASE_CONFIG.appId;

export function firebaseApp() {
  return getApps()[0] ?? initializeApp(FIREBASE_CONFIG);
}

export async function googleIdToken(): Promise<string> {
  if (!firebaseConfigured()) {
    throw new Error("Google sign-in is not configured for the web app yet.");
  }
  const auth = getAuth(firebaseApp());
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: "select_account" });
  try {
    const cred = await signInWithPopup(auth, provider);
    const token = await cred.user.getIdToken();
    await signOut(auth).catch(() => undefined);
    return token;
  } catch (e) {
    const code = (e as { code?: string }).code ?? "";
    if (code === "auth/popup-closed-by-user" || code === "auth/cancelled-popup-request") {
      throw new Error("Google sign-in was cancelled");
    }
    if (code === "auth/popup-blocked") throw new Error("Your browser blocked the Google sign-in popup. Allow popups and try again.");
    if (code === "auth/unauthorized-domain") throw new Error("This domain is not authorised for Google sign-in yet.");
    throw new Error("Google sign-in failed. Please try again.");
  }
}
