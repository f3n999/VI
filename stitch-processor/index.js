const fs = require("fs");
const crypto = require("crypto");
const express = require("express");
const { Pool } = require("pg");

function readSecret(name, def) {
  const fp = process.env[name + "_FILE"];
  if (fp && fs.existsSync(fp)) return fs.readFileSync(fp, "utf8").trim();
  return process.env[name] || def;
}

const API_KEY = readSecret("API_KEY");

const pool = new Pool({
  host: process.env.DB_HOST || "db-velvet",
  database: process.env.DB_NAME || "velvet",
  user: process.env.DB_USER || "velvet",
  password: readSecret("DB_PASSWORD"),
  port: parseInt(process.env.DB_PORT || "5432", 10),
});

const app = express();
app.use(express.json());

// Sonde de sante : non protegee (utilisee par le healthcheck).
app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "stitch-processor" });
});

// Defense en profondeur : cle API en temps constant (le service est deja
// isole sur le reseau interne, non expose).
app.use((req, res, next) => {
  const provided = Buffer.from(req.get("X-API-Key") || "");
  const expected = Buffer.from(API_KEY || "");
  if (
    !API_KEY ||
    provided.length !== expected.length ||
    !crypto.timingSafeEqual(provided, expected)
  ) {
    return res.status(401).json({ error: "unauthorized" });
  }
  next();
});

app.get("/process", async (req, res) => {
  try {
    const r = await pool.query(
      "SELECT user_id, heart_rate, fall_detected, posture FROM health_data ORDER BY id"
    );
    const out = r.rows.map((row) => {
      let risk = 0;
      if (row.fall_detected) risk += 50;
      if (row.heart_rate > 100 || row.heart_rate < 50) risk += 30;
      if (row.posture === "lying") risk += 20;
      return { user_id: row.user_id, risk_score: risk, alert: risk >= 50 };
    });
    res.json(out);
  } catch (e) {
    res.status(500).json({ error: "processing error" });
  }
});

app.get("/stats", async (req, res) => {
  try {
    const r = await pool.query("SELECT count(*)::int AS total FROM health_data");
    res.json({ total_records: r.rows[0].total });
  } catch (e) {
    res.status(500).json({ error: "processing error" });
  }
});

const PORT = parseInt(process.env.PORT || "8082", 10);
app.listen(PORT, "0.0.0.0", () => console.log("stitch-processor on " + PORT));
