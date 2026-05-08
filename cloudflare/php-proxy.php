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

$SUPABASE_HOST = 'hyczawwuehrqsqqosgub.supabase.co';

// CORS preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD');
    header('Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type, prefer, range');
    header('Access-Control-Max-Age: 86400');
    http_response_code(204);
    exit;
}

// Берём путь и query string из запроса
$path = $_SERVER['REQUEST_URI'];
$url = "https://{$SUPABASE_HOST}{$path}";

// Собираем заголовки от клиента (кроме Host)
$headers = [];
foreach (getallheaders() as $name => $value) {
    if (strtolower($name) === 'host') continue;
    $headers[] = "{$name}: {$value}";
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

echo $out_body;
