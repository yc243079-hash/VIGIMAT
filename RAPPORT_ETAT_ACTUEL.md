# RAPPORT D'ÉTAT ACTUEL — PROJET VIGIMAT

**Date :** 25/11/2026  
**Branche Git :** `redesign-interface` (commit `d57faf5`)  
**Statut :** Corrections apportées, APK construit, tests fonctionnels en attente  
**Aucun commit ni push n'a été effectué sur le dépôt distant**

---

## 1. ARCHITECTURE GÉNÉRALE

### Stack technique
| Couche | Technologie | Version | Rôle |
|--------|-------------|---------|------|
| Framework | Flutter | 3.47.9 (stable) | UI cross-platform |
| Langage | Dart | 3.13.7 | Logique applicative |
| Base de données locale | SQLite (via `sqflite`) | 2.4.6 | Stockage hors ligne, cache |
| Base de données distante | Supabase (PostgreSQL) | — | Données partagées, RLS, synchronisation |
| Synchronisation réseau | `connectivity_plus` | 7.3.2 | Détection de connectivité |
| Géolocalisation | `geolocator` | 14.0.1 | Capture GPS |
| Médias (photos) | `image_picker` | 1.2.4 | Sélection/capture photo |
| Médias (audio) | `record` + `audioplayers` | 7.2.0 / 6.8.1 | Enregistrement/lecture vocal |
| QR Code | `qr_flutter` + `mobile_scanner` | 4.1.0 / 7.5.0 | Génération et scan QR |
| Notifications push | Firebase (FCM) | 5.1.0 / 17.0.1 | Push notifications (reporté post-MVP) |
| Notifications locales | `flutter_local_notifications` | 23.0.2 | Notifications en foreground |
| Sync arrière-plan | `workmanager` | 0.10.10 | Tâche de sync différée Android |
| Identifiants | `uuid` | 4.6.0 | Génération d'IDs uniques |

### Structure du projet (`lib/`)
```
lib/
├── main.dart                      # Point d'entrée, initialisation Supabase + Workmanager
├── core/
│   ├── supabase_config.dart       # Clés Supabase via String.fromEnvironment
│   ├── firebase_config.dart       # Clés Firebase via String.fromEnvironment
│   ├── vigimat_brand.dart         # Palette, logo, bandeaux partagés
│   └── mali_identity.dart         # Drapeau et devise du Mali
├── models/
│   ├── app_user_profile.dart      # Profil utilisateur (rôle, unité, matricule)
│   ├── maintenance_report.dart    # Modèle de rapport avec état de sync + mergeRemote
│   ├── dashboard_snapshot.dart    # Indicateurs du tableau de bord
│   ├── equipment.dart             # Inventaire d'équipement
│   └── app_notification.dart      # Modèle de notification
├── services/
│   ├── local_report_store.dart    # Accès SQLite (CRUD, historique, file d'actions)
│   ├── report_sync_service.dart   # Synchronisation Supabase (rapports, pièces jointes, actions)
│   ├── app_profile_service.dart   # Chargement du profil via RPC Supabase + cache
│   ├── background_sync.dart       # Planification workmanager
│   ├── background_sync_worker.dart # Point d'entrée worker arrière-plan
│   ├── dashboard_service.dart     # Indicateurs via RPC Supabase
│   ├── equipment_repository.dart  # Inventaire et scan QR
│   ├── notification_repository.dart # Notifications Supabase
│   └── push_notification_service.dart # Firebase FCM + notifications locales
└── features/
    ├── auth/                      # AuthGate (connexion, routage par rôle)
    ├── soldier/                   # Espace soldat (signalement, lecture seule)
    ├── chief/                     # Espace chef d'unité (affectation, validation)
    ├── home/                      # Espace technicien (affectations, suivi)
    ├── reports/                   # Formulaire de signalement, suivi détaillé
    ├── dashboard/                 # Tableau de bord avec graphiques CustomPainter
    ├── equipment/                 # Inventaire, fiche, édition, scan QR
    ├── maintenance/               # Centre de maintenance (entretiens, historique, stock démo)
    ├── notifications/             # Centre de notifications
    └── profile/                   # Profil et déconnexion
```

## 2. MODÈLE DE DONNÉES SUPABASE

### Tables principales
- `maintenance_units` — Unités de maintenance (code, nom, active)
- `maintenance_reports` — Rapports de maintenance (statut, affectation, technicien, soldat, etc.)
- `maintenance_report_history` — Historique des modifications (audit)
- `maintenance_report_action_receipts` — Réception des actions (idempotence)
- `equipment_inventory` — Inventaire des équipements
- `preventive_maintenance_schedules` — Entretiens préventifs
- `user_notifications` — Notifications utilisateur
- `user_push_tokens` — Tokens de push

### Stockage (buckets)
- `report-attachments` (privé, 20 Mo max) — Pièces jointes des rapports
- `equipment-photos` (privé) — Photos des équipements

### Fonctions RPC clés
- `get_my_app_profile()` — Récupère le profil utilisateur (rôle, unité)
- `get_assignable_technicians()` — Liste des techniciens d'une unité (chef seulement)
- `create_maintenance_report(p_report jsonb)` — Crée un rapport (soldat seulement)
- `set_maintenance_report_attachments(...)` — Upload des pièces jointes
- `apply_maintenance_report_action(...)` — Affectation, changement de statut, réparation, validation (chef/technicien)

### Sécurité (RLS)
- Row Level Security activé sur toutes les tables
- Politiques restrictives par rôle (`soldier`, `technician`, `unit_head`) via `raw_app_meta_data`
- Fonctions `security definer` pour les opérations sensibles


## 3. CORRECTIONS APPORTÉES (ÉTAT ACTUEL)

### 3.1 Correction SQL — Fonction `apply_maintenance_report_action`
**Fichier :** `supabase/migrations/202611240001_vigimat_mvp_roles_offline.sql`  
**Problème :** `pg_advisory_xact_lock()` nécessite une transaction explicite, provoquant l'erreur PostgreSQL `Can't perform this operation because there is no current transaction`.  
**Correction :** Remplacé par `pg_advisory_lock()` (niveau session, ne requiert pas de transaction explicite).  
**Lignes modifiées :** Ligne 366 du fichier migration.

### 3.2 Correction Dart — `chief_dashboard_page.dart`
**Problème :** Après l'enregistrement d'une action (affectation, changement de statut), la feuille modale se fermait immédiatement (`Navigator.pop`) sans attendre la fin de la synchronisation. L'action restait en local SQLite sans être envoyée à Supabase. Aucun indicateur visuel n'avertissait l'utilisateur.  
**Correction :**
1. `syncPending()` est appelé de manière bloquante (`await`) après `enqueueAction`.
2. Après le sync, on vérifie via `getPendingActions()` que l'action n'est plus en attente locale.
3. Si l'action reste en attente, un message d'erreur s'affiche (`Synchronisation échouée...`) et la feuille modale ne se ferme pas.
4. En cas d'erreur de sync, un message explicite est affiché à l'utilisateur.

### 3.3 Correction Dart — `maintenance_report.dart`
**Problème :** `mergeRemote()` écrasait les modifications locales en attente (statut, technicien affecté, notes de réparation) par l'ancienne version distante au rechargement du rapport.  
**Correction :** Lorsque `syncState` est `pending` ou `syncing`, les valeurs locales des champs de workflow sont conservées (statut, assignedTechnicianId, interventionDueAt, repairNote, waitingReason). Les valeurs distantes ne prévalent que lorsque le rapport est synchronisé.

### 3.4 Configuration locale — `supabase.local.env` et `.gitignore`
- Fichier `supabase.local.env` créé avec `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY` (valeurs réelles injectées via `--dart-define-from-file`).
- `.gitignore` mis à jour pour exclure `supabase.local.env` (les clés ne doivent pas être commitées).

### 3.5 Fichiers non touchés (préservés)
- Aucun fichier n'a été supprimé.
- Aucune base SQLite n'a été réinitialisée.
- Aucun commit ni push n'a été effectué.


## 4. CONFIGURATION SUPABASE — ÉTAT ACTUEL

### Projet
- **URL :** `https://rgqsczrgrchicgpyhola.supabase.co`
- **Clé publique (publishable) :** Configurée via `supabase.local.env` (non exposée ici)
- **Statut :** Projet accessible, schéma appliqué

### Base de données
Les scripts suivants ont été appliqués :
1. `supabase/schema.sql` — Schéma de base (tables, RLS, fonctions, triggers, buckets)
2. `supabase/migrations/202611240001_vigimat_mvp_roles_offline.sql` — Migration additive (unités, rôles, politiques MVP, fonction `apply_maintenance_report_action`)

### Comptes de test créés
L'utilisateur a confirmé que le script SQL d'initialisation a fonctionné. Les 3 comptes suivants doivent exister dans `auth.users` avec les métadonnées appropriées :

| Email | Rôle | Unité |
|-------|------|-------|
| soldat@test.com | soldier | UUID_UNIT_001 |
| technicien@test.com | technician | UUID_UNIT_001 |
| chef@test.com | unit_head | UUID_UNIT_001 |

> **Note :** Les métadonnées (`raw_app_meta_data`) doivent contenir `role` et `unit_id` pour que les fonctions SQL et le routage Flutter fonctionnent.

### Données observées dans Supabase (dernière vérification)
La requête suivante retourne 2 lignes :
```sql
SELECT id, reference, equipment_name, status, reporter_id, assigned_technician_id
FROM public.maintenance_reports
ORDER BY created_at DESC
LIMIT 20;
```
Résultat :
| reference | equipment_name | status | reporter_id | assigned_technician_id |
|-----------|---------------|--------|-------------|------------------------|
| SIG-41B27CBE6D65495494F1D54EB1318604 | VR12 | repaired_pending_validation | 8ae8509e... | NULL |
| SIG-CBD4DA2462764C61BDE01 | Toyota YD V0001 | waiting | 8ae8509e... | NULL |

**Observation :** Aucun rapport n'a `assigned_technician_id` renseigné. Les affectations du chef ne sont pas encore arrivées dans Supabase.

## 5. CE QUI FONCTIONNE DÉJÀ (validé ou implémenté)

| Fonctionnalité | Rôle | Statut |
|----------------|------|--------|
| Authentification email/mot de passe | Tous | ✅ Implémenté |
| Routage automatique par rôle (soldier/technician/unit_head) | Tous | ✅ Implémenté |
| Chargement du profil avec cache SQLite hors ligne | Tous | ✅ Implémenté |
| Création de signalement (texte, vocal, photos, GPS, véhicule) | Soldat | ✅ Implémenté |
| Sauvegarde locale immédiate (SQLite, état `pending`) | Soldat | ✅ Implémenté |
| Synchronisation des rapports vers Supabase (`create_maintenance_report`) | Soldat | ✅ Fonctionne (rapports présents dans Supabase) |
| Consultation des rapports propres | Soldat | ✅ Implémenté (lecture seule) |
| Consultation des affectations | Technicien | ✅ Implémenté (écran affiché) |
| Déclarer réparation terminée / blocage | Technicien | ✅ Implémenté (écran affiché) |
| Consulter les rapports de l'unité | Chef d'unité | ✅ Implémenté (rapports visibles) |
| Affecter un technicien à un rapport | Chef d'unité | ✅ Implémenté en local, ❌ sync non vérifié |
| Mettre à jour le statut / valider une réparation | Chef d'unité | ✅ Implémenté en local, ❌ sync non vérifié |
| File d'attente d'actions avec versionning optimiste | Tous | ✅ Implémenté |
| Sync automatique au retour du réseau | Tous | ✅ Implémenté (connectivity_plus) |
| Sync arrière-plan WorkManager | Tous | ✅ Implémenté |
| Inventaire d'équipement + scan QR | Tous | ✅ Implémenté |
| Notifications push FCM (code) | Tous | ✅ Implémenté (non testé, reporté post-MVP) |
| Centre de notifications | Tous | ✅ Implémenté |
| Tableau de bord avec indicateurs | Chef / Technicien | ✅ Implémenté |
| Profil + déconnexion | Tous | ✅ Implémenté |
| Build APK debug | — | ✅ Réussi (3 builds effectués) |

