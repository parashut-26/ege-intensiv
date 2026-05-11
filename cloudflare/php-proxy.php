<?php
/**
 * PHP-прокси для Supabase, v2.
 * Загрузить на reg.ru хостинг как index.php в корне субдомена api2.zebrus.online.
 *
 * Принимает любой запрос (GET/POST/PATCH/DELETE/OPTIONS),
 * пробрасывает на hyczawwuehrqsqqosgub.supabase.co с тем же путём,
 * возвращает ответ как есть + CORS-заголовки.
 *
 * Что нового в v2:
 *  • Длинные таймауты (CURL 60s, connect 15s) — спасает медленные запросы.
 *  • Внутренний retry x3 для GET с экспоненциальной задержкой 200/400/800 мс.
 *    Спасает от единичных 502/503/504 без участия фронта.
 *  • Запись в proxy.log (создаётся рядом). Включается переменной окружения
 *    PROXY_LOG=1 — или строкой 21 ниже (раскомментируй).
 *  • Увеличены ini-лимиты (memory_limit 256M, max_execution_time 90s).
 *  • POST/PATCH/DELETE НЕ ретраятся — они не идемпотентны, могут продублировать.
 */

// === Раскомментируй если хочешь видеть лог запросов в файл proxy.log ===
// putenv('PROXY_LOG=1');

ini_set('max_execution_time', '90');
ini_set('memory_limit', '256M');

// Чистая буферизация — никаких BOM/пробелов/уведомлений в выходе
while (ob_get_level()) ob_end_clean();
ob_start();

$SUPABASE_HOST = 'hyczawwuehrqsqqosgub.supabase.co';
$LOG_FILE = __DIR__ . '/proxy.log';
$LOG_ON = !!getenv('PROXY_LOG');

function pxlog(string $line): void {
    global $LOG_ON, $LOG_FILE;
    if (!$LOG_ON) return;
    @file_put_contents($LOG_FILE,
        '[' . date('Y-m-d H:i:s') . '] ' . $line . "\n",
        FILE_APPEND | LOCK_EX);
}

// === CORS preflight ===
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD');
    // x-upsert / cache-control / x-upload-id шлёт Supabase Storage SDK при upload.
    header('Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type, prefer, range, x-supabase-api-version, accept, accept-language, accept-profile, content-profile, x-requested-with, x-upsert, cache-control, x-upload-id, tus-resumable, upload-length, upload-metadata, upload-offset');
    header('Access-Control-Max-Age: 86400');
    http_response_code(204);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
$path = $_SERVER['REQUEST_URI'];
$url = "https://{$SUPABASE_HOST}{$path}";

// === Заголовки от клиента ===
$headers = [];
$has_auth = false;
foreach (getallheaders() as $name => $value) {
    $lower = strtolower($name);
    if ($lower === 'host') continue;
    if ($lower === 'accept-encoding') continue;
    if ($lower === 'authorization') $has_auth = true;
    $headers[] = "{$name}: {$value}";
}

// Подстраховка для FastCGI/Apache
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
    if ($auth_value) $headers[] = "Authorization: {$auth_value}";
}

// === Тело запроса ===
$body = null;
if (in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'])) {
    $body = file_get_contents('php://input');
}

// === Функция одного CURL-запроса ===
function do_curl(string $method, string $url, array $headers, ?string $body): array {
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HEADER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_TIMEOUT, 60);          // было 30
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 15);   // было 10
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
    curl_setopt($ch, CURLOPT_ENCODING, '');         // cURL сам разжимает
    if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, $body);

    $resp = curl_exec($ch);
    $err = curl_error($ch);
    $errno = curl_errno($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $header_size = (int)curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    curl_close($ch);

    return [
        'resp' => $resp,
        'err' => $err,
        'errno' => $errno,
        'status' => $status,
        'header_size' => $header_size,
    ];
}

// === Основной запрос с ретраями для GET ===
$is_idempotent = in_array($method, ['GET', 'HEAD']);
$max_attempts = $is_idempotent ? 3 : 1;
$result = null;
$attempt = 0;

while ($attempt < $max_attempts) {
    $attempt++;
    $t_start = microtime(true);
    $result = do_curl($method, $url, $headers, $body);
    $elapsed_ms = (int)((microtime(true) - $t_start) * 1000);

    // Успех = код 2xx/3xx/4xx (4xx — клиентская ошибка, не наша)
    $is_network_error = ($result['resp'] === false || !empty($result['err']));
    $is_5xx = $result['status'] >= 500 && $result['status'] <= 599;
    $should_retry = $is_idempotent && ($is_network_error || $is_5xx) && $attempt < $max_attempts;

    pxlog(sprintf('%s %s → %d %s in %dms (attempt %d/%d)%s',
        $method, $path, $result['status'],
        ($is_network_error ? '[netfail: ' . $result['err'] . ']' : ''),
        $elapsed_ms, $attempt, $max_attempts,
        $should_retry ? ' → retry' : ''));

    if (!$should_retry) break;

    // Экспоненциальная задержка: 200, 400, 800 мс
    usleep(200000 * (1 << ($attempt - 1)));
}

// === Если совсем не сложилось ===
if ($result['resp'] === false || !empty($result['err'])) {
    header('Content-Type: application/json');
    header('Access-Control-Allow-Origin: *');
    http_response_code(502);
    echo json_encode(['error' => 'proxy: ' . $result['err'], 'attempts' => $attempt]);
    exit;
}

// === Разделяем заголовки и тело ===
$head = substr($result['resp'], 0, $result['header_size']);
$out_body = substr($result['resp'], $result['header_size']);

http_response_code($result['status']);
$lines = explode("\r\n", trim($head));
foreach ($lines as $line) {
    if (preg_match('/^HTTP\//i', $line)) continue;
    // Не пробрасываем заголовки, которые могут поломать передачу
    if (preg_match('/^(Transfer-Encoding|Connection|Content-Length|Content-Encoding):/i', $line)) continue;
    if (strpos($line, ':') !== false) header($line, false);
}

header('Access-Control-Allow-Origin: *');
header('Access-Control-Expose-Headers: content-range, content-length, etag');

ob_end_clean();
echo $out_body;
