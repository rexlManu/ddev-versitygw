<?php

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\Storage;

chdir(getenv('DDEV_COMPOSER_ROOT') ?: '/var/www/html');
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

// Laravel's CLI exception renderer can return success for standalone scripts.
set_exception_handler(static function (Throwable $exception): never {
    fwrite(STDERR, $exception->__toString() . "\n");
    exit(1);
});

function check(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

if (($argv[1] ?? '') === 'production-default') {
    check(config('filesystems.disks.s3.retain_visibility') === true, 'Visibility retention must stay enabled outside DDEV.');
    echo "Production default passed.\n";
    exit;
}

check(config('filesystems.default') === 's3', 'The default disk must be s3.');
config(['filesystems.disks.s3.throw' => true]);
$disk = Storage::disk();

if (($argv[1] ?? '') === 'verify-upload') {
    check($disk->get('demo/browser-upload.txt') === 'Browser upload', 'The signed upload failed.');
    echo "Signed upload passed.\n";
    exit;
}

$key = 'demo/hello world+ä.txt';
$content = 'Hello from Laravel';
check($disk->put($key, $content, ['ContentType' => 'text/plain']), 'Writing failed.');
check($disk->exists($key), 'The uploaded file is missing.');
check($disk->get($key) === $content, 'The downloaded file differs.');
check($disk->size($key) === strlen($content), 'The file size differs.');
check($disk->mimeType($key) === 'text/plain', 'The content type differs.');
check(in_array($key, $disk->files('demo'), true), 'The file listing is missing the object.');
check($disk->copy($key, 'demo/copy.txt'), 'Copying failed.');
check($disk->move('demo/copy.txt', 'demo/moved.txt'), 'Moving failed.');
check($disk->delete('demo/moved.txt'), 'Deleting failed.');
check(!$disk->exists('demo/moved.txt'), 'The deleted object still exists.');

// Exceed the SDK's 16 MiB threshold to test multipart stream uploads.
$stream = tmpfile();
$chunk = str_repeat('streamed upload ', 65536);
for ($part = 0; $part < 18; $part++) {
    fwrite($stream, $chunk);
}
rewind($stream);
check($disk->put('demo/stream.txt', $stream), 'The multipart stream upload failed.');
check($disk->size('demo/stream.txt') === strlen($chunk) * 18, 'The stream size differs.');
rewind($stream);
$sourceHash = hash_init('sha256');
hash_update_stream($sourceHash, $stream);
$download = $disk->readStream('demo/stream.txt');
$downloadHash = hash_init('sha256');
hash_update_stream($downloadHash, $download);
check(hash_final($sourceHash) === hash_final($downloadHash), 'The stream content differs.');
fclose($stream);
fclose($download);

$upload = $disk->temporaryUploadUrl('demo/browser-upload.txt', now()->addMinutes(10));

echo json_encode([
    'public_url' => $disk->url($key),
    'temporary_url' => $disk->temporaryUrl($key, now()->addMinutes(10)),
    'upload_url' => $upload['url'],
    'upload_headers' => $upload['headers'],
], JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES) . "\n";
