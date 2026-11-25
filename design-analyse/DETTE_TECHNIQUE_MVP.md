# Dette technique actuelle — VIGIMAT

> **État initial avant corrections :** les constats ci-dessous décrivent le dépôt avant l’implémentation du parcours Android MVP. Pour les corrections déjà faites et l’état de validation le plus récent, voir [ETAT_MVP_ANDROID.md](ETAT_MVP_ANDROID.md).

**Audit du 24 novembre 2026**  
**But :** identifier ce qui bloque ou fragilise un MVP exploitable, sans lancer de refonte générale.

## Synthèse

La codebase contient déjà les principaux parcours métier (authentification par rôle, signalements avec médias, file locale, synchronisation, inventaire, suivi, notifications) et une base Supabase/RLS non triviale. Le README décrit correctement une grande partie du fonctionnement et les comptes de test ne sont pas codés en dur.

Le périmètre est maintenant clarifié : application native **Android uniquement**; rôles soldat déclarant, chef d’unité et technicien; rapports conservés localement et synchronisés avec Supabase au retour du réseau après une première connexion en ligne; texte, vocal, photos, véhicule/GPS et suivi de statuts. Le code actuel n’implémente pas encore le rôle soldat ni son lien au rapport. Les risques principaux sont ce décalage de rôles, la surface d’accès SQL trop large, la fiabilité de la synchronisation hors ligne et l’absence de build de publication validé.

## Niveau de validation observé

- SDK local déclaré dans le cache : Flutter 3.47.9, Dart 3.13.7.
- `dart analyze lib test` : **réussi**, `No issues found!`.
- `flutter test --no-pub` : **inconclusif**. La commande n’a produit aucune sortie après environ 110 secondes; elle a été interrompue. Ce n’est ni un échec de test, ni une suite validée.
- Pas de build Android release, de contrôle SQL sur une base staging, ni de déploiement exécuté dans cet audit.
- Le workspace contenait déjà des changements locaux dans `lib/core/vigimat_brand.dart`; les corrections proposées doivent les préserver.

## Dette classée par priorité

### P0 — À traiter avant une diffusion à des utilisateurs

#### P0.1 — Le modèle actuel n’inclut pas le rôle soldat déclarant

Le parcours métier désormais défini distingue le soldat qui signale, le chef d’unité qui affecte et valide, et le technicien qui répare. Le client et les politiques SQL ne connaissent actuellement que `technician` et `unit_head`. `maintenance_reports.technician_id` est obligatoire et sert de lien propriétaire, tandis que `reporter_name` n’est qu’un nom texte; le déclarant n’est donc pas associé à un compte soldat de façon fiable.

**Risque :** les rapports seraient attribués au mauvais rôle, et les permissions ne pourraient pas assurer que le chef voit son unité, que le technicien ne traite que ses affectations, et que le soldat ne change pas les statuts.

**Travail requis :** ajouter `soldier`, relier chaque rapport au compte déclarant et à son unité, séparer cette relation de l’affectation au technicien, puis migrer les données existantes avec sauvegarde et historique conservés. Le soldat doit pouvoir consulter ses propres signalements et leur historique en lecture seule, sans modifier leur statut.

**Références :** `lib/features/auth/auth_gate.dart`, `lib/models/maintenance_report.dart`, `supabase/schema.sql` (`maintenance_reports.technician_id`, `reporter_name`, politiques RLS).

#### P0.2 — Flux mobiles natifs pas encore validés en conditions réelles

La cible Android étant confirmée, `sqflite`, `path_provider` et `dart:io` correspondent au choix de plateforme. Les parcours critiques ne sont néanmoins pas couverts par des tests sur appareils : se connecter une première fois, créer un brouillon hors réseau, conserver photo et vocal, fermer/redémarrer l’application, retrouver le brouillon, puis synchroniser sans doublon. Les permissions, formats audio/photo et reprise d’envoi doivent être validés sur un téléphone Android réel.

**Risque :** le parcours principal peut sembler fonctionner en démonstration mais perdre ses médias ou rester bloqué après une interruption réseau ou un redémarrage.

**Références :** `lib/services/local_report_store.dart`, `lib/services/report_sync_service.dart`, `lib/features/reports/report_form_page.dart`, `lib/features/reports/report_tracking_page.dart`, `lib/features/home/reports_home_page.dart`.

#### P0.3 — Règles RLS trop larges pour le modèle à trois rôles

- `equipment_inventory` et `preventive_maintenance_schedules` accordent `SELECT` à toute session `authenticated` avec `using (true)`.
- La lecture du bucket privé `equipment-photos` est également autorisée à toute session authentifiée, sans vérifier rôle ou lien avec une fiche.
- La politique `authorized report updates` et le `GRANT UPDATE` sur `maintenance_reports` permettent au propriétaire, au technicien affecté ou au chef d’unité de modifier la ligne entière. Le client technicien n’édite que statut/observation, mais la base n’applique pas cette restriction de colonnes.

L’application masque l’espace aux rôles inconnus, mais l’interface n’est pas la frontière de sécurité : un client authentifié peut appeler directement l’API Supabase.

**Risque :** accès de comptes authentifiés hors rôle attendu aux fiches, échéances et photos; modifications métier plus larges que celles prévues par l’interface.

**Références :** `supabase/schema.sql` autour des politiques des tables et `storage.objects`; `lib/features/auth/auth_gate.dart`.

#### P0.4 — Configuration et démarrage sans garde d’erreur

`main()` attend `Supabase.initialize()` avant `runApp()`. Cette initialisation n’est pas entourée d’un état de démarrage ou d’un rendu d’erreur. Une configuration incorrecte ou une erreur d’initialisation peut laisser une page de chargement sans action de reprise.

`lib/core/env.json` est suivi par Git et contient URL + clé **publishable** Supabase (aucune clé `service_role` n’a été trouvée dans la configuration client inspectée). Cette clé est destinée au client; le point de dette est la configuration d’environnement : le fichier n’est pas ignoré et le README ne montre pas clairement comment l’injecter en build. Les valeurs `String.fromEnvironment` ne lisent pas ce JSON automatiquement.

**Risque :** builds locaux/staging/production dirigés vers la mauvaise instance, ou démarrage opaque si la configuration est invalide.

**Références :** `lib/main.dart`, `lib/core/supabase_config.dart`, `lib/core/env.json`, `.gitignore`, `README.md`.

#### P0.5 — Identité et signature Android de publication non prêtes

La configuration Android garde `applicationId` et `namespace` `com.example.vigimat`; le type `release` est signé avec la clé `debug`. Ces valeurs conviennent à l’exécution locale, pas à une distribution MVP.

**Risque :** identité de paquet instable et impossibilité de publier une mise à jour cohérente sans signature release dédiée.

**Références :** `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`.

### P1 — Fonctionnalités métier incomplètes ou ambiguës

#### P1.1 — Mode local incohérent entre les écrans

Le dashboard local tente de charger des métriques Supabase et affiche une erreur qui demande de vérifier Supabase. C’est confirmé par la capture utilisateur et par `DashboardService.load()`, qui lève une erreur si Supabase n’est pas configuré.

Le formulaire local affiche le texte disant que le signalement sera synchronisé plus tard, mais un signalement créé sans Supabase a `technicianId == null`. À la synchronisation ultérieure, `ReportSyncService` le marque en échec parce qu’il n’a pas de propriétaire distant. Le texte actuel promet donc un comportement qui n’existe que pour un utilisateur déjà authentifié, momentanément hors ligne.

**Références :** `lib/services/dashboard_service.dart`, `lib/features/dashboard/dashboard_overview.dart`, `lib/features/reports/report_form_page.dart`, `lib/services/report_sync_service.dart`.

#### P1.2 — Planification préventive distante non accessible depuis le centre

L’action « Programmer un entretien » enregistre dans SQLite via `LocalReportStore`. Son menu choisit les équipements depuis `Equipment.demo`. Ce parcours n’écrit pas dans `preventive_maintenance_schedules`, alors que le tableau de bord et les fiches d’équipement lisent cette table distante.

Le stock est une liste de valeurs fictives intégrée dans `MaintenanceSupportPage`. Le titre le signale, mais l’onglet reste présent dans l’espace connecté.

**Risque :** le chef peut croire avoir créé un entretien utilisable par l’équipe alors qu’il n’existe que sur son appareil; les notifications/indicateurs distants ne le voient pas.

**Références :** `lib/features/maintenance/maintenance_support_page.dart`, `lib/services/local_report_store.dart`, `lib/features/equipment/equipment_pages.dart`, `README.md`.

#### P1.3 — Parcours hors connexion et pièces jointes encore fragiles

La synchronisation est lancée à l’ouverture, au retour du réseau ou par action manuelle; elle n’a pas de reprise en arrière-plan documentée. Les médias locaux restent liés à des chemins fichier. Un changement de compte transforme les signalements d’un autre compte en échec permanent, sans action d’export/réattribution/suppression visible.

La base locale SQLite stocke les coordonnées, noms, statuts et chemins des pièces jointes. Aucun mécanisme de purge ou de durée de conservation n’est exposé dans l’application.

**Risque :** perte de confiance sur les signalements « en attente », accumulation de médias, ou mauvaise surprise lors d’un changement de compte/appareil.

**Références :** `lib/services/report_sync_service.dart`, `lib/services/local_report_store.dart`, `lib/features/home/reports_home_page.dart`.

### P1 — Sécurité métier et source de rôle non alignées

Le routage Flutter accepte `app_metadata.role`, puis retombe sur `userMetadata.role` et les variantes JWT. Les politiques SQL vérifient `app_metadata.role` seulement. Un utilisateur qui porte un rôle uniquement dans ses métadonnées modifiables peut donc voir l’interface chef/technicien alors que les opérations seront rejetées par RLS. Ce n’est pas, à lui seul, une élévation de privilège côté base, mais cela crée un état d’accès contradictoire.

La fonction `refresh_maintenance_notifications()` est `SECURITY DEFINER` et exécutable par tous les comptes authentifiés. Elle parcourt les échéances globales et l’application la déclenche en ouvrant/actualisant les notifications. C’est pratique en petit pilote, mais un endpoint de lecture déclenche ainsi un traitement global.

**Références :** `lib/features/auth/auth_gate.dart`, `supabase/schema.sql`, `lib/services/notification_repository.dart`.

### P1 — Pas de chaîne de validation et de publication

Le dépôt ne contient pas de workflow CI GitHub, de scripts de build/release, ni de migrations Supabase versionnées dans `supabase/migrations/`; le schéma est un unique script `supabase/schema.sql`. Le README indique `flutter analyze`/`flutter test`, mais cette suite ne couvre que les conversions de modèles et un test responsive du login. Aucun test de synchronisation, politiques RLS, stockage média, affectation ou notifications n’est présent.

**Risque :** une modification peut casser un parcours ou le schéma sans être détectée avant publication; les changements SQL ne sont pas rattachés à un ordre de migration reproductible.

### P2 — Coût de maintenance et cohérence

- Plusieurs écrans concentrent beaucoup de responsabilités : `dashboard_overview.dart` (~1 266 lignes), `equipment_pages.dart` (~952), `chief_dashboard_page.dart` (~907), `reports_home_page.dart` (~888). Présentation, chargement Supabase, règles de rôle et orchestration vivent souvent dans le même widget.
- Les statuts et couleurs de priorité sont répétés entre vues, modèles et SQL. Il existe plusieurs variantes de couleurs d’état; un nouveau statut impose des modifications coordonnées.
- Les écrans effectuent certaines requêtes Supabase directement, alors que d’autres utilisent des repositories. Cela complique les tests sans backend.
- Les métadonnées du projet sont encore celles du template (`pubspec.yaml` description, `web/index.html` et `web/manifest.json`), et les icônes/nom Android sont à revoir pour une sortie de produit.

## Points solides à conserver

- RLS activée sur les principales tables et buckets privés.
- Rôle `unit_head` vérifié par `app_metadata` dans les politiques SQL; comptes créés par l’administrateur selon le README.
- Jeton `service_role` lu côté Edge Function via `Deno.env`, pas dans le client Flutter.
- Pièces jointes de signalement limitées au propriétaire et lues par propriétaire, technicien affecté ou chef.
- Références uniques, contraintes de statuts/priorités, historique serveur et déduplication des notifications.
- `pubspec.lock` suivi et analyse Dart réussie.

## Conclusion

Le périmètre Android et les responsabilités des trois rôles sont maintenant définis. Avant les corrections, il reste à figer les transitions de statut et les règles de consultation hors ligne. L’ordre recommandé est : adapter le modèle de données et préserver les rapports existants, sécuriser les politiques Supabase, fiabiliser la file locale/synchronisation, finaliser l’identité et la signature Android, puis valider les parcours sur téléphone. Les notifications, l’inventaire administrable, les entretiens et le stock peuvent rester hors du MVP. Le découpage des grands widgets peut attendre; il n’est pas nécessaire de réécrire l’architecture avant le pilote.
