// PMS PWA (#228): no offline data, only a friendly page when a navigation can't reach the server.
// Bump CACHE when public/offline.html changes. Web Push (#237): the payload is Notification#push_payload.
const CACHE = "hueni-v1"
const OFFLINE = "/offline.html"

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.add(OFFLINE)))
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  if (event.request.mode !== "navigate") return
  event.respondWith(fetch(event.request).catch(() => caches.match(OFFLINE)))
})

self.addEventListener("push", (event) => {
  const note = event.data?.json() || {}
  event.waitUntil(self.registration.showNotification(note.title || "hueni", {
    body: note.body || "", tag: note.tag, silent: !!note.silent, icon: "/icon.png", lang: "vi", data: { url: note.url || "/thong-bao" }
  }))
})

// Opens what the notification is about in the app's window if there is one, else a new one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = new URL(event.notification.data?.url || "/thong-bao", self.location.origin).href
  event.waitUntil((async () => {
    const [client] = await clients.matchAll({ type: "window", includeUncontrolled: true })
    if (client) {
      await client.focus()
      return client.navigate(url).catch(() => clients.openWindow(url))
    }
    return clients.openWindow(url)
  })())
})
