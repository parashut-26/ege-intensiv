// Service Worker для Web Push уведомлений ЗебРус.
// Файл лежит в КОРНЕ домена — иначе scope не покроет весь сайт.
//
// Делает три вещи:
//  1) push: показывает уведомление в браузере при пуш-сообщении
//  2) notificationclick: открывает zebrus.online по клику
//  3) install + activate: skip waiting → claim — обновляется без F5

self.addEventListener('install', e => { self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(self.clients.claim()); });

self.addEventListener('push', event => {
  let data = {};
  try {
    if (event.data) {
      data = event.data.json();
    }
  } catch (_) {
    data = { title: 'ЗебРус', body: event.data ? event.data.text() : '' };
  }

  const title = data.title || 'ЗебРус 🐝';
  const options = {
    body:  data.body  || '',
    icon:  data.icon  || '/icon-192.png',
    badge: data.badge || '/icon-192.png',
    tag:   data.tag   || 'zebrus',
    data:  { url: data.url || 'https://zebrus.online' },
    requireInteraction: false,
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || 'https://zebrus.online';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clients => {
      // Если zebrus уже открыт — фокусируем
      for (const client of clients) {
        if (client.url.includes('zebrus.online') && 'focus' in client) {
          return client.focus();
        }
      }
      // Иначе — открываем новую вкладку
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});
