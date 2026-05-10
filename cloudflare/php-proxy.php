<?php
/**
 * Простой PHP-прокси для Supabase.
 * Загрузить на reg.ru хостинг как index.php в корне субдомена api2.zebrus.online.
 *
 * Принимает любой запрос (GET/POST/PATCH/DELETE/OPTIONS),
 * пробрасывает на hyczawwuehrqsqqosgub.supabase.co с тем же путём,
 * возвращает ответ как есть + CORS-заголовки.
 *
 * Российский IP, поэтому провайдеры не блокируют.
 */

// Чистая буферизация — никаких BOM/пробелов/уведомлений в выходе
while (ob_get_level()) ob_end_clean();
ob_start();

$SUPABASE_HOST = 'hyczawwuehrqsqqosgub.supabase.co';

// CORS preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD');
    // x-upsert / cache-control / x-upload-id шлёт Supabase Storage SDK при upload.
    // Без них preflight отбрасывал запрос и заливка падала с "Load failed".
    header('Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type, prefer, range, x-supabase-api-version, accept, accept-language, accept-profile, content-profile, x-requested-with, x-upsert, cache-control, x-upload-id, tus-resumable, upload-length, upload-metadata, upload-offset');
    header('Access-Control-Max-Age: 86400');
    http_response_code(204);
    exit;
}

// Берём путь и query string из запроса
$path = $_SERVER['REQUEST_URI'];
$url = "https://{$SUPABASE_HOST}{$path}";

// Собираем заголовки от клиента (кроме Host и Accept-Encoding —
// последний заставит Supabase отдавать gzip, а cURL сам разжимает).
$headers = [];
$has_auth = false;
foreach (getallheaders() as $name => $value) {
    $lower = strtolower($name);
    if ($lower === 'host') continue;
    if ($lower === 'accept-encoding') continue;
    if ($lower === 'authorization') $has_auth = true;
    $headers[] = "{$name}: {$value}";
}

// Подстраховка для FastCGI/Apache — Authorization мог не дойти через getallheaders.
// Пробуем явно прочитать из $_SERVER (заполняется через .htaccess RewriteRule).
if (!$has_auth) {
    $auth_value = '';
    if (!empty($_SERVER['HTTP_AUTHORIZATION'])) {
        $auth_value = $_SERVER['HTTP_AUTHORIZATION'];
    } elseif (!empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        $auth_value = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    } elseif (function_exists('apache_request_headers')) {
        $apache = apache_request_headers();
        foreach ($apache as $k => $v) {
            if (strtolower($k) === 'authorization') { $auth_value = $v; break; }
        }
    }
    if ($auth_value) {
        $headers[] = "Authorization: {$auth_value}";
    }
}

// Тело запроса (для POST/PATCH/PUT)
$body = null;
if (in_array($_SERVER['REQUEST_METHOD'], ['POST', 'PUT', 'PATCH', 'DELETE'])) {
    $body = file_get_contents('php://input');
}

// CURL запрос
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HEADER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $_SERVER['REQUEST_METHOD']);
curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
// Передаём gzip/deflate автоматически — cURL разжимает на лету
curl_setopt($ch, CURLOPT_ENCODING, '');

if ($body !== null) {
    curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
}

$response = curl_exec($ch);
$err = curl_error($ch);
$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$header_size = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
curl_close($ch);

if ($err || $response === false) {
    header('Content-Type: application/json');
    header('Access-Control-Allow-Origin: *');
    http_response_code(502);
    echo json_encode(['error' => 'proxy: ' . $err]);
    exit;
}

// Разделяем заголовки и тело
$head = substr($response, 0, $header_size);
$out_body = substr($response, $header_size);

// Передаём заголовки из upstream-ответа клиенту
http_response_code($status);
$lines = explode("\r\n", trim($head));
foreach ($lines as $line) {
    // Пропускаем status line и проблемные заголовки
    if (preg_match('/^HTTP\//i', $line)) continue;
    if (preg_match('/^(Transfer-Encoding|Connection|Content-Length|Content-Encoding):/i', $line)) continue;
    if (strpos($line, ':') !== false) header($line, false);
}

// CORS-заголовки в ответе (на всякий случай)
header('Access-Control-Allow-Origin: *');
header('Access-Control-Expose-Headers: content-range, content-length, etag');

// Очищаем буфер и выводим только тело ответа (без BOM/пробелов)
ob_end_clean();
echo $out_body;
