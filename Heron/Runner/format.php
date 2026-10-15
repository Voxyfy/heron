<?php
// Tidies a snippet before Heron runs it: re-indents by nesting, adds the usual spaces after
// commas and control keywords and around braces, trims trailing spaces and extra blank lines.
// Works on PHP's own tokens, so text inside strings and comments is never touched.
// Argument: "tab" to indent with tabs, or the number of spaces per level (default 4).
// Reads the snippet from stdin, writes the tidy version to stdout; when brackets don't
// balance it writes the snippet back unchanged.

$source = stream_get_contents(STDIN);
$unit = ($argv[1] ?? '4') === 'tab' ? "\t" : str_repeat(' ', max(1, min(8, (int) ($argv[1] ?? 4))));
$hadOpenTag = (bool) preg_match('/^\s*<\?php/', $source);
$code = preg_replace('/^\s*<\?php\s*/', '', $source);

// No TOKEN_PARSE: snippets often end without a semicolon, which is fine for Heron.
$tokens = token_get_all('<?php ' . $code);
array_shift($tokens);

// Binary operators get one space on each side. + and - only count as binary after a value,
// so "-1" and "f(-$x)" stay as they are.
$binary = ['=', '<', '>', '*', '/', '%', '.', '|', '^', T_IS_EQUAL, T_IS_NOT_EQUAL, T_IS_IDENTICAL,
    T_IS_NOT_IDENTICAL, T_IS_SMALLER_OR_EQUAL, T_IS_GREATER_OR_EQUAL, T_SPACESHIP, T_BOOLEAN_AND,
    T_BOOLEAN_OR, T_LOGICAL_AND, T_LOGICAL_OR, T_COALESCE, T_DOUBLE_ARROW, T_PLUS_EQUAL, T_MINUS_EQUAL,
    T_MUL_EQUAL, T_DIV_EQUAL, T_CONCAT_EQUAL, T_MOD_EQUAL, T_COALESCE_EQUAL, T_POW, T_POW_EQUAL,
    T_AND_EQUAL, T_OR_EQUAL, T_XOR_EQUAL, T_SL, T_SR, T_SL_EQUAL, T_SR_EQUAL];
$values = [T_VARIABLE, T_LNUMBER, T_DNUMBER, T_CONSTANT_ENCAPSED_STRING, T_STRING, T_NAME_QUALIFIED,
    T_NAME_FULLY_QUALIFIED, T_INC, T_DEC];
$previous = null; // last token that wasn't whitespace or a comment
$afterOperator = false;
$controls = [T_IF, T_ELSEIF, T_FOREACH, T_FOR, T_WHILE, T_SWITCH, T_CATCH, T_MATCH, T_FN, T_FUNCTION];
$out = '';
$depth = 0;
$count = count($tokens);

for ($i = 0; $i < $count; $i++) {
    $token = $tokens[$i];
    $id = is_array($token) ? $token[0] : null;
    $text = is_array($token) ? $token[1] : $token;
    $next = $tokens[$i + 1] ?? null;
    $nextText = is_array($next) ? $next[1] : $next;
    $significant = !in_array($id, [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true);
    if ($significant && $id !== null || $significant && $text !== '') {
        $wasPrevious = $previous;
        $previous = $token;
    }
    if ($id !== T_WHITESPACE) {
        $afterOperator = false;
    }
    $isMinusOrPlus = in_array($text, ['+', '-'], true) && $id === null;
    $previousIsValue = isset($wasPrevious) && (in_array(is_array($wasPrevious) ? $wasPrevious[0] : $wasPrevious,
        $values, true) || in_array($wasPrevious, [')', ']'], true));
    if (in_array($id ?? $text, $binary, true) || ($isMinusOrPlus && $previousIsValue)) {
        $out = rtrim($out, ' ') . (str_ends_with($out, "\n") || $out === '' ? '' : ' ') . $text . ' ';
        $afterOperator = true;
        continue;
    }

    if ($id === T_WHITESPACE) {
        if ($text === '') {
            continue;
        }
        $newlines = substr_count($text, "\n");
        if ($newlines === 0) {
            if (!$afterOperator) {
                $out .= ' ';
            }
            continue;
        }
        // A new line: indent it by depth, one level less when it starts by closing a block.
        $out = rtrim($out, " \t");
        $out .= str_repeat("\n", min($newlines, 2));
        $closing = in_array($nextText, ['}', ')', ']'], true) ? 1 : 0;
        $out .= str_repeat($unit, max($depth - $closing, 0));
        continue;
    }

    if (in_array($text, ['{', '(', '['], true) || $id === T_CURLY_OPEN || $id === T_DOLLAR_OPEN_CURLY_BRACES) {
        if ($id === null && $text === '{' && $out !== '' && !in_array(substr($out, -1), [' ', "\n", '(', '{', '$'], true)) {
            $out .= ' ';
        }
        $depth++;
        $out .= $text;
        continue;
    }
    if (in_array($text, ['}', ')', ']'], true)) {
        $depth = max($depth - 1, 0);
        $out .= $text;
        // "}else", "){" and the like get their space.
        if ($text === '}' && is_array($next) && in_array($next[0], [T_ELSE, T_ELSEIF, T_CATCH, T_FINALLY], true)) {
            $out .= ' ';
        }
        if ($text === ')' && $nextText === '{') {
            $out .= ' ';
        }
        continue;
    }
    if ($text === ',' ) {
        $out .= ',';
        if ($next !== null && !(is_array($next) && $next[0] === T_WHITESPACE) && !in_array($nextText, [')', ']'], true)) {
            $out .= ' ';
        }
        continue;
    }
    if ($text === ';') {
        $out = rtrim($out, ' ') . ';';
        $nextIsSpace = is_array($next) && $next[0] === T_WHITESPACE;
        $afterSpace = $nextIsSpace ? ($tokens[$i + 2] ?? null) : $next;
        $endsLine = $next === null || ($nextIsSpace && str_contains($next[1], "\n"))
            || (is_array($afterSpace) && $afterSpace[0] === T_COMMENT);
        if ($depth > 0) {
            // "for ($i = 0; $i < 3; $i++)"
            if (!$nextIsSpace && !in_array($nextText, [')', '}'], true)) {
                $out .= ' ';
            }
        } elseif (!$endsLine) {
            // One statement per line at the top level.
            $tokens[$i] = [T_WHITESPACE, "\n"];
            if ($nextIsSpace) {
                $tokens[$i + 1] = [T_WHITESPACE, ''];
            }
            $i--;
        }
        continue;
    }
    if (in_array($id, $controls, true) && $nextText === '(') {
        $out .= $text . ' ';
        continue;
    }
    if ($id === T_COMMENT && str_ends_with($text, "\n")) {
        // "// note\n" carries its own newline; hand it to the whitespace logic so the
        // next line is indented like any other.
        $out .= rtrim($text, "\n");
        if (is_array($next) && $next[0] === T_WHITESPACE) {
            $tokens[$i + 1] = [T_WHITESPACE, "\n" . $next[1]];
        } else {
            $tokens[$i] = [T_WHITESPACE, "\n"];
            $i--;
        }
        continue;
    }
    $out .= $text;
}

if ($depth !== 0) {
    echo $source;
    exit;
}
$out = preg_replace("/[ \t]+\n/", "\n", $out);
echo ($hadOpenTag ? "<?php\n\n" : '') . trim($out) . "\n";
