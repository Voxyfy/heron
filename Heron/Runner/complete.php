<?php
// Answers completion requests for Heron. Arguments: the project folder (or ""), a mode, a subject.
//   members <Class>   public methods and properties of a class, plus a model's columns, relations
//                     and scopes; each method says what it returns, so chains can be followed
//   functions         the functions a snippet can call: PHP's own and the framework's helpers
//   classes           every class Composer knows, as short name + full name
// Output is JSON on stdout. Runs inside the project like runner.php, so facades resolve.

$root = $argv[1] ?? '';
$mode = $argv[2] ?? 'functions';
$subject = $argv[3] ?? '';
$isLaravel = false;

error_reporting(E_ALL & ~E_DEPRECATED & ~E_NOTICE & ~E_WARNING);
set_error_handler(fn () => true);

if ($root !== '' && is_file($root . '/vendor/autoload.php')) {
    chdir($root);
    require $root . '/vendor/autoload.php';
    if (is_file($root . '/artisan') && is_file($root . '/bootstrap/app.php')) {
        try {
            $app = require $root . '/bootstrap/app.php';
            $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
            $isLaravel = true;
        } catch (Throwable) {
        }
    }
}

function heron_out(array $items): never
{
    echo json_encode($items, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

/** The class a method hands back, as a full name, or null when it isn't a class. */
function heron_return_type(ReflectionMethod $method, string $owner): ?string
{
    $type = $method->getReturnType();
    $names = [];
    if ($type instanceof ReflectionNamedType) {
        $names[] = $type->getName();
    } elseif ($type instanceof ReflectionUnionType) {
        foreach ($type->getTypes() as $part) {
            if ($part instanceof ReflectionNamedType) {
                $names[] = $part->getName();
            }
        }
    }
    if ($names === [] && ($doc = $method->getDocComment()) && preg_match('/@return\s+([^\s]+)/', $doc, $m)) {
        $names = explode('|', $m[1]);
    }
    foreach ($names as $name) {
        $name = ltrim($name, '\\');
        $name = preg_replace('/<.*$/', '', $name);
        if (in_array($name, ['static', '$this', 'self', 'this'], true)) {
            return $owner;
        }
        if ($name === 'TModel' || $name === 'TValue') {
            return null;
        }
        if (class_exists($name) || interface_exists($name)) {
            return $name;
        }
        if (str_contains($name, '\\') === false && class_exists('Illuminate\\Support\\' . $name)) {
            return 'Illuminate\\Support\\' . $name;
        }
    }
    return null;
}

/** Parameter names in order, each marked optional or not, for placeholders in the editor. */
function heron_param_list(ReflectionFunctionAbstract $function): array
{
    $list = [];
    foreach ($function->getParameters() as $parameter) {
        $list[] = ['name' => $parameter->getName(), 'optional' => $parameter->isOptional() || $parameter->isVariadic()];
    }
    return $list;
}

function heron_params(ReflectionFunctionAbstract $function): string
{
    $parts = [];
    foreach ($function->getParameters() as $parameter) {
        $part = '$' . $parameter->getName();
        if ($parameter->isOptional()) {
            $part = '?' . $part;
        }
        $parts[] = $part;
    }
    return implode(', ', $parts);
}

function heron_members(string $class): array
{
    $isFacade = false;
    try {
        $reflection = new ReflectionClass($class);
    } catch (Throwable) {
        heron_out([]);
    }
    $items = [];
    $seen = [];
    $owner = $class;

    // A facade completes with the methods of the object behind it.
    if (class_exists('Illuminate\\Support\\Facades\\Facade') && $reflection->isSubclassOf('Illuminate\\Support\\Facades\\Facade')) {
        $isFacade = true;
        try {
            $rootObject = $class::getFacadeRoot();
            if (is_object($rootObject)) {
                $owner = get_class($rootObject);
                $reflection = new ReflectionClass($rootObject);
            }
        } catch (Throwable) {
        }
    }

    $isModel = class_exists('Illuminate\\Database\\Eloquent\\Model') && $reflection->isSubclassOf('Illuminate\\Database\\Eloquent\\Model');

    foreach ($reflection->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
        $name = $method->getName();
        if (str_starts_with($name, '__') || isset($seen[$name])) {
            continue;
        }
        // Scopes become where-like methods on the query: scopeActive() is called as active().
        if ($isModel && str_starts_with($name, 'scope') && strlen($name) > 5) {
            $scope = lcfirst(substr($name, 5));
            $items[] = ['label' => $scope, 'kind' => 'scope', 'detail' => 'scope', 'insert' => $scope . '()',
                'returns' => 'Illuminate\\Database\\Eloquent\\Builder'];
            $seen[$scope] = true;
            continue;
        }
        $seen[$name] = true;
        $returns = heron_return_type($method, $owner);
        $items[] = ['label' => $name, 'kind' => $method->isStatic() || $isFacade ? 'static' : 'method',
            'detail' => '(' . heron_params($method) . ')' . ($returns ? ': ' . $returns : ''),
            'insert' => $name . ($method->getNumberOfParameters() ? '(' : '()'), 'returns' => $returns,
            'static' => $method->isStatic() || $isFacade, 'params' => heron_param_list($method)];
    }
    foreach ($reflection->getProperties(ReflectionProperty::IS_PUBLIC) as $property) {
        if ($property->isStatic() || isset($seen[$property->getName()])) {
            continue;
        }
        $type = $property->getType();
        $returns = $type instanceof ReflectionNamedType && class_exists($type->getName()) ? $type->getName() : null;
        $items[] = ['label' => $property->getName(), 'kind' => 'property', 'detail' => (string) $type,
            'insert' => $property->getName(), 'returns' => $returns];
    }

    if ($isModel) {
        // Columns from the database, relations from methods that return one, both as properties.
        try {
            $instance = $reflection->newInstanceWithoutConstructor();
            $table = $instance->getTable();
            $columns = Illuminate\Support\Facades\Schema::getColumnListing($table);
            foreach ($columns as $column) {
                if (!isset($seen[$column])) {
                    $items[] = ['label' => $column, 'kind' => 'column', 'detail' => $table, 'insert' => $column, 'returns' => null];
                    $seen[$column] = true;
                }
            }
        } catch (Throwable) {
        }
        foreach ($reflection->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
            if ($method->getDeclaringClass()->getName() === 'Illuminate\\Database\\Eloquent\\Model' || $method->getNumberOfRequiredParameters() > 0) {
                continue;
            }
            $returns = heron_return_type($method, $class);
            if ($returns && is_subclass_of($returns, 'Illuminate\\Database\\Eloquent\\Relations\\Relation')) {
                $related = null;
                try {
                    $instance ??= $reflection->newInstanceWithoutConstructor();
                    $relation = $method->invoke($instance);
                    $related = get_class($relation->getRelated());
                    $many = !($relation instanceof Illuminate\Database\Eloquent\Relations\BelongsTo
                        || $relation instanceof Illuminate\Database\Eloquent\Relations\HasOne
                        || $relation instanceof Illuminate\Database\Eloquent\Relations\MorphOne
                        || $relation instanceof Illuminate\Database\Eloquent\Relations\HasOneThrough);
                } catch (Throwable) {
                    $many = true;
                }
                $items[] = ['label' => $method->getName(), 'kind' => 'relation',
                    'detail' => (new ReflectionClass($returns))->getShortName() . ($related ? ' ' . $related : ''),
                    'insert' => $method->getName(),
                    'returns' => $many ? 'Illuminate\\Database\\Eloquent\\Collection' : $related];
            }
        }
        // Static calls on a model go to its query builder: User::where(...) etc.
        $builder = new ReflectionClass('Illuminate\\Database\\Eloquent\\Builder');
        foreach ($builder->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
            $name = $method->getName();
            if (str_starts_with($name, '__') || isset($seen[$name])) {
                continue;
            }
            $seen[$name] = true;
            $items[] = ['label' => $name, 'kind' => 'static', 'detail' => '(' . heron_params($method) . ')',
                'insert' => $name . ($method->getNumberOfParameters() ? '(' : '()'),
                'returns' => heron_builder_return($name, $class), 'static' => true, 'params' => heron_param_list($method)];
        }
        $query = new ReflectionClass('Illuminate\\Database\\Query\\Builder');
        foreach ($query->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
            $name = $method->getName();
            if (str_starts_with($name, '__') || isset($seen[$name])) {
                continue;
            }
            $seen[$name] = true;
            $items[] = ['label' => $name, 'kind' => 'static', 'detail' => '(' . heron_params($method) . ')',
                'insert' => $name . ($method->getNumberOfParameters() ? '(' : '()'),
                'returns' => heron_builder_return($name, $class), 'static' => true, 'params' => heron_param_list($method)];
        }
    }
    if ($class === 'Illuminate\\Database\\Eloquent\\Builder' || $class === 'Illuminate\\Database\\Query\\Builder') {
        foreach ($items as &$item) {
            $item['returns'] = heron_builder_return($item['label'], null) ?? $item['returns'];
        }
        unset($item);
    }
    if ($class === 'Illuminate\\Database\\Eloquent\\Collection') {
        // Items of a model collection are that model.
        foreach ($items as &$item) {
            if (in_array($item['label'], ['first', 'last', 'find', 'pop', 'shift', 'sole', 'firstWhere', 'random'], true)) {
                $item['returns'] = '@model';
            }
        }
        unset($item);
    }
    return $items;
}

/** What a query method gives back: the model, a collection of them, or the builder again. */
function heron_builder_return(string $method, ?string $model): ?string
{
    $single = ['first', 'find', 'findOrFail', 'firstOrFail', 'firstOrNew', 'firstOrCreate', 'updateOrCreate', 'create',
        'make', 'sole', 'firstWhere', 'findOrNew', 'fresh', 'refresh', 'latestOfMany', 'oldestOfMany'];
    $many = ['get', 'all', 'findMany', 'cursor', 'lazy', 'paginate', 'simplePaginate', 'chunk'];
    $plain = ['pluck', 'count', 'sum', 'avg', 'max', 'min', 'exists', 'doesntExist', 'toSql', 'toRawSql', 'value',
        'delete', 'update', 'insert', 'increment', 'decrement'];
    if (in_array($method, $single, true)) {
        return $model ?? '@model';   // the model is known from the start of the chain
    }
    if (in_array($method, $many, true)) {
        return 'Illuminate\\Database\\Eloquent\\Collection';
    }
    if ($method === 'pluck') {
        return 'Illuminate\\Support\\Collection';
    }
    if (in_array($method, $plain, true)) {
        return null;
    }
    return 'Illuminate\\Database\\Eloquent\\Builder';
}

switch ($mode) {
    case 'members':
        heron_out(heron_members(ltrim($subject, '\\')));
    case 'classes':
        $items = [];
        if (class_exists('Composer\\Autoload\\ClassLoader')) {
            foreach (spl_autoload_functions() as $loader) {
                if (is_array($loader) && $loader[0] instanceof Composer\Autoload\ClassLoader) {
                    foreach ($loader[0]->getClassMap() as $name => $file) {
                        $items[] = ['label' => substr($name, strrpos($name, '\\') + 1 ?: 0), 'full' => $name];
                    }
                }
            }
        }
        heron_out(array_slice($items, 0, 5000));
    default:
        $items = [];
        $functions = get_defined_functions();
        foreach ($functions['internal'] as $name) {
            try {
                $params = heron_param_list(new ReflectionFunction($name));
            } catch (Throwable) {
                $params = [];
            }
            $items[] = ['label' => $name, 'kind' => 'function', 'detail' => 'PHP', 'insert' => $name . ($params ? '(' : '()'),
                'returns' => null, 'params' => $params];
        }
        if ($isLaravel) {
            $helpers = ['collect' => 'Illuminate\\Support\\Collection', 'now' => 'Illuminate\\Support\\Carbon',
                'today' => 'Illuminate\\Support\\Carbon', 'app' => 'Illuminate\\Foundation\\Application',
                'config' => null, 'env' => null, 'route' => null, 'url' => null, 'view' => 'Illuminate\\View\\View',
                'auth' => 'Illuminate\\Auth\\AuthManager', 'request' => 'Illuminate\\Http\\Request',
                'response' => null, 'redirect' => null, 'str' => 'Illuminate\\Support\\Stringable',
                'cache' => null, 'session' => null, 'logger' => null, 'event' => null, 'dispatch' => null,
                'resolve' => null, 'value' => null, 'tap' => null, 'with' => null, 'dd' => null, 'dump' => null,
                'abort' => null, 'base_path' => null, 'storage_path' => null, 'database_path' => null, 'public_path' => null,
                'resource_path' => null, 'asset' => null, 'trans' => null, '__' => null, 'fake' => null, 'bcrypt' => null,
                'old' => null, 'back' => null, 'policy' => null, 'rescue' => null, 'retry' => null, 'throw_if' => null,
                'throw_unless' => null, 'blank' => null, 'filled' => null, 'optional' => null, 'data_get' => null,
                'data_set' => null, 'head' => null, 'last' => null, 'e' => null, 'class_basename' => null];
            foreach ($helpers as $name => $returns) {
                if (function_exists($name)) {
                    $params = heron_param_list(new ReflectionFunction($name));
                    $items[] = ['label' => $name, 'kind' => 'function', 'detail' => 'Laravel',
                        'insert' => $name . ($params ? '(' : '()'), 'returns' => $returns, 'params' => $params];
                }
            }
        }
        heron_out($items);
}
