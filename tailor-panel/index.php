<?php
function read_secret($name, $default = null) {
    $path = getenv($name . '_FILE');
    if ($path && is_file($path)) {
        return trim(file_get_contents($path));
    }
    $val = getenv($name);
    return $val !== false ? $val : $default;
}

$host = getenv('DB_HOST') ?: 'db-velvet';
$db   = getenv('DB_NAME') ?: 'velvet';
$user = getenv('DB_USER') ?: 'velvet';
$pass = read_secret('DB_PASSWORD');
$port = getenv('DB_PORT') ?: '5432';

$pdo = null;
for ($i = 0; $i < 15; $i++) {
    try {
        $pdo = new PDO("pgsql:host=$host;port=$port;dbname=$db", $user, $pass,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        break;
    } catch (Exception $e) {
        sleep(2);
    }
}

function verify_password($stored, $password) {
    $p = explode('$', (string)$stored);
    if (count($p) !== 4 || $p[0] !== 'pbkdf2_sha256') {
        return false;
    }
    $iter = (int)$p[1];
    $salt = base64_decode($p[2]);
    $expected = base64_decode($p[3]);
    $dk = hash_pbkdf2('sha256', $password, $salt, $iter, 0, true);
    return hash_equals($expected, $dk);
}

session_set_cookie_params(['httponly' => true, 'secure' => true, 'samesite' => 'Strict']);
session_start();
if (empty($_SESSION['csrf'])) {
    $_SESSION['csrf'] = bin2hex(random_bytes(16));
}

$error = '';
if (isset($_POST['login'])) {
    if (!hash_equals($_SESSION['csrf'], $_POST['csrf'] ?? '')) {
        $error = 'Jeton CSRF invalide';
    } else {
        $stmt = $pdo->prepare(
            "SELECT id, role, password_hash FROM users WHERE email = :e AND role = 'admin'");
        $stmt->execute([':e' => $_POST['username'] ?? '']);
        $u = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($u && verify_password($u['password_hash'], $_POST['password'] ?? '')) {
            session_regenerate_id(true);
            $_SESSION['auth'] = true;
        } else {
            $error = 'Identifiants invalides';
        }
    }
}
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: /');
    exit;
}

function h($s) { return htmlspecialchars((string)($s ?? ''), ENT_QUOTES); }
?>
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>SL1P Tailor Panel</title>
<style>
 body{font-family:system-ui,sans-serif;margin:2rem auto;max-width:820px;color:#222}
 h1{color:#1F3864} table{border-collapse:collapse;width:100%;margin-top:1rem}
 td,th{border:1px solid #ccc;padding:6px;text-align:left}
 input{padding:6px;margin-right:.3rem} button{padding:6px 12px}
</style>
</head>
<body>
<h1>SL1PCONNECT &mdash; Back-office (tailor-panel)</h1>

<?php if (empty($_SESSION['auth'])): ?>
  <?php if ($error) echo "<p style='color:#C00000'>" . h($error) . "</p>"; ?>
  <form method="post">
    <input type="hidden" name="csrf" value="<?php echo h($_SESSION['csrf']); ?>">
    <input name="username" placeholder="email">
    <input name="password" type="password" placeholder="mot de passe">
    <button name="login" value="1">Connexion</button>
  </form>
<?php else: ?>
  <p><a href="?logout=1">Deconnexion</a></p>
  <h2>Recherche d'utilisateurs</h2>
  <form method="get">
    <input name="q" value="<?php echo h($_GET['q'] ?? ''); ?>" placeholder="email...">
    <button>Rechercher</button>
  </form>
  <?php
    $q = $_GET['q'] ?? '';
    try {
        $stmt = $pdo->prepare(
            "SELECT id, email, role FROM users WHERE email LIKE :q ORDER BY id");
        $stmt->execute([':q' => '%' . $q . '%']);
        echo "<table><tr><th>id</th><th>email</th><th>role</th></tr>";
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            echo "<tr><td>" . h($r['id']) . "</td><td>" . h($r['email']) .
                 "</td><td>" . h($r['role']) . "</td></tr>";
        }
        echo "</table>";
    } catch (Exception $e) {
        echo "<p style='color:#C00000'>Erreur lors de la recherche.</p>";
    }
  ?>
<?php endif; ?>
</body>
</html>
