-- Schema + seed. Mots de passe stockes en PBKDF2-HMAC-SHA256 (600k iterations).
-- Aucun mot de passe en clair. Comptes de demonstration uniquement.
-- Donnees de sante : synthetiques, generees pour la demo (aucune donnee reelle).

CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'user'
);

CREATE TABLE health_data (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER REFERENCES users(id),
    heart_rate    INTEGER,
    fall_detected BOOLEAN NOT NULL DEFAULT false,
    posture       TEXT,
    recorded_at   TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO users (email, password_hash, role) VALUES
    ('admin@sl1pconnect.fr',        'pbkdf2_sha256$600000$Lzaxz3trOeVwJFAEi38T6Q==$begFw7tLfv6sBxXYCvCbZM9Z4VviIvgxtHzBUmu5T/U=', 'admin'),
    ('calvin.slipp@sl1pconnect.fr', 'pbkdf2_sha256$600000$fU35DPVgftf8CAqTMAixFg==$BzfydN51tFoJAlbWDgmnOMYw+lE+d5RRig/dLxDygfQ=', 'admin'),
    ('jean.dupont@example.com',     'pbkdf2_sha256$600000$sQcoMQNpE5dSZY2jRn5mRA==$z+Fnmr7XvAuIRgAMYt2k9KeghirJqw/UQVdK6qQILJw=', 'user'),
    ('marie.martin@example.com',    'pbkdf2_sha256$600000$VloahMznhiI7jF+9vlU2Pw==$82hbdyagRQXiWsMvZXA6X0ltmHY6vfBPa8SvU7GIF+o=', 'user');

-- Donnees synthetiques — 7 jours de suivi pour la demo Grafana
-- Jean Dupont (id=3) : profil actif, 30 ans, pic cardiaque en activite
-- Marie Martin (id=4) : profil seniorite, 72 ans, 2 chutes sur la periode

INSERT INTO health_data (user_id, heart_rate, fall_detected, posture, recorded_at) VALUES
-- Jean Dupont — jour -7
(3,  66, false, 'upright',  now() - interval '7 days 8 hours 30 minutes'),
(3, 118, false, 'walking',  now() - interval '7 days 6 hours 15 minutes'),
(3,  74, false, 'sitting',  now() - interval '7 days 4 hours 00 minutes'),
(3,  69, false, 'upright',  now() - interval '7 days 1 hour  10 minutes'),
-- Jean Dupont — jour -6
(3,  70, false, 'upright',  now() - interval '6 days 9 hours 00 minutes'),
(3, 125, false, 'walking',  now() - interval '6 days 7 hours 30 minutes'),
(3,  78, false, 'sitting',  now() - interval '6 days 5 hours 00 minutes'),
(3,  67, false, 'lying',    now() - interval '6 days 0 hours 45 minutes'),
-- Jean Dupont — jour -5
(3,  65, false, 'upright',  now() - interval '5 days 8 hours 00 minutes'),
(3,  88, false, 'walking',  now() - interval '5 days 6 hours 20 minutes'),
(3, 132, false, 'walking',  now() - interval '5 days 5 hours 00 minutes'),
(3,  75, false, 'sitting',  now() - interval '5 days 3 hours 10 minutes'),
(3,  71, false, 'upright',  now() - interval '5 days 1 hour  00 minutes'),
-- Jean Dupont — jour -4
(3,  68, false, 'upright',  now() - interval '4 days 9 hours 15 minutes'),
(3, 110, false, 'walking',  now() - interval '4 days 7 hours 00 minutes'),
(3,  80, false, 'sitting',  now() - interval '4 days 4 hours 30 minutes'),
(3,  73, false, 'upright',  now() - interval '4 days 2 hours 00 minutes'),
-- Jean Dupont — jour -3
(3,  70, false, 'upright',  now() - interval '3 days 8 hours 45 minutes'),
(3, 121, false, 'walking',  now() - interval '3 days 6 hours 30 minutes'),
(3,  76, false, 'sitting',  now() - interval '3 days 3 hours 00 minutes'),
-- Jean Dupont — jour -2
(3,  67, false, 'upright',  now() - interval '2 days 9 hours 00 minutes'),
(3,  94, false, 'walking',  now() - interval '2 days 7 hours 10 minutes'),
(3,  72, false, 'sitting',  now() - interval '2 days 5 hours 20 minutes'),
(3,  69, false, 'upright',  now() - interval '2 days 1 hour  15 minutes'),
-- Jean Dupont — jour -1
(3,  71, false, 'upright',  now() - interval '1 day  8 hours 00 minutes'),
(3, 108, false, 'walking',  now() - interval '1 day  6 hours 30 minutes'),
(3,  77, false, 'sitting',  now() - interval '1 day  3 hours 00 minutes'),
-- Marie Martin — jour -7
(4,  64, false, 'lying',    now() - interval '7 days 9 hours 00 minutes'),
(4,  71, false, 'sitting',  now() - interval '7 days 7 hours 30 minutes'),
(4,  68, false, 'upright',  now() - interval '7 days 5 hours 00 minutes'),
-- Marie Martin — jour -6
(4,  66, false, 'sitting',  now() - interval '6 days 8 hours 00 minutes'),
(4,  73, false, 'upright',  now() - interval '6 days 6 hours 15 minutes'),
(4,  62, false, 'lying',    now() - interval '6 days 1 hour  00 minutes'),
-- Marie Martin — jour -5 : premiere chute
(4,  78, false, 'upright',  now() - interval '5 days 9 hours 30 minutes'),
(4,  95, true,  'lying',    now() - interval '5 days 8 hours 45 minutes'),
(4,  69, false, 'sitting',  now() - interval '5 days 6 hours 00 minutes'),
(4,  65, false, 'lying',    now() - interval '5 days 1 hour  30 minutes'),
-- Marie Martin — jour -4
(4,  67, false, 'sitting',  now() - interval '4 days 8 hours 00 minutes'),
(4,  72, false, 'upright',  now() - interval '4 days 6 hours 30 minutes'),
(4,  63, false, 'lying',    now() - interval '4 days 1 hour  00 minutes'),
-- Marie Martin — jour -3 : deuxieme chute
(4,  70, false, 'upright',  now() - interval '3 days 9 hours 00 minutes'),
(4,  88, true,  'lying',    now() - interval '3 days 8 hours 15 minutes'),
(4,  66, false, 'sitting',  now() - interval '3 days 5 hours 30 minutes'),
-- Marie Martin — jour -2
(4,  64, false, 'sitting',  now() - interval '2 days 8 hours 45 minutes'),
(4,  71, false, 'upright',  now() - interval '2 days 7 hours 00 minutes'),
(4,  60, false, 'lying',    now() - interval '2 days 1 hour  20 minutes'),
-- Marie Martin — jour -1
(4,  68, false, 'sitting',  now() - interval '1 day  9 hours 00 minutes'),
(4,  75, false, 'upright',  now() - interval '1 day  7 hours 15 minutes'),
(4,  63, false, 'lying',    now() - interval '1 day  2 hours 00 minutes');
