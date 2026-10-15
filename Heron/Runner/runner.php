<?php
// Runs one snippet for Heron. Arguments: the snippet file, the result file, the project folder.
// Echoed output goes to stdout as usual; everything else (the value of the last expression,
// the error, warnings, timing) is written to the result file as JSON, so a snippet that
// prints JSON itself can't be confused with Heron's own data.

// Made absolute first: the snippet runs from the project folder, and the result must not land there.
$heronCodeFile = $argv[1][0] === '/' ? $argv[1] : getcwd() . '/' . $argv[1];
$heronResultFile = $argv[2][0] === '/' ? $argv[2] : getcwd() . '/' . $argv[2];
$heronRoot = $argv[3] ?? '';
$heronResult = ['kind' => 'php', 'php' => PHP_VERSION, 'warnings' => [], 'items' => []];
$heronWritten = false;

function heron_write(array $result): void
{
    global $heronResultFile, $heronWritten;
    if ($heronWritten) {
        return;
    }
    $heronWritten = true;
    file_put_contents($heronResultFile, json_encode($result,
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR));
}

/** A JSON tree of any value, for the result panel. */
function heron_dump(mixed $value, int $depth = 0, array &$seen = []): array
{
    $limit = 200;
    switch (true) {
        case $value === null:
            return ['type' => 'null', 'summary' => 'null'];
        case is_bool($value):
            return ['type' => 'bool', 'summary' => $value ? 'true' : 'false'];
        case is_int($value):
            return ['type' => 'int', 'summary' => (string) $value];
        case is_float($value):
            return ['type' => 'float', 'summary' => var_export($value, true)];
        case is_string($value):
            $short = mb_strlen($value) > 10000 ? mb_substr($value, 0, 10000) . '…' : $value;
            return ['type' => 'string', 'summary' => $short, 'length' => mb_strlen($value)];
        case is_resource($value):
            return ['type' => 'resource', 'summary' => get_resource_type($value)];
        case is_array($value):
            $node = ['type' => 'array', 'summary' => 'array:' . count($value), 'count' => count($value)];
            if ($depth >= 8) {
                return $node;
            }
            $node['children'] = [];
            foreach (array_slice($value, 0, $limit, true) as $key => $item) {
                $node['children'][] = ['key' => (string) $key, 'value' => heron_dump($item, $depth + 1, $seen)];
            }
            return $node;
        case $value instanceof Closure:
            $reflection = new ReflectionFunction($value);
            return ['type' => 'closure', 'summary' => 'Closure(' . implode(', ', array_map(
                fn ($p) => '$' . $p->getName(), $reflection->getParameters())) . ')'];
        case is_object($value):
            $class = get_class($value);
            $id = spl_object_id($value);
            $node = ['type' => 'object', 'class' => $class, 'summary' => $class . ' #' . $id, 'oid' => $id];
            if (isset($seen[$id]) || $depth >= 8) {
                return $node;
            }
            $seen[$id] = true;
            $node['children'] = heron_properties($value, $depth, $seen, $limit);
            unset($seen[$id]);
            if ($value instanceof Countable) {
                $node['count'] = count($value);
            }
            return $node;
        default:
            return ['type' => gettype($value), 'summary' => print_r($value, true)];
    }
}

/** Laravel models and collections show their data; other objects show every property. */
function heron_properties(object $value, int $depth, array &$seen, int $limit): array
{
    $children = [];
    if (class_exists('Illuminate\Database\Eloquent\Model') && $value instanceof Illuminate\Database\Eloquent\Model) {
        foreach ($value->getAttributes() as $key => $item) {
            $children[] = ['key' => $key, 'value' => heron_dump($item, $depth + 1, $seen)];
        }
        foreach ($value->getRelations() as $key => $item) {
            $children[] = ['key' => $key, 'kind' => 'relation', 'value' => heron_dump($item, $depth + 1, $seen)];
        }
        return $children;
    }
    if (class_exists('Illuminate\Support\Collection') && $value instanceof Illuminate\Support\Collection) {
        return [['key' => 'all', 'value' => heron_dump($value->all(), $depth + 1, $seen)]];
    }
    if ($value instanceof DateTimeInterface) {
        return [['key' => 'date', 'value' => ['type' => 'string', 'summary' => $value->format('Y-m-d H:i:s.u P')]]];
    }
    foreach (array_slice((array) $value, 0, $limit, true) as $key => $item) {
        // (array) marks protected keys "\0*\0name" and private ones "\0Class\0name".
        $visibility = 'public';
        if (is_string($key) && str_starts_with($key, "\0")) {
            $visibility = str_starts_with($key, "\0*\0") ? 'protected' : 'private';
            $key = substr($key, strrpos($key, "\0") + 1);
        }
        $children[] = ['key' => (string) $key, 'kind' => $visibility, 'value' => heron_dump($item, $depth + 1, $seen)];
    }
    return $children;
}

/**
 * Wraps every top-level expression statement in heron_capture(): each marks its line in the
 * gutter, and the last one becomes the result card. Statements such as echo, if, foreach, use
 * or function are left alone. A missing semicolon on the last line is added.
 */
function heron_prepare(string $code): string
{
    $code = preg_replace('/^\s*<\?php/', '', $code);
    $tokens = token_get_all('<?php ' . $code);
    array_shift($tokens);
    $skip = [T_RETURN, T_ECHO, T_PRINT, T_IF, T_ELSE, T_ELSEIF, T_FOREACH, T_FOR, T_WHILE, T_DO, T_SWITCH,
        T_FUNCTION, T_CLASS, T_INTERFACE, T_TRAIT, T_ENUM, T_TRY, T_UNSET, T_GLOBAL, T_STATIC, T_THROW, T_USE,
        T_NAMESPACE, T_ABSTRACT, T_FINAL, T_READONLY, T_CONST, T_GOTO, T_BREAK, T_CONTINUE, T_EXIT, T_INLINE_HTML,
        T_DECLARE, T_REQUIRE, T_REQUIRE_ONCE, T_INCLUDE, T_INCLUDE_ONCE, T_YIELD, T_YIELD_FROM, T_ENDIF,
        T_ENDFOREACH, T_ENDFOR, T_ENDWHILE, T_ENDSWITCH, T_ENDDECLARE, T_CASE, T_DEFAULT, T_CLOSE_TAG, T_LIST,
        T_HALT_COMPILER, T_ATTRIBUTE];
    $statements = [];   // [start, end (exclusive, before ';'), firstToken, terminated, expression]
    $depth = 0;
    $offset = 0;
    $start = null;
    $first = null;
    $lastSignificantEnd = 0;
    foreach ($tokens as $token) {
        $text = is_array($token) ? $token[1] : $token;
        $id = is_array($token) ? $token[0] : null;
        $length = strlen($text);
        $significant = !in_array($id, [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true);
        if ($significant && $start === null) {
            $start = $offset;
            $first = $token;
        }
        if ($significant) {
            $lastSignificantEnd = $offset + $length;
        }
        if (in_array($text, ['(', '[', '{'], true) || $id === T_CURLY_OPEN || $id === T_DOLLAR_OPEN_CURLY_BRACES) {
            $depth++;
        } elseif (in_array($text, [')', ']', '}'], true)) {
            $depth--;
            if ($text === '}' && $depth === 0) {
                $statements[] = [$start, $offset + $length, $first, true, false];
                $start = null;
            }
        } elseif ($text === ';' && $depth === 0 && $start !== null) {
            $statements[] = [$start, $offset, $first, true, true];
            $start = null;
        }
        $offset += $length;
    }
    if ($start !== null && $depth === 0) {
        // The last statement has no semicolon.
        $statements[] = [$start, $lastSignificantEnd, $first, false, true];
    }
    // Which statements are expressions: only the last of them becomes a result card.
    $wrapped = [];
    foreach ($statements as $n => [$from, $to, $token, $terminated, $expression]) {
        $id = is_array($token) ? $token[0] : null;
        $text = is_array($token) ? $token[1] : $token;
        $wrapped[$n] = $expression && $text !== '{' && !in_array($id, $skip, true);
    }
    $lastWrapped = array_key_last(array_filter($wrapped));
    foreach (array_reverse($statements, true) as $n => [$from, $to, $token, $terminated, $expression]) {
        $line = substr_count(substr($code, 0, $from), "\n") + 1;
        $body = substr($code, $from, $to - $from);
        $card = $n === $lastWrapped ? 'true' : 'false';
        $replacement = $wrapped[$n] ? "heron_capture($line, ($body), $card)" : $body;
        if (!$terminated) {
            $replacement .= ';';
        }
        $code = substr($code, 0, $from) . $replacement . substr($code, $to);
    }
    return $code;
}

/**
 * A statement ran: its line gets a mark in the gutter; the last statement's value becomes a
 * result card (unless a dump() on the same line already made one).
 */
function heron_capture(int $line, mixed $value, bool $card = false): mixed
{
    global $heronResult;
    if (count($heronResult['items']) >= 500) {
        return $value;
    }
    $heronResult['items'][] = ['kind' => 'mark', 'line' => $line];
    if ($card) {
        foreach (array_reverse($heronResult['items']) as $item) {
            if ($item['kind'] === 'value') {
                if ($item['line'] === $line) {
                    return $value;
                }
                break;
            }
        }
        $heronResult['items'][] = ['kind' => 'value', 'line' => $line, 'value' => heron_dump($value)];
    }
    return $value;
}

/** The line of the snippet that called dump(), found in the stack. */
function heron_eval_line(): int
{
    foreach (debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS) as $frame) {
        if (isset($frame['file']) && str_contains($frame['file'], "eval()'d code")) {
            return (int) $frame['line'];
        }
    }
    return 0;
}

/** dump() and dd() put their values into the results as cards. */
function heron_dump_card(mixed $value): void
{
    global $heronResult;
    if (count($heronResult['items']) < 500) {
        $heronResult['items'][] = ['kind' => 'value', 'line' => heron_eval_line(), 'value' => heron_dump($value)];
    }
}

register_shutdown_function(function () {
    global $heronResult;
    $error = error_get_last();
    if ($error && in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
        $heronResult['error'] = ['class' => 'Fatal error', 'message' => $error['message'],
            'line' => str_contains($error['file'], "eval()'d code") ? $error['line'] : null];
    }
    heron_write($heronResult);
});

set_error_handler(function (int $level, string $message, string $file, int $line) {
    global $heronResult;
    if (!(error_reporting() & $level)) {
        return false;
    }
    $heronResult['warnings'][] = ['message' => $message,
        'line' => str_contains($file, "eval()'d code") ? $line : null];
    return true;
});

if ($heronRoot !== '') {
    chdir($heronRoot);
    try {
        if (is_file($heronRoot . '/vendor/autoload.php')) {
            require $heronRoot . '/vendor/autoload.php';
            $heronResult['kind'] = 'composer';
        }
        if (is_file($heronRoot . '/artisan') && is_file($heronRoot . '/bootstrap/app.php')) {
            $app = require $heronRoot . '/bootstrap/app.php';
            $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
            $heronResult['kind'] = 'laravel';
            $heronResult['framework'] = $app->version();
            // Every query the snippet runs, in order with the values.
            Illuminate\Support\Facades\DB::listen(function ($query) use (&$heronResult) {
                if (count($heronResult['items']) >= 500) {
                    return;
                }
                $sql = method_exists($query, 'toRawSql') ? $query->toRawSql() : $query->sql;
                $heronResult['items'][] = ['kind' => 'query', 'sql' => $sql, 'milliseconds' => $query->time,
                    'connection' => $query->connectionName];
            });
        }
    } catch (Throwable $e) {
        $heronResult['error'] = ['class' => get_class($e), 'message' => $e->getMessage(), 'line' => null,
            'phase' => 'bootstrap', 'file' => $e->getFile() . ':' . $e->getLine()];
        heron_write($heronResult);
        exit(1);
    }
}

if (class_exists('Symfony\Component\VarDumper\VarDumper')) {
    Symfony\Component\VarDumper\VarDumper::setHandler(function ($var) {
        heron_dump_card($var);
    });
}
if (!function_exists('dump')) {
    function dump(mixed ...$vars)
    {
        foreach ($vars as $var) {
            heron_dump_card($var);
        }
        return $vars[0] ?? null;
    }
}
if (!function_exists('dd')) {
    function dd(mixed ...$vars): never
    {
        dump(...$vars);
        exit(1);
    }
}

$heronStarted = hrtime(true);
try {
    (function () use ($heronCodeFile) {
        eval(heron_prepare(file_get_contents($heronCodeFile)));
    })();
} catch (Throwable $e) {
    $evalLine = null;
    if (str_contains($e->getFile(), "eval()'d code")) {
        $evalLine = $e->getLine();
    } else {
        foreach ($e->getTrace() as $frame) {
            if (isset($frame['file']) && str_contains($frame['file'], "eval()'d code")) {
                $evalLine = $frame['line'];
                break;
            }
        }
    }
    $heronResult['error'] = ['class' => get_class($e), 'message' => $e->getMessage(), 'line' => $evalLine];
}
// The last value doubles as "the" value, for the summary line.
foreach (array_reverse($heronResult['items']) as $heronItem) {
    if ($heronItem['kind'] === 'value') {
        $heronResult['value'] = $heronItem['value'];
        $heronResult['valueLine'] = $heronItem['line'];
        break;
    }
}
$heronResult['milliseconds'] = (hrtime(true) - $heronStarted) / 1e6;
$heronResult['memory'] = memory_get_peak_usage(true);
heron_write($heronResult);
