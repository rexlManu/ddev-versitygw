<?php
// #ddev-generated

declare(strict_types=1);

$path = 'config/filesystems.php';
if (!is_file($path)) {
    return;
}

$config = file_get_contents($path);
if ($config === false) {
    throw new RuntimeException("VersityGW: could not read {$path}.");
}

// Respect an existing visibility setting. Run this edit once per project.
if (str_contains($config, 'retain_visibility')) {
    return;
}

$updated = preg_replace(
    '/^([ \t]*)([\'"])driver\2\s*=>\s*([\'"])s3\3\s*,/m',
    "$0\n$1// VersityGW uses bucket policies instead of object ACLs.\n$1'retain_visibility' => env('VERSITYGW_RETAIN_VISIBILITY', true),",
    $config,
    -1,
    $count,
);

if ($count === 0) {
    fwrite(STDERR, "VersityGW: add 'retain_visibility' => env('VERSITYGW_RETAIN_VISIBILITY', true) to your S3 disk config to support copying and moving files.\n");
    return;
}

if ($updated === null || file_put_contents($path, $updated) === false) {
    throw new RuntimeException("VersityGW: could not update {$path}.");
}

echo "VersityGW: configured Laravel copies and moves in {$path}.\n";
