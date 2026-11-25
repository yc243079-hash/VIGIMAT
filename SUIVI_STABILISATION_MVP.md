# VIGIMAT — Suivi de Stabilisation et Corrections du MVP

**Date de début :** 25/11/2026  
**Objectif prioritaire :** Stabiliser le MVP en local avant tout déploiement.  
**Cible de test :** Téléphone physique Android (liaison câble USB) + Émulateur Android Studio en local (pour valider le découplage des bases SQLite locales et la synchronisation via Supabase).

---

## 1. Diagnostic des Problèmes Identifiés

### 1.1 Bug de synchronisation des actions du Chef
- **Constat utilisateur :** Lorsque le chef change l'état d'un signalement (`new` ➔ `waiting`, `assigned`, etc.), affecte un technicien ou ajoute un motif, rien n'est répercuté dans Supabase. Les modifications semblent appliquées dans l'application car SQLite local est mis à jour immédiatement, mais la synchronisation distante n'aboutit pas et aucun statut de sync n'est visible sur l'écran Chef.
- **Causes techniques identifiées :**
  1. **Contrainte SQL bloquante :** Dans `supabase/schema.sql`, la contrainte `maintenance_reports_assignment_deadline_check` impose :
     ```sql
     CHECK (assigned_technician_id IS NULL OR intervention_due_at IS NOT NULL)
     ```
     La modale d'affectation du chef ne renseigne pas systématiquement `intervention_due_at`, ce qui fait échouer la transaction côté PostgreSQL avec une violation de contrainte.
  2. **Gestion d'erreur muette dans `ReportSyncService` :**
     Dans `_syncAction`, le bloc `catch(error)` capture l'erreur PostgreSQL, met à jour l'action locale en `failed`, mais n'émet pas d'exception remontée à l'UI.
  3. **Absence d'indicateur de synchronisation sur l'écran Chef :**
     Contrairement à l'écran technicien ou soldat, les cartes de l'écran Chef n'affichent pas le badge d'état de synchronisation (`pending`, `syncing`, `sent`, `failed`). Le chef ne peut donc pas savoir si son action est encore en attente, réussie ou en échec.

### 1.2 Problème de verrouillage PostgreSQL
- L'utilisation de `pg_advisory_lock` au lieu de `pg_advisory_xact_lock` sans `pg_advisory_unlock` retient le verrou de session au niveau de la connexion poolée Supavisor, ce qui peut bloquer les requêtes suivantes.

---

## 2. État de l'Environnement Local

| Composant | Statut | Emplacement / Détails |
| :--- | :--- | :--- |
| **Flutter SDK** | ✅ Opérationnel (3.50.1 / Dart 3.14.0) | `C:\Users\ymd\flutter\bin` |
| **Android SDK & ADB** | ✅ Opérationnel | `C:\Users\ymd\AppData\Local\Android\Sdk\platform-tools\adb.exe` |
| **Émulateur Android Studio** | ✅ En cours d'exécution (`device`) | `Medium_Phone_API_37.0` (ID: `emulator-5554`) |
| **Téléphone externe (USB)** | ✅ Autorisé et connecté (`device`) | `Samsung Galaxy A12s` (ID: `RZ8R90GNTWE`) |
| **Runtime de script DB** | ✅ Node.js v26.8.1 & npm v11.19.0 | Prêt |

---

## 3. Plan d'Action par Étapes

### Étape 1 : Finalisation de l'environnement de test (Émulateur + Téléphone USB)
- [x] Détection du SDK Android et de l'outil ADB.
- [x] Ajout de Flutter et ADB au PATH Windows utilisateur.
- [x] Téléphone physique Android détecté (`Samsung SM-A127F`, ID: `RZ8R90GNTWE`).
- [x] Autorisation du débogage USB sur l'écran du téléphone validée.
- [x] Compilation de l'APK debug terminée avec succès (`app-debug.apk`).
- [x] Installation et ouverture automatique de l'application sur le téléphone Samsung.
- [ ] Lancement de la fenêtre visible de l'émulateur Android Studio (`Medium_Phone_API_37.0`) via le raccourci `LANCER_EMULATEUR.bat`.

### Étape 2 : Réinitialisation et Schéma de la Base Supabase
- [x] Créer le schéma SQL consolidé `supabase/01_consolidated_clean_schema.sql` (sans contrainte bloquante, avec unité `UNITE-01` et 3 comptes de test).
- [x] Schéma consolidé appliqué sur le projet Supabase.
- [x] Comptes de test configurés (`soldat@test.com`, `chef@test.com`, `technicien@test.com`).

### Étape 3 : Correction de la Synchronisation et du Code Flutter
- [x] **Remontée d'erreurs :** Correction de `ReportSyncService._syncAction` et `_syncReport` pour émettre les erreurs via `onError(error)` au lieu de les avaler silencieusement.
- [x] **Visibilité UI de la synchronisation (Chef) :**
  - Ajout des badges d'état (`Synchronisé`, `En attente`, `En cours`, `Échec sync`) sur chaque carte de signalement.
  - Message SnackBar précis affichant l'erreur exacte renvoyée par Supabase en cas d'échec.
- [x] **Validation des tests locaux :** Tous les tests unitaires et widget passent (`flutter test` : 8/8 validés).

### Étape 4 : Validation Croisée Bout-en-Bout
- [x] Test 1 : Le Soldat crée un signalement sur le Téléphone (photos, GPS, vocal) ➔ Validé avec succès.
- [x] Test 2 : Synchronisation vers Supabase vérifiée ➔ Validé avec succès.
- [x] Test 3 : Le Chef reçoit le signalement, affecte le Technicien avec observation ➔ Validé avec succès (`assign` & `chief_update`).
- [x] Test 4 : Le Technicien prend en charge et déclare la fin de réparation (`repaired_pending_validation`) ➔ Validé avec succès.
- [x] Test 5 : Le Chef valide la réparation et clôture le ticket (`validate` ➔ `closed`) ➔ Synchronisé dans Supabase.
- [x] **Correction 2 erreurs de clôture / validation :**
  1. **Idempotence SQL `apply_maintenance_report_action` :** Si un ticket est déjà clôturé (`status = 'closed'`), la ré-exécution ou modification d'observation par le chef est acceptée sans lever l'erreur `P0001` (`supabase/02_fix_apply_action_idempotence.sql`).
  2. **Verrou de synchronisation globale & SQLite transaction collision :** Ajout d'un mutex global `_activeGlobalSync` dans `ReportSyncService` et remplacement des transactions imbriquées dans `updateActionState` par des `update` atomiques pour éliminer `DatabaseException(Cannot perform this operation because there is no current transaction.) sql 'COMMIT'`.

---

## 4. Journal des Modifications et Avancement

- **25/11/2026 - Icône d'Application, Visionneuse Photos & Correctif Priorité :**
  - **Correctif d'erreur de synchronisation (priorité `Élevée` / `Haute`) :** La contrainte SQL PostgreSQL `maintenance_reports_priority_check` attendait `'Haute'` alors que l'UI envoyait `'Élevée'`. Résolu par la création de `supabase/03_fix_priority_constraint.sql` pour élargir la contrainte et l'ajout de `MaintenanceReport.normalizePriority()` dans l'application pour convertir automatiquement en amont.
  - **Icône de l'Application (Launcher Icon Android) :** Remplacement de l'icône par défaut Flutter par l'icône officielle tactique VIGIMAT (bouclier hexagonal, armure émeraude, grand V aérodynamique et ruban Mali) générée pour toutes les densités Android (`mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`).
  - **Visionneuse Photos Plein Écran Interactive (`VigimatImageViewer`) :** Implémentation de `lib/widgets/vigimat_image_viewer.dart` permettant d'ouvrir n'importe quelle photo locale ou distante d'un simple clic avec zoom tactile multipoint (pinch-to-zoom jusqu'à 4.5x), déplacement panoramique (pan), carrousel multi-photos et barre d'outils immersive.
  - **Correction du débordement d'affichage (Wrap responsive) :** Remplacement des `Row` statiques par des conteneurs adaptatifs `Wrap` sur les cartes du soldat, du chef et du technicien pour éviter tout débordement de pixels sur les libellés longs.
  - **Déploiement et validation :** Nouvelle compilation APK debug réussie et déploiement simultané sur le nouveau téléphone Samsung Galaxy A16 (`RFGL70CCGEZ`) et l'émulateur (`emulator-5554`).

- **25/11/2026 - Modernisation Complète UX/UI & Design System Tactique :**
  - Création du Design System modulaire et réutilisable (`lib/core/theme/` et `lib/widgets/`).
  - Intégration du logo officiel vectoriel `VigimatLogo` (bouclier tactique, chevron V aérodynamique, clé de maintenance, balise radar et trinité FAMa).
  - Refonte complète de tous les écrans : Login (avec hero card FAMa préservée + switchers de test), Dashboard Soldat, Dashboard Chef, Dashboard Technicien, Formulaire de signalement multimodal et Écran de Suivi avec timeline verticale.
  - Résolution des erreurs résiduelles de synchronisation (`P0001` idempotence SQL et collision SQLite `COMMIT`).
  - Tests unitaires et responsive validés (8/8 passés) et analyse statique 100% propre (0 issue).
  - Déploiement et validation croisée en direct sur le téléphone physique Samsung (`RFGL70CCGEZ`) et l'émulateur Android Studio (`emulator-5554`).

---

## 5. Architecture du Design System et UI Kit Réutilisable

Le projet intègre désormais une architecture UI professionnelle, centralisée et extensible, permettant d'ajouter ou faire évoluer des fonctionnalités très facilement.

### 5.1 Tokens et Thème (`lib/core/theme/`)
- **`VigimatColors` (`vigimat_colors.dart`)** :
  - **Identité Principale :** Bleu Marine Tactique (`#0A192F`, `#132F52`), Vert Émeraude FAMa (`#059669`, `#10B981`), Turquoise Holographique (`#06B6D4`).
  - **Statuts Opérationnels :** Émeraude (Validé/Résolu), Or Tactique (En attente), Carmin (Critique/Avarie grave), Bleu Ciel (Nouveau).
  - **Couleurs de Rôles :** Soldat (Bleu `#2563EB`), Chef (Pourpre `#7C3AED`), Technicien (Teal `#0D9488`).
  - **Surfaces et Élévations :** Fonds clairs titane (`#F8FAFC`, `#F1F5F9`), ombres douces et lueurs néon (`cardShadow`, `glowShadow`).
- **`VigimatLogo` (`vigimat_logo.dart`)** :
  - Composant vectoriel haute résolution (`CustomPainter`), net de 24px à 512px.
  - Bouclier hexagonal blindé, chevron aérodynamique "V", clé d'intervention mécanique, balise d'état opérationnel et bandeau tricolore national Mali (Vert, Or, Rouge).

### 5.2 Bibliothèque de Composants Réutilisables (`lib/widgets/`)
| Composant | Fichier | Description & Usage |
| :--- | :--- | :--- |
| **`VigimatButton`** | `vigimat_button.dart` | Bouton tactile avec micro-animation d'enfoncement (`scale: 0.97`), retour haptique, 4 variantes (`primary`, `secondary`, `danger`, `ghost`), indicateur de chargement intégré et support des icônes avant/arrière. |
| **`VigimatCard`** | `vigimat_card.dart` | Carte conteneur standard avec bordure subtile, ombre douce, et bande latérale de priorité optionnelle (`accentColor` / `priorityStripeColor`). |
| **`VigimatMetricCard`** | `vigimat_card.dart` | Tuile KPI pour afficher les compteurs du dashboard avec icône dédiée, libellé et mise en valeur chiffrée. |
| **`VigimatTextField`** | `vigimat_text_field.dart` | Champ de saisie uniforme avec anneau de focus émeraude, icônes préfixe/suffixe, gestion automatique du masquage de mot de passe et support mode sombre/clair. |
| **`VigimatStatusBadge`** | `vigimat_badge.dart` | Pilule de statut opérationnel (Nouveau, Attente, Affecté, Réparé, Validé/Clôturé). |
| **`VigimatSyncBadge`** | `vigimat_badge.dart` | Indicateur visuel d'état de synchronisation cloud (Synchronisé, En attente, En cours, Échec). |
| **`VigimatPriorityBadge`** | `vigimat_badge.dart` | Badge visuel de niveau de criticité (Faible, Moyenne, Élevée, Critique). |
| **`VigimatHeader`** | `vigimat_header.dart` | En-tête tactique unifié avec logo vectoriel, badge de rôle (`Soldat`, `Chef`, `Technicien`), nom de la compagnie, bouton de synchronisation manuelle et avatar utilisateur. |
| **`VigimatEmptyState`** | `vigimat_empty_state.dart` | Vue d'état vide ergonomique avec illustration tactique, message explicatif et bouton d'action CTA. |

### 5.3 Écrans Modernisés
1. **Écran de Connexion (`auth_gate.dart`) :**
   - Conservation de l'image officielle FAMa (`vigimat_login_hero.png`) dans une carte flottante avec overlay HUD.
   - Bandeau national « UN PEUPLE – UN BUT – UNE FOI ».
   - Carte de formulaire en verre fumé avec logo vectoriel.
   - Puces d'accès rapide pour tests instantanés (`[👤 Soldat]`, `[🛡️ Chef d'Unité]`, `[🔧 Technicien]`).
2. **Dashboard Soldat (`soldier_home_page.dart`) :**
   - En-tête unifié `VigimatHeader`.
   - Carte héroïque d'action rapide pour déclaration immédiate d'avarie avec CTA émeraude.
   - Compteurs métriques KPI (Dossiers actifs, Clôturés/Validés).
   - Cartes de signalement avec bande de criticité latérale et badges synchronisés.
3. **Dashboard Chef d'Unité (`chief_dashboard_page.dart`) :**
   - Vue de commandement avec 3 KPI (À traiter, À valider, Clôturés).
   - Filtres horizontaux interactifs (`Tous`, `À traiter`, `À valider`, `Clôturés`).
   - Fiche modale de revue et décision avec mise en évidence du rapport technicien et boutons d'actions hiérarchiques.
4. **Dashboard Technicien (`reports_home_page.dart`) :**
   - Vue dédiée aux ordres de réparation avec filtres d'interventions.
5. **Formulaire de Signalement (`report_form_page.dart`) :**
   - Sections structurées : Identification matériel, Description de la panne, Sélecteur tactile de priorité (4 niveaux), Photos du matériel, Enregistreur vocal de bruit moteur, Géolocalisation GPS avec précision en mètres.
6. **Suivi Détaillé & Historique (`report_tracking_page.dart`) :**
   - Carte d'identité du matériel et métadonnées complètes.
   - Galerie photos du matériel et lecteur audio de la note vocale.
   - Journal chronologique vertical avec nœuds colorés par acteur/type d'événement (Soldat, Chef, Technicien, Blocage, Validation).

- **25/11/2026 - Initialisation & Corrections :**
  - Diagnostic complet : suppression de la contrainte bloquante `maintenance_reports_assignment_deadline_check`, sécurisation des verrous de transaction avec `FOR UPDATE`.
  - Intégration de la remontée d'erreur dans `ReportSyncService` et ajout des badges de synchronisation sur le tableau de bord du Chef.
  - Compilation réussie de l'APK debug avec variables d'environnement Supabase (`lib/core/env.json`).
  - Déploiement et exécution simultanée de l'application sur le téléphone physique Samsung et sur l'émulateur Android Studio.
