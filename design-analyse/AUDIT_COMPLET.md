# Audit complet du design et de l’expérience VIGIMAT

> **Capture de référence avant correction :** ce rapport décrit l’interface observée lors de l’audit initial. Le périmètre produit a depuis été resserré sur Android et les trois rôles du MVP; l’état fonctionnel à jour se trouve dans [ETAT_MVP_ANDROID.md](ETAT_MVP_ANDROID.md).

**Date : 24 novembre 2026**  
**Périmètre :** application Flutter, parcours technicien et chef d’unité, mode local, capture du dashboard fournie par l’utilisateur et composants définis dans le code.

## 1. Résumé exécutif

VIGIMAT a une direction visuelle métier identifiable : marine, turquoise, fonds clairs, cartes, icônes techniques et codes de statut. La capture du dashboard local confirme que cette direction fonctionne à l’écran : marque lisible, grand bandeau d’accueil, bonne largeur de lecture et actions principales faciles à repérer.

Le principal problème observé n’est pas la palette. C’est la cohérence entre le mode annoncé et les données présentées : la capture affiche « Mode local », puis une erreur qui demande de vérifier Supabase. Le code confirme ce comportement : le dashboard demande des métriques distantes et échoue intentionnellement lorsque Supabase n’est pas configuré. Le résultat occupe une grande carte dans la zone la plus visible et repousse les signalements récents vers le bas.

Sur la capture de bureau, la navigation inférieure et le bouton flottant gardent une logique mobile. Le bouton « Nouveau signalement » chevauche visuellement la zone des signalements récents. Il faut également réduire la répétition du logo et harmoniser plusieurs variantes de couleurs. Les autres pages sont évaluées ci-dessous à partir de leur code; seule la capture du dashboard local est disponible visuellement.

## 2. Constats prioritaires

### P1 — Le tableau de bord local présente une erreur distante comme état principal

**Observation visuelle :** le bandeau porte le badge « Mode local », mais la grande carte suivante dit « Indicateurs indisponibles » et conseille de vérifier Supabase ainsi que `supabase/schema.sql`. Aucun chiffre de démonstration ou résumé local n’est présenté.

**Confirmation dans le code :** `DashboardService.load()` lève `StateError('Supabase n’est pas configuré.')` si l’application est en mode local. `DashboardOverview` transforme cette erreur en carte générique d’indisponibilité.

**Effet UX :** l’utilisateur peut croire que son mode local est cassé ou qu’il doit configurer Supabase, alors que l’étiquette indique précisément l’absence de configuration distante.

**Recommandation :** fournir une vue locale cohérente (compteurs calculés à partir des rapports locaux et données de démonstration clairement étiquetées) ou remplacer cette erreur par un état informatif du type « Les indicateurs détaillés nécessitent une connexion à l’espace distant ». Réserver les consignes de schéma aux erreurs Supabase réellement distantes.

### P1 — Navigation de bureau et action flottante

La capture de bureau montre une barre de navigation blanche qui s’étend sur toute la largeur et occupe une bande importante en bas. Le `NavigationBar` à quatre destinations reste le même qu’en mobile. Le bouton flottant étendu se superpose au bord supérieur droit de la carte des signalements récents.

**Recommandation :** sur écran large, étudier une navigation latérale ou un bandeau de navigation moins haut. Donner au contenu inférieur une zone de dégagement suffisante pour le FAB, ou déplacer l’action dans l’en-tête de la liste sur les grands écrans. Vérifier que le FAB ne recouvre jamais une carte cliquable.

### P2 — Répétition du logo dans le premier écran

L’AppBar affiche déjà le wordmark à gauche. Le bandeau de tableau de bord réaffiche le symbole et « VIGIMAT ». Cette répétition renforce la marque, mais prend de la place au-dessus de la ligne de bienvenue sans ajouter de contexte. Elle devient plus visible sur un grand écran où les deux marques sont éloignées verticalement.

**Recommandation :** conserver le wordmark dans l’AppBar et réserver le bandeau au nom d’utilisateur/rôle, au contexte de page, à l’actualisation et à l’identité malienne; ou faire de l’AppBar un simple conteneur sans wordmark sur le dashboard.

### P2 — Contraste des accents sur fonds blancs

Calcul de contraste relatif par rapport au blanc pour les tokens centraux : turquoise `#14B8A6` **2,49:1**, orange `#F59E0B` **2,15:1**, vert `#16A34A` **3,30:1**, texte secondaire `#687386` **4,79:1**. Le pictogramme orange de la carte d’erreur sur la capture est visible, mais nettement plus pâle que le texte et le titre. Les accents turquoise et orange sont également employés comme icônes sur des surfaces très claires dans plusieurs vues.

**Recommandation :** garder les teintes de marque pour les surfaces colorées et les fonds doux; prévoir des nuances plus sombres pour les petits pictogrammes, les statuts et tout libellé directement posé sur blanc. Vérifier le rendu en plein jour et sur des écrans peu lumineux.

### P2 — Palette sémantique fragmentée

La palette centralisée contient `#14B8A6`, `#F59E0B`, `#DC2626` et `#16A34A`, tandis que plusieurs écrans codent directement des états en `#18A6A6`, `#B36B12`, `#B84242` et `#17815E`. Les couleurs Flutter `Colors.red`, `Colors.deepOrange` et `Colors.blueGrey` apparaissent aussi. Cela crée des variantes de statut différentes d’une page à l’autre.

**Recommandation :** centraliser les couleurs d’état et leurs versions foncées/claires dans la charte, puis utiliser les mêmes correspondances panne/retard/en cours/terminé partout.

## 3. Audit interface par interface

### Connexion, session et accès refusé

- **Forces :** écran de connexion très distinctif, identité nationale, bannière illustrée, champs reconnaissables, visibilité du mot de passe et bouton d’action fortement différencié. Le conteneur étroit et le défilement conviennent aux petits téléphones.
- **À surveiller :** la grande bannière consomme une part importante de la hauteur sur mobile; l’écran est entièrement personnalisé avec champs arrondis et bouton pilule, alors que le reste de l’application utilise des rayons plus petits. Les états « Session indisponible » et « Accès non attribué » retombent sur une page très minimale.
- **Piste :** conserver la connexion comme page de marque, mais alléger sa hauteur sur petits écrans et aligner l’apparence des messages d’accès sur les cartes d’erreur du reste de l’application.

### Dashboard technicien — capture réelle fournie

- **Forces :** lecture immédiate du rôle local et de la page; dégradé marine, titre blanc, devise à droite; largeur centrale confortable; action de création identifiable; navigation inférieure explicite.
- **À surveiller :** wordmark répété dans l’AppBar et le bandeau; erreur Supabase dominante en mode local; les signalements récents commencent sous cette carte et se trouvent partiellement sous la ligne de flottaison; FAB au-dessus de la carte; navigation de bureau très basse et étendue.
- **Évaluation :** le style est cohérent, mais le premier écran donne davantage de place au manque de métriques qu’à l’action locale principale. La correction du contenu local améliorerait nettement la perception de finition.

### Dashboard chef d’unité

- **Forces :** réutilise le même langage visuel et les mêmes composants; les métriques et graphiques distinguent supervision et activité technicien; les graphiques s’organisent en colonnes sur écran large.
- **À surveiller :** même dépendance aux métriques Supabase; carte d’erreur identique au mode local même si le rôle n’est pas local; empilement vertical conséquent avant la liste de signalements.
- **Piste :** séparer un problème de connexion, un schéma incomplet et un espace local; le message d’erreur doit décrire l’état réellement détecté.

### Liste des signalements

- **Forces :** référence et équipement en tête, aperçu image, priorité/statut/synchronisation en badges, signalement audio identifié; états vide, chargement et erreur prévus. Le lien vers le détail est évident.
- **À surveiller :** jusqu’à quatre badges plus un message d’erreur compact rendent les cartes denses; l’état de synchronisation rivalise visuellement avec le statut métier.
- **Piste :** réduire les badges secondaires sur mobile et regrouper la synchronisation dans une ligne de métadonnées ou un indicateur discret.

### Création d’un signalement

- **Forces :** formulaire complet et séquencé par sections; sélection d’équipement, catégorie, localisation, description, photos, horodatage, déclarant, vocal et priorité; aperçus supprimables; bouton final pleine largeur.
- **À surveiller :** formulaire long en une seule colonne, sans indication de progression; plusieurs sections utilisent seulement un titre et un espace, sans carte ou séparateur. L’action principale est éloignée du début du formulaire.
- **Piste :** conserver le formulaire en une page, mais renforcer le regroupement visuel (incident, médias, déclaration) et prévoir une barre d’action fixe ou un rappel de progression sur téléphone.

### Suivi du signalement

- **Forces :** informations de base condensées dans une carte, statut en pastille, galerie photo horizontale et chronologie verticale; le technicien affecté voit ses commandes d’intervention.
- **À surveiller :** informations, photos, chronologie et formulaire de mise à jour s’empilent dans un long défilement; le cas « local non synchronisé » ne permet pas le suivi distant, mais le message explicatif arrive en bas.
- **Piste :** remonter le message de disponibilité du suivi près du statut et distinguer visuellement les actions du technicien de la consultation historique.

### Inventaire des équipements

- **Forces :** recherche textuelle, trois filtres fonctionnels, compteur de résultats, scan QR et bouton d’ajout conditionné au rôle; les cartes gardent nom et état lisibles.
- **À surveiller :** trois menus de filtre sous la recherche peuvent occuper un écran entier sur mobile; l’inventaire mêle données réelles et démonstration en mode local, avec une mention de source seulement dans le sous-titre du bandeau.
- **Piste :** replier les filtres secondaires sur petit écran et rendre la source locale/démonstration plus explicite lorsqu’il s’agit des équipements d’exemple.

### Fiche équipement

- **Forces :** grande image, badges d’état et de référence, données techniques en grille responsive, QR code facile à scanner, action de panne bien visible et historiques séparés.
- **À surveiller :** trois blocs d’historique peuvent produire une fiche très longue; en mode local, le dépôt de photos n’est pas activé et les historiques sont vides.
- **Piste :** conserver les détails principaux en haut, puis replier les historiques vides ou les présenter par onglets/accordéons. Ajouter des états explicites pour photo et historique indisponibles en local.

### Création/modification d’équipement

- **Forces :** champs groupés par informations générales, identification et affectation; aperçu photo de taille confortable; largeur maximale limitée sur bureau.
- **À surveiller :** formulaire de grande longueur, titres de section non encadrés, bouton enregistrer uniquement en bas; édition possible seulement pour le chef.
- **Piste :** reprendre les groupes visuels du formulaire de signalement et maintenir l’action d’enregistrement accessible pendant le défilement.

### Scanner QR

- **Forces :** caméra plein écran, cadre de visée blanc contrasté, ouverture automatique au premier code reconnu; titre clair dans l’AppBar.
- **À surveiller :** aucun état de permission refusée ou aide de repositionnement n’est visible dans l’écran décrit; le message d’erreur est posé en panneau blanc sans style partagé.
- **Piste :** harmoniser le panneau d’erreur et prévoir un état de permission caméra avec consigne courte.

### Centre de maintenance : entretiens, historique et stock

- **Forces :** trois onglets thématiques, cartes répétables, retard signalé par icône/couleur, bouton de programmation placé sous la liste.
- **À surveiller :** l’onglet stock expose explicitement des quantités fictives; les entretiens créés sont enregistrés localement et l’historique est distant si Supabase est configuré. Ces sources différentes ne sont pas visibles au premier coup d’œil. Le dialogue de planification choisit son équipement depuis `Equipment.demo`.
- **Piste :** afficher une étiquette « Démonstration » persistante sur le stock et distinguer « enregistré sur cet appareil » des données synchronisées dans les listes concernées.

### Notifications et cloche

- **Forces :** badge de non-lus, icônes par événement, priorité, date, fond différencié pour le non-lu, marquage individuel ou global.
- **À surveiller :** lorsque la liste est vide, l’écran remplace entièrement le contenu par l’état vide et ne conserve pas le bandeau de page habituel; les boutons/états d’erreur ont un traitement distinct.
- **Piste :** maintenir titre et contexte même quand la liste est vide, et utiliser le même composant d’état vide/erreur que les autres pages.

### Profil

- **Forces :** page très lisible, compte et rôle regroupés, action de déconnexion immédiatement repérable.
- **À surveiller :** la déconnexion rouge foncé est isolée de la palette principale; le profil ne propose aucune autre information ou action.
- **Piste :** conserver la simplicité; ajouter une confirmation seulement si la déconnexion peut faire perdre une saisie non synchronisée.

### Revue d’un signalement par le chef d’unité

- **Forces :** feuille modale adaptée à la revue rapide; affectation, échéance, pièces jointes, chronologie, statut, observation et sauvegarde regroupés sans quitter la liste.
- **À surveiller :** le contenu est très long et dense, avec plusieurs menus, champs, pièces jointes et historique dans la même colonne. Sur téléphone, clavier et formulaire peuvent pousser le bouton d’enregistrement très bas.
- **Piste :** conserver les commandes de statut/affectation visibles tôt, séparer le résumé et la chronologie, et garder le bouton de sauvegarde accessible au-dessus du clavier.

## 4. Recommandations de mise en œuvre par ordre

1. **Clarifier le mode local sur le dashboard** : supprimer le faux message de panne Supabase et afficher des données locales, une vue de démonstration clairement nommée ou une limite fonctionnelle expliquée.
2. **Traiter les grands écrans** : éviter le chevauchement FAB/contenu et reconsidérer la barre inférieure lorsque la largeur dépasse la tablette.
3. **Normaliser les états visuels** : une source centrale pour turquoise, orange, rouge, vert, fonds doux, contrastes et libellés de statut.
4. **Alléger les longs flux** : regroupement visuel et action de sauvegarde accessible dans les formulaires et feuilles modales.
5. **Uniformiser les états vides/erreurs** : même squelette de page, même ton, distinction entre mode local, absence de données, échec réseau et schéma distant.
6. **Évaluer sur plusieurs tailles réelles** : petit téléphone (320–360 px), téléphone standard, tablette et navigateur de bureau; contrôler spécialement la navigation, le clavier, le FAB et les textes longs.

## 5. Limites de l’audit

Le tableau de bord local a été observé dans la capture fournie par l’utilisateur. Le navigateur headless lancé séparément reste sur le chargeur et ne permet pas d’interagir avec les autres routes. Les pages secondaires ont donc été auditées à partir du code Flutter et de leurs composants, sans prétendre à une validation visuelle en direct. Les captures headless se trouvent dans `design-analyse/` et sont étiquetées comme telles.

### Sources principales examinées

- Démarrage, thème et marque : `lib/main.dart`, `lib/core/vigimat_brand.dart`, `lib/core/mali_identity.dart`.
- Modes et données : `lib/core/supabase_config.dart`, `lib/services/dashboard_service.dart`, `lib/services/equipment_repository.dart`, `lib/services/local_report_store.dart`.
- Dashboards et rôles : `lib/features/home/reports_home_page.dart`, `lib/features/dashboard/dashboard_overview.dart`, `lib/features/chief/chief_dashboard_page.dart`, `lib/features/auth/auth_gate.dart`.
- Parcours métier : `lib/features/reports/report_form_page.dart`, `lib/features/reports/report_tracking_page.dart`, `lib/features/equipment/equipment_pages.dart`, `lib/features/equipment/equipment_edit_page.dart`, `lib/features/maintenance/maintenance_support_page.dart`.
- Services annexes : `lib/features/notifications/notification_center_page.dart`, `lib/features/profile/profile_page.dart`.
