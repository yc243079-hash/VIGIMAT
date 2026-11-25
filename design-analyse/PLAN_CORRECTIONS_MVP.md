# Plan de corrections et de sortie MVP — VIGIMAT

Ce plan privilégie une livraison courte et contrôlable. Il évite une refonte générale et place les garde-fous de données et le parcours hors ligne avant les retouches de code secondaires.

## Périmètre confirmé

- **Plateforme :** application native Android uniquement; pas de Web, Windows ni iOS pour ce MVP.
- **Données :** chaque téléphone conserve les rapports en local et les synchronise automatiquement avec Supabase lorsque le réseau revient. Chaque utilisateur se connecte une première fois avec Internet; sa session est ensuite conservée sur son téléphone pour l’usage hors ligne.
- **Fonctions :** signalement de panne par un soldat en texte et/ou vocal, photos, informations du véhicule et autres détails utiles, identité du déclarant liée à son compte, lieu capturé par GPS, suivi des statuts et synchronisation.
- **Hors MVP pour le moment :** push, stock, planification préventive partagée et gestion avancée de l’inventaire. Ne garder que les données du véhicule nécessaires au signalement.

## Modèle de rôles MVP — proposition métier

- **Soldat (`soldier`) :** se connecte une première fois en ligne; crée et envoie un signalement avec texte et/ou vocal, photos, véhicule, position GPS et identité préremplie depuis son compte. Peut ensuite consulter uniquement ses propres signalements et leur historique, en lecture seule. Ne peut ni affecter un technicien ni changer le statut.
- **Chef d’unité (`unit_head`) :** voit l’ensemble des signalements et réparations de son unité, avec les informations du soldat déclarant et du technicien affecté; affecte ou réaffecte le technicien, met à jour les statuts et valide/clôture la réparation.
- **Technicien (`technician`) :** voit les pannes qui lui sont affectées, réalise l’intervention, puis indique la réparation effectuée et met à jour le statut pour validation par le chef. Il ne crée pas les signalements au nom des soldats et ne gère pas les affectations.
- **Administrateur de comptes :** crée les comptes et attribue rôle et unité dans Supabase; c’est une fonction d’administration hors de l’application MVP, pas un quatrième rôle métier.

**Cycle de statuts proposé :** `Nouveau` (soldat) → `Affecté` (chef) → `Réparé, à valider` (technicien après intervention, avec compte rendu) → `Validé / clôturé` (chef). Ajouter `En attente` avec un motif si une panne est bloquée. Le chef peut corriger le statut à tout moment; chaque changement doit être historisé avec auteur, date et commentaire/motif.

Ce modèle remplace l’hypothèse antérieure où le technicien était aussi le créateur du signalement. Le code actuel ne connaît que `technician` et `unit_head`, et la table impose un `technician_id` comme propriétaire du rapport : le rôle soldat, l’identité du déclarant et les règles d’accès doivent donc être conçus avant les corrections fonctionnelles. Préserver les rapports existants lors de l’évolution du schéma.

Le projet Supabase déjà référencé sera traité comme une donnée à préserver. Avant toute migration, créer une sauvegarde et tester le script sur une instance staging ou une copie; ne pas exécuter de modification non vérifiée sur la base de production.

## Étape 1 — Rendre l’environnement reproductible

- Sortir les valeurs propres à l’environnement du fichier `lib/core/env.json` suivi par Git. Ajouter un exemple sans valeur et documenter `--dart-define-from-file` ou les variables CI; garder les clés de service uniquement dans Supabase/CI.
- Ajouter un état de démarrage explicite : config absente = mode local annoncé; config invalide ou `Supabase.initialize()` en erreur = écran d’erreur avec réessai, pas de chargement sans fin.
- Distinguer `local`, `staging` et `production` dans les profils de lancement/build.
- Préparer une instance Supabase staging, appliquer le schéma dessus, créer un compte de chaque rôle métier (`soldier`, `technician`, `unit_head`) avec rôle et rattachement d’unité attribués côté serveur dans `app_metadata`/profil.

**Critère de sortie :** l’équipe peut lancer le mode local et un build connecté staging sans éditer le code ni deviner la configuration.

## Étape 2 — Fermer les permissions backend avant les vrais comptes

- Redéfinir le propriétaire du signalement comme le soldat déclarant; séparer sans ambiguïté `reporter_id` et `assigned_technician_id`, puis migrer les données existantes sans perdre d’historique.
- Appliquer les accès par rôle et unité : soldat crée et consulte ses seuls signalements en lecture seule, chef voit et gère ceux de son unité, technicien lit et actualise seulement les pannes qui lui sont affectées.
- Remplacer l’`UPDATE` direct global des signalements par des opérations serveur ou politiques qui imposent les transitions : chef (affectation/réaffectation, statut et validation), technicien affecté (avancement de réparation et compte rendu), soldat (aucune modification de statut).
- Retirer le fallback `user_metadata.role` côté routage et utiliser la même source de rôle sécurisée que RLS (`app_metadata`). Afficher un message d’accès si le rôle manque.
- Réserver le rafraîchissement global des notifications à un traitement serveur planifié ou en limiter strictement l’appel; garder l’appel de lecture du badge sans effet de bord global.
- Définir limites de taille/types autorisés pour photos et audios dans l’interface et les buckets.

**Critère de sortie :** tests en staging confirment qu’un soldat ne modifie pas les statuts, qu’un technicien ne voit/actualise que ses affectations, qu’un chef gère les seuls signalements de son unité et qu’un rôle inconnu n’accède à aucune donnée métier.

## Étape 3 — Stabiliser le parcours principal selon la plateforme

### Publication Android

- Attribuer un `applicationId`/namespace VIGIMAT unique et définitif; ne plus utiliser `com.example.vigimat`.
- Configurer la signature release avec secrets hors du dépôt, valider APK/AAB signé et mise à jour depuis la version pilote.
- Finaliser icônes, permissions caméra/microphone, formats médias et tester le parcours sur un téléphone Android réel.
- Garder les secrets de signature hors du dépôt; les paramètres Supabase côté client restent des clés publishable protégées par RLS.

### Parcours hors ligne et synchronisation

- Permettre au soldat de créer un signalement hors réseau après sa première connexion réussie; conserver son identifiant, l’identité liée au compte et le brouillon localement pour les associer correctement au retour réseau.
- Mettre en file locale les modifications permises au chef et au technicien faites hors réseau (affectation, déclaration de réparation, validation), avec auteur et ordre des événements conservés.
- En mode hors ligne, le chef voit les signalements de son unité déjà chargés sur son téléphone; un signalement créé sur un autre appareil ne devient visible qu’après synchronisation. Afficher clairement l’état local/en attente/synchronisé.
- Synchroniser automatiquement le texte, les photos et le vocal; rendre les envois idempotents et reprendre les pièces échouées sans créer de doublon.
- Définir la résolution d’un conflit si un même signalement est modifié sur plusieurs appareils avant synchronisation; ne jamais écraser silencieusement une décision du chef ou le compte rendu du technicien.
- Corriger le texte d’état : les données hors ligne d’un compte déjà connecté seront synchronisées; un appareil jamais authentifié devra d’abord se connecter pour pouvoir associer un rapport à un compte.
- Rendre l’état d’échec exploitable : cause courte, réessayer, conserver la pièce jointe et afficher si une action est nécessaire.

**Critère de sortie :** un soldat déjà connecté peut créer hors réseau un signalement texte/vocal avec photos, véhicule et position, le retrouver après redémarrage, puis le synchroniser sans doublon dès le retour de la connexion.

## Étape 4 — Fermer le périmètre métier

- Retirer du parcours MVP le stock de démonstration et la planification préventive, déjà déclarés hors périmètre.
- Garder uniquement les informations de véhicule et de panne utiles au signalement; différer gestion d’inventaire, QR et édition complète des fiches.
- Définir quelles données de profil identifient un soldat et son unité; capturer le GPS avec permission et prévoir une saisie/correction manuelle si la position est indisponible.
- Conserver la chronologie des transitions et l’auteur de chaque action; le soldat consulte l’état et l’historique de ses propres signalements sans pouvoir les modifier.
- Définir le sort des brouillons locaux au changement de compte : conserver pour le compte d’origine, proposer export/suppression, ou demander confirmation; ne pas convertir silencieusement en échec permanent.
- Décider d’une durée de conservation des médias et signalements sur l’appareil et d’une action de purge.

## Étape 5 — Validation automatisée minimale

Ajouter une CI qui exécute à chaque changement :

1. `dart format --output=none --set-exit-if-changed lib test`.
2. `flutter analyze`.
3. `flutter test`.
4. Build Android signé.
5. Vérification du schéma/migrations Supabase sur une base jetable ou staging.

Tests fonctionnels prioritaires à ajouter :

- signalement local, validation de formulaire et reprise après fermeture;
- sync hors ligne → en ligne, doublons, erreur d’upload et reprise;
- affichage/lecture des pièces jointes sur la plateforme cible;
- rôle `app_metadata`, navigation d’un rôle inconnu et autorisations RLS par rôle et unité;
- création par soldat, affectation par chef, réparation déclarée par technicien, validation par chef et chronologie;
- persistance et synchronisation des photos/vocaux sur Android.

Le contrôle de départ connu est `dart analyze lib test` réussi. `flutter test --no-pub` n’a pas fourni de résultat dans l’environnement de cet audit et doit être relancé avant toute validation de release.

## Étape 6 — Déploiement progressif

1. Déployer le schéma et les fonctions sur staging; contrôler RLS avec les trois rôles métier.
2. Installer le build Android MVP sur un petit groupe pilote et vérifier connexion initiale, création hors réseau, pièces jointes, suivi, synchronisation et comportement en réseau faible.
3. Corriger les défauts bloquants remontés; vérifier l’absence de clé `service_role` dans les bundles.
4. Construire et signer l’artefact Android pour la distribution choisie.
5. Conserver version précédente, procédure de retour arrière et sauvegarde Supabase avant extension du pilote.

## Ce qui peut attendre après le MVP

- Découper les widgets de 900–1 200 lignes en composants plus petits.
- Remplacer toute l’architecture de gestion d’état ou de navigation.
- Refaire les graphiques et ajouter des animations.
- Construire un système de thème ou de design tokens complet.

Ces améliorations réduiraient la dette à moyen terme, mais ne doivent pas retarder la stabilisation des permissions, de la plateforme, du parcours signalement et du build de release.
