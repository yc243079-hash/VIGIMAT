# État de préparation du MVP Android — VIGIMAT

**Mis à jour le 24 novembre 2026**  
**Périmètre validé avec l’utilisateur :** Android uniquement; soldat déclarant, chef d’unité, technicien; signalements texte et/ou vocal, photos, informations du véhicule et GPS; consultation des statuts; conservation hors ligne après une première connexion; synchronisation vers Supabase au retour du réseau.

## Résumé

La base fonctionnelle du MVP est en cours de stabilisation dans la codebase. Les principaux parcours par rôle, le cache SQLite, une file de synchronisation, l’envoi des médias et une tâche Android de reprise en arrière-plan sont implémentés. Le parcours local n’est pas une démonstration anonyme : il exige un compte ayant effectué sa première connexion à Supabase.

**Le MVP n’est pas encore prêt à être remis à un pilote.** Il reste à terminer les validations Flutter/Android, appliquer et valider la migration Supabase sur la bonne instance, provisionner les unités et comptes, puis tester le flux réel avec un téléphone Android. L’identité de paquet et la signature de distribution restent également à fixer avant une publication officielle.

La base n’a pas été supprimée et aucune migration distante n’a été exécutée. L’inspection n’a montré aucune nécessité de repartir de zéro; le script préparé est additif et conserve les lignes existantes.

## Modèle fonctionnel livré dans le code

| Rôle | Accès et actions |
|---|---|
| Soldat | Crée un signalement lié à son compte et à son unité; ajoute texte et/ou vocal, jusqu’à cinq photos, véhicule, lieu et coordonnées GPS; consulte ses dossiers et leur historique sans pouvoir changer le statut. |
| Chef d’unité | Consulte les dossiers de son unité; affecte ou réaffecte un technicien de la même unité; met à jour les états de suivi; valide et clôture une réparation terminée. |
| Technicien | Consulte seulement les dossiers qui lui sont affectés; indique la réparation et son compte rendu, ou met le dossier en attente avec un motif. |
| Administrateur | Crée les comptes et attribue rôle/unité côté Supabase; l’administration des comptes ne fait pas partie de l’application pilote. |

La clôture est réservée à l’action de validation du chef après le statut « réparé, à valider ». L’historique garde l’acteur, l’heure, le changement et l’éventuel commentaire.

## Changements réalisés dans l’application

- Routage d’accès à partir du profil serveur (`app_metadata`), avec cache local du profil pour l’usage hors ligne après connexion initiale.
- Formulaire de signalement soldat avec capture GPS, permission de localisation, saisie manuelle du lieu en solution de repli, photos et enregistrement/lecture audio.
- Écrans distincts soldat, technicien et chef d’unité; le soldat n’a pas de commande d’édition du statut.
- Extension versionnée du stockage SQLite, sans suppression des tables locales existantes; cache de rapports, chronologie, techniciens et file d’actions.
- Synchronisation idempotente via RPC Supabase, envoi des pièces jointes vers un bucket privé, reprise sur changement de réseau et tâche WorkManager Android lorsque l’application est en arrière-plan.
- Restriction des consultations au déclarant soldat, au technicien affecté dans son unité, ou au chef de la même unité. Les anciennes lignes ne sont plus montrées à un technicien simplement parce qu’il est renseigné comme créateur historique.
- Suppression du chemin de création de panne depuis les fiches d’équipement; seul le rôle soldat crée les signalements selon le périmètre convenu.

## Migration Supabase préparée

Fichier : `supabase/migrations/202611240001_vigimat_mvp_roles_offline.sql`.

- **Projet existant avec le schéma VIGIMAT actuel :** appliquer cette migration additive après avoir fait une sauvegarde vérifiée.
- **Nouveau projet Supabase vide :** exécuter `supabase/schema.sql`, puis cette migration. Ne pas réexécuter l’ancien `schema.sql` après la migration, car il rétablirait les anciennes règles.
- La migration ne supprime pas de rapport, d’historique, de fichier ni de compte. Elle ajoute les relations d’unité et de déclarant, remplace les politiques de rapports, ajoute les RPC de workflow et configure le bucket privé des médias.
- Les anciens rapports sans `unit_id` restent conservés. Ils devront être associés explicitement à une unité après vérification avant d’être affichés dans le tableau de cette unité; aucun rattachement n’est deviné.
- Aucun secret `service_role` ne doit être ajouté à l’application Android. Le client utilise seulement l’URL et la clé publique/publishable déjà prévues dans la configuration de build.

Pour chaque compte pilote, créer d’abord l’utilisateur dans Supabase Auth, créer son unité dans `maintenance_units`, puis affecter côté serveur les valeurs protégées `role` (`soldier`, `technician` ou `unit_head`), `unit_id`, `full_name` et, si disponible, `personnel_number`. Sans unité active et métadonnées valides, l’application refuse l’accès métier.

## Validation et déploiement restants

1. **Validé localement :** les huit tests Flutter passent et l’APK debug compile. Relancer l’analyse statique après résolution du blocage du serveur Dart; elle n’est pas comptée comme réussie pour l’instant.
2. Choisir l’instance Supabase (staging ou pilote), vérifier une sauvegarde, puis demander confirmation du nom de projet avant l’application de la migration distante.
3. Appliquer la migration et créer une unité ainsi qu’un compte par rôle. Vérifier que les rapports et médias d’un autre compte/unité ne sont jamais visibles.
4. Sur téléphone réel : première connexion; mode avion; création texte, vocal et photo; fermeture/redémarrage; retour réseau; absence de doublon; vérification chef → technicien → réparation → validation; consultation soldat en lecture seule.
5. Pour la distribution pilote, produire l’APK installable. Pour une publication durable, remplacer `com.example.vigimat` par l’identifiant Android choisi et configurer une clé de signature release sauvegardée hors du dépôt.

## Dette et risques qui restent

- **Publication :** `applicationId` est encore `com.example.vigimat` et le build release utilise la signature debug; non publiable tel quel dans un canal officiel.
- **Base distante :** migration écrite mais pas encore exécutée par un serveur PostgreSQL/Supabase; les politiques et RPC doivent être validées sur la bonne instance avant le pilote.
- **Données historiques :** les anciens rapports sans rattachement d’unité ne peuvent pas apparaître au chef tant qu’une correspondance fiable n’a pas été établie.
- **Données locales :** SQLite et les médias sont conservés dans l’espace privé de l’application, sans chiffrement applicatif dédié ni politique de purge. Pour un usage terrain avec données sensibles, décider de la conservation et du chiffrement avant élargissement du pilote.
- **Validation terrain :** aucun test instrumenté de synchronisation, d’upload ou de permissions par rôle ne remplace encore l’essai avec trois comptes et un appareil Android réel.
- **SDK/plugins :** le build local a signalé un avertissement de compatibilité Kotlin Gradle Plugin pour `workmanager_android` (ainsi que l’ancien plugin Firebase encore présent), et un avertissement de décalage de version des outils Android. Ces avertissements doivent être suivis lors de la mise à jour des plugins/outils; ils ne remplacent pas le résultat du build.
- **Contrôles exécutés pendant la correction :** `flutter test --no-pub` passe avec 8 tests; le build `flutter build apk --debug --dart-define-from-file=lib/core/env.json` passe. L’APK debug généré est volumineux (environ 203 Mo car il contient plusieurs architectures). `dart format --set-exit-if-changed` passe sur les fichiers Dart modifiés et `git diff --check` ne détecte pas d’erreur d’espacement. `flutter analyze`/`dart analyze` reste sans résultat après plus de 30 secondes, bloqué sur « Analyzing… » sans aucun diagnostic; ne pas le compter comme validation réussie. Aucun téléphone n’était connecté à ADB; aucun client PostgreSQL/Supabase CLI n’est installé, donc la migration et les parcours distants ne sont pas encore validés.
- **Conception :** certains anciens modules d’inventaire, maintenance et notifications restent dans la codebase alors qu’ils ne font pas partie du parcours MVP. Leur refactorisation ou leur suppression peut attendre si les routes pilote restent isolées.

## Fichiers d’audit liés

- `design-analyse/DETTE_TECHNIQUE_MVP.md` — état de la dette avant les changements.
- `design-analyse/PLAN_CORRECTIONS_MVP.md` — périmètre et ordre de correction proposé.
- `design-analyse/AUDIT_COMPLET.md` — audit visuel/code des interfaces et charte graphique.
