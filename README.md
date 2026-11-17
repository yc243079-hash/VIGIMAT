# VIGIMAT

Prototype Flutter de suivi administratif de la maintenance des équipements non sensibles.

## Parcours actuellement implémenté

- Connexion Supabase et routage selon le rôle placé dans `app_metadata.role` (`technician` ou `unit_head`). Aucun compte ou mot de passe n’est codé en dur.
- Formulaire de signalement avec équipement, description détaillée, catégorie de panne, priorité à quatre niveaux, localisation, date/heure automatique et identité du déclarant.
- Ajout de plusieurs photographies et d’un message vocal facultatif.
- Lecture et suppression du vocal avant l’enregistrement du signalement.
- Sauvegarde SQLite des signalements et conservation des photos et vocaux dans l’espace privé de l’application.
- File locale et transfert des signalements et pièces jointes vers Supabase lorsqu’un compte technicien authentifié et une connexion sont disponibles.
- Tableau de bord par rôle, avec les statistiques et graphiques calculés à partir des données Supabase visibles par le compte connecté.
- Référence unique générée pour chaque signalement, file locale hors connexion et synchronisation des pièces jointes vers Supabase.
- Tableau du chef d’unité avec consultation des signalements, photos/vocaux, chronologie, mise à jour des statuts et observations.
- Suivi individuel des signalements avec statut et historique, protégé par les règles RLS de Supabase.
- Centre de notifications Supabase, badge non lu, niveaux de priorité, marquage lu/non lu et liens directs vers les signalements et équipements concernés.
- Répertoire des équipements avec fiches, génération et lecture de QR codes.
- Inventaire Supabase avec fiches détaillées, recherche et filtres, QR codes uniques, historique des pannes/interventions et échéances préventives.
- Historique des signalements, calendrier local des entretiens et stock fictif simplifié.

En mode local, le répertoire et le stock de démonstration restent fictifs. Avec Supabase configuré, l’inventaire utilise les tables distantes et les chefs d’unité peuvent créer ou modifier les fiches ; les techniciens disposent d’un accès en lecture. Les fiches incluent une référence unique, les données techniques, une photo privée, la localisation, le responsable, l’état, le QR code et les historiques associés aux signalements liés. La recherche et les filtres couvrent catégorie, état et localisation. Les entretiens créés depuis l’ancienne interface restent locaux ; les échéances affichées par les fiches et le tableau de bord viennent de `preventive_maintenance_schedules`.

Le tableau de bord n’utilise aucun équipement de démonstration : ses indicateurs proviennent de `equipment_inventory` et `preventive_maintenance_schedules`, sans données initiales inventées. Les anciennes pannes sont associées automatiquement aux fiches lorsque leur nom correspond sans ambiguïté ; les nouveaux signalements conservent l’identifiant de l’équipement.

Les signalements suivent les statuts `new`, `pending`, `assigned`, `in_progress`, `waiting_parts`, `resolved` et `closed`, affichés en français. Les chefs d’unité mettent à jour le statut et les observations ; les techniciens consultent uniquement leurs signalements et leur chronologie. Les références sont de la forme `SIG-<UUID>` et les photos sont conservées dans le bucket privé `report-attachments`.

Les notifications persistantes sont générées par les insertions et changements réels de signalements (nouveau, critique, affectation, statut, pièces nécessaires, résolution) ainsi que par les échéances des interventions et entretiens. Une échéance d’intervention est saisie par le chef lors de l’affectation ; l’imminence d’un entretien est fixée à trois jours. Le centre actualise les échéances à l’ouverture et périodiquement pendant l’utilisation. Pour l’actualisation en arrière-plan, activer l’extension Supabase `pg_cron`, puis réexécuter `supabase/schema.sql` afin d’enregistrer le contrôle périodique.

Les notifications push Android utilisent Firebase Cloud Messaging et restent facultatives : sans paramètres Firebase, l’application conserve le centre de notifications intégré sans tenter d’initialiser Firebase. Quand Firebase est configuré, le client enregistre le jeton FCM du compte connecté dans `user_push_tokens`, affiche les alertes en premier plan et ouvre le signalement ou l’entretien après un appui sur la notification. Les jetons sont retirés de Supabase lors de la déconnexion.

## Exécution locale

1. Installer Flutter et Android Studio, puis vérifier l’installation avec `flutter doctor`.
2. À la racine du projet, exécuter :

   ```powershell
   flutter pub get
   flutter run
   ```

3. Sur Android, autoriser l’accès au microphone ou à l’appareil photo lorsque le système le demande.

Sans configuration Supabase, le prototype fonctionne en mode local avec des signalements conservés sur l’appareil. Pour activer l’authentification et la synchronisation :

1. Exécuter [`supabase/schema.sql`](./supabase/schema.sql) dans l’éditeur SQL du projet Supabase. Ce script crée/complète les tables de signalements, d’équipements et d’entretiens préventifs, les règles RLS, l’historique, les fonctions de statistiques/référence et les buckets privés des pièces jointes et photos.
2. Créer les comptes dans Supabase Auth et leur attribuer, **côté serveur uniquement**, la valeur `app_metadata.role` `technician` ou `unit_head`.
3. Lancer l’application avec l’URL du projet et sa clé publique :

   ```powershell
   flutter run `
     --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co `
     --dart-define=SUPABASE_PUBLISHABLE_KEY=VOTRE_CLE_PUBLIQUE
   ```

Ne jamais utiliser une clé `service_role` dans l’application, ni permettre au client de modifier `app_metadata`.

### Activer le push Android

1. Réexécuter `supabase/schema.sql` pour appliquer les permissions serveur permettant à la fonction de retirer les jetons FCM expirés. Le script est idempotent.
2. Dans Firebase Console, créer une application Android dont l’identifiant correspond à `applicationId` dans `android/app/build.gradle.kts` (initialement `com.example.vigimat`) et activer Firebase Cloud Messaging.
3. Construire l’application avec les paramètres Firebase de cette application. Ces valeurs d’identification Firebase ne sont pas des secrets :

   ```powershell
   flutter run `
     --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co `
     --dart-define=SUPABASE_PUBLISHABLE_KEY=VOTRE_CLE_PUBLIQUE `
     --dart-define=FIREBASE_API_KEY=VOTRE_API_KEY_FIREBASE `
     --dart-define=FIREBASE_APP_ID=VOTRE_APP_ID_ANDROID `
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=VOTRE_SENDER_ID `
     --dart-define=FIREBASE_PROJECT_ID=VOTRE_PROJECT_ID
   ```

4. Créer un compte de service du même projet Firebase avec le rôle `Firebase Cloud Messaging API Admin`. Dans **Supabase → Edge Functions → Secrets**, configurer `FIREBASE_SERVICE_ACCOUNT_JSON` avec son JSON et `PUSH_WEBHOOK_SECRET` avec une valeur aléatoire forte. Ne jamais ajouter le JSON du compte de service ni une clé `service_role` au dépôt ou à l’application.
5. Se connecter au projet Supabase avec la CLI, puis déployer la fonction :

   ```powershell
   supabase login
   supabase link --project-ref VOTRE_PROJECT_REF
   supabase functions deploy send-push-notification
   ```

6. Dans Supabase Database Webhooks, créer un webhook `INSERT` sur `public.user_notifications`, pointant vers `/functions/v1/send-push-notification`, et ajouter l’en-tête `x-push-webhook-secret` avec la même valeur que le secret Edge Function.
7. Installer/mettre à jour l’application Android, accepter l’autorisation de notifications, puis créer un signalement ou une affectation pour tester l’envoi. En l’absence d’appareil enregistré ou si FCM refuse un jeton, l’erreur est conservée dans `user_notifications.push_error`.

Le tableau de bord affiche zéro ou aucune valeur de performance lorsque les tables ne contiennent pas de données ; le script n’insère aucun équipement ni entretien fictif. Les techniciens voient leurs signalements et l’inventaire autorisé par RLS ; les chefs d’unité voient les signalements globaux et peuvent gérer les équipements et les échéances de planification.

## Vérifications

```powershell
flutter analyze
flutter test
```
