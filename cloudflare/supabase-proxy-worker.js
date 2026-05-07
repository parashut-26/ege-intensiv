/**
 * Cloudflare Worker — прокси api.zebrus.online → hyczawwuehrqsqqosgub.supabase.co
 *
 * Мобильные операторы РФ часто режут *.supabase.co. Этот Worker сидит
 * на api.zebrus.online (наш домен, не блокируется) и пробрасывает все
 * REST/Storage/Functions/Auth запросы к настоящему Supabase.
 *
 * Деплой через Cloudflare Dashboard:
 *   Workers & Pages → Create → Hello World → вставить этот код → Deploy
 * Затем привязка к api.zebrus.online через Custom Domains.
 */

const SUPABASE_HOST = 'hyczawwuehrqsqqosgub.supabase.co';

export default {
  async fetch(request) {
    const url = new URL(request.url);

    // Преобразуем URL: api.zebrus.online/rest/v1/foo → SUPABASE_HOST/rest/v1/foo
    const upstreamUrl = `https://${SUPABASE_HOST}${url.pathname}${url.search}`;

    // Клонируем headers (пропускаем Host — Worker сам его подставит)
    const headers = new Headers(request.headers);
    headers.delete('host');

    // Прокидываем запрос к настоящему Supabase
    const upstream = await fetch(upstreamUrl, {
      method: request.method,
      headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
      redirect: 'manual',
    });

    // Возвращаем ответ — добавляем CORS на случай preflight
    const responseHeaders = new Headers(upstream.headers);
    responseHeaders.set('Access-Control-Allow-Origin', '*');
    responseHeaders.set('Access-Control-Allow-Headers',
      'authorization, x-client-info, apikey, content-type, prefer, range');
    responseHeaders.set('Access-Control-Allow-Methods',
      'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD');
    responseHeaders.set('Access-Control-Expose-Headers',
      'content-range, content-length, etag');

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: responseHeaders });
    }

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  },
};
