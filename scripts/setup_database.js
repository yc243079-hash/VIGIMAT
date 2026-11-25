/**
 * VIGIMAT — Exécuteur automatique du schéma Supabase
 *
 * Ce script permet d'appliquer le schéma SQL consolidé directement à la base
 * Supabase sans passer par le SQL Editor web de Supabase.
 *
 * Utilisation :
 *   node scripts/setup_database.js [DATABASE_URL]
 *
 * Exemples :
 *   node scripts/setup_database.js postgresql://postgres.rgqsczrgrchicgpyhola:[VOTRE_MOT_DE_PASSE]@aws-0-eu-central-1.pooler.supabase.com:6543/postgres
 *   ou définir la variable d'environnement DATABASE_URL :
 *   $env:DATABASE_URL="postgresql://postgres:motdepasse@db.rgqsczrgrchicgpyhola.supabase.co:5432/postgres"
 *   node scripts/setup_database.js
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

async function run() {
  const connectionString =
    process.argv[2] ||
    process.env.DATABASE_URL ||
    process.env.SUPABASE_DB_URL;

  if (!connectionString) {
    console.error(`
[ERREUR] URL de connexion PostgreSQL manquante.

Veuillez fournir la chaîne de connexion directe PostgreSQL (trouvable dans votre projet Supabase > Settings > Database > Connection string) :
  
  node scripts/setup_database.js "postgresql://postgres:[MOT_DE_PASSE]@db.rgqsczrgrchicgpyhola.supabase.co:5432/postgres"
  ou via le connection pooler (port 6543) :
  node scripts/setup_database.js "postgresql://postgres.rgqsczrgrchicgpyhola:[MOT_DE_PASSE]@aws-0-[REGION].pooler.supabase.com:6543/postgres"
    `);
    process.exit(1);
  }

  const sqlFilePath = path.join(__dirname, '..', 'supabase', '01_consolidated_clean_schema.sql');
  if (!fs.existsSync(sqlFilePath)) {
    console.error(`[ERREUR] Fichier SQL introuvable : ${sqlFilePath}`);
    process.exit(1);
  }

  const sql = fs.readFileSync(sqlFilePath, 'utf8');
  console.log(`[INFO] Connexion à Supabase PostgreSQL...`);

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
  });

  try {
    await client.connect();
    console.log(`[SUCCÈS] Connecté à la base de données.`);
    console.log(`[INFO] Exécution de 01_consolidated_clean_schema.sql...`);

    await client.query(sql);

    console.log(`\n=============================================================`);
    console.log(`[SUCCÈS TOTAL] La base Supabase VIGIMAT est configurée !`);
    console.log(`=============================================================`);
    console.log(`1. Tables recréées : maintenance_units, maintenance_reports, history, receipts.`);
    console.log(`2. RPCs configurées : create_maintenance_report, apply_maintenance_report_action, etc.`);
    console.log(`3. Bucket privé configuré : report-attachments.`);
    console.log(`4. Comptes de test initialisés (mot de passe : "Test1234!") :`);
    console.log(`   - Soldat     : soldat@test.com     (role: soldier)`);
    console.log(`   - Chef       : chef@test.com       (role: unit_head)`);
    console.log(`   - Technicien : technicien@test.com (role: technician)`);
    console.log(`=============================================================\n`);
  } catch (err) {
    console.error(`[ERREUR LORS DE L'EXÉCUTION DU SQL] :`, err.message);
    if (err.detail) console.error(`Détail :`, err.detail);
    if (err.hint) console.error(`Indice :`, err.hint);
    process.exit(1);
  } finally {
    await client.end();
  }
}

run();
