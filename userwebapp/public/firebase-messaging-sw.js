importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js");

const q = new URL(self.location.href).searchParams;
const BASE = q.get("base") || "/app/";

firebase.initializeApp({
  apiKey: q.get("apiKey"),
  authDomain: q.get("authDomain"),
  projectId: q.get("projectId"),
  messagingSenderId: q.get("messagingSenderId"),
  appId: q.get("appId"),
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const d = payload.data || {};
  if (d.type !== "chat_message") return;
  return self.registration.showNotification(d.title || "New message", {
    body: d.body || "",
    icon: d.icon || BASE + "logo.png",
    badge: BASE + "logo.png",
    tag: "chat-" + (d.listener_id || ""),
    renotify: true,
    data: { listener_id: d.listener_id || "" },
  });
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const id = (event.notification.data || {}).listener_id;
  const target = BASE + (id ? "#/chats/" + id : "");
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.startsWith(self.location.origin + BASE)) {
          c.focus();
          if (id) c.postMessage({ type: "open-chat", listener_id: id });
          return;
        }
      }
      return self.clients.openWindow(target);
    })
  );
});
