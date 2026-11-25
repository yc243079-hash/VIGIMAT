# Rapport de design — VIGIMAT

**État observé le 24 novembre 2026.** Ce rapport décrit les interfaces définies dans le code Flutter et les ressources graphiques présentes dans le projet. Il couvre les parcours technicien et chef d’unité, les écrans secondaires et les règles visuelles partagées. La capture fournie confirme le rendu du dashboard local à `localhost:53155`; l’audit détaillé et ses recommandations sont dans `design-analyse/AUDIT_COMPLET.md`. Un essai Chrome headless séparé reste bloqué sur le chargeur et est documenté comme une limite de vérification, pas comme une panne avérée de cette session locale.

## 1. Vue d’ensemble

VIGIMAT est une application de maintenance au style d’outil métier : fond gris très clair, surfaces blanches, bleu marine pour la structure et les actions principales, turquoise pour les accents, et badges de couleur pour signaler les états. L’interface utilise Material 3, des icônes Material arrondies, des cartes à coins doux et une navigation inférieure adaptée au mobile.

La marque associe l’univers technique de la maintenance à l’identité malienne. Le drapeau et la devise apparaissent dans l’écran de connexion et dans l’en-tête des tableaux de bord. Le ton est institutionnel et opérationnel, avec des libellés directs et des statuts visibles.

## 2. Charte graphique actuelle

### Palette centrale

Les couleurs de référence sont déclarées dans `lib/core/vigimat_brand.dart`.

| Rôle | Nom dans le code | Couleur | Usage principal |
|---|---|---:|---|
| Bleu marine | `navy` | `#142B4A` | Titres, logo, boutons principaux, texte fort |
| Turquoise | `turquoise` | `#14B8A6` | Accent de marque, icônes, sélection, détails actifs |
| Fond d’application | `background` | `#F4F6FA` | Fond général des pages |
| Texte secondaire | `muted` | `#687386` | Aides, sous-titres, métadonnées |
| Bordure | `border` | `#E7EBF1` | Champs, séparateurs et contours discrets |
| Alerte / échéance | `orange` | `#F59E0B` | Avertissements et retards |
| Erreur / panne | `red` | `#DC2626` | Erreurs et pannes |
| Succès / opérationnel | `green` | `#16A34A` | États positifs |
| Fonds de badges | `redSoft`, `orangeSoft`, `greenSoft`, `turquoiseSoft` | `#FEE2E2`, `#FEF3C7`, `#DCFCE7`, `#CCFBF1` | Pastilles et icônes sur fond doux |

### Couleurs complémentaires effectivement utilisées

Plusieurs écrans reprennent des variantes qui ne sont pas toutes rattachées aux constantes centrales. Elles font donc partie de l’apparence actuelle, même si elles forment un système moins uniforme :

| Usage | Couleurs observées |
|---|---|
| Bleu des dégradés et surfaces foncées | `#1B4266`, `#102B49`, `#123453`, `#071B31`, `#06172B` |
| Turquoise de statut / pictogrammes | `#18A6A6` (distinct du turquoise central `#14B8A6`) |
| Vert de statut | `#17815E` (distinct de `#16A34A`) |
| Orange de statut | `#B36B12` (distinct de `#F59E0B`) |
| Rouge de statut | `#B84242` (distinct de `#DC2626`) |
| Fonds doux additionnels | `#EAF4F4`, `#FFEFEA`, `#F8FBFD`, `#F3F6FA`, `#FFF1F0` |
| Texte clair sur fond sombre | `#D8E1ED`, `#B8CDE2` |
| Drapeau du Mali | vert `#14B53A`, jaune `#FCD116`, rouge `#CE1126` |

Les alertes de certains composants utilisent aussi les couleurs nommées Flutter (`Colors.red`, `Colors.deepOrange`, `Colors.blueGrey`). Les couleurs d’état restent compréhensibles, mais leurs nuances varient selon l’écran.

### Logo et identité

- **Symbole :** icône `settings_suggest_rounded` blanche, posée sur un carré bleu marine à coins arrondis, avec un point turquoise en bas à droite.
- **Version sur fond sombre :** carré translucide blanc et contour du point turquoise bleu marine.
- **Wordmark :** « VIGIMAT » en capitales, graisse forte et espacement de lettres augmenté. Un sous-titre optionnel indique « MAINTENANCE & SUIVI ».
- **Identité nationale :** drapeau du Mali en trois bandes verticales et devise « UN PEUPLE – UN BUT – UNE FOI ».
- **Visuel de connexion :** `assets/images/vigimat_login_hero.png`, une bannière illustrée avec le logo, le drapeau, un véhicule et un atelier de maintenance.

### Typographie et hiérarchie

Aucune police de marque ni famille personnalisée n’est déclarée. L’application repose donc sur la typographie par défaut de Flutter/Material selon la plateforme.

- Titres de page (`headlineSmall`) : 24 px, extra-gras, bleu marine, léger crénage négatif.
- Titres principaux (`titleLarge`) : 20 px, gras.
- Sous-titres (`titleMedium`) : 16 px, gras.
- Texte courant : couleur `#34445B`, hauteur de ligne 1,4.
- Texte secondaire : gris `#687386`, hauteur de ligne 1,35.
- Libellés compacts, badges et catégories : généralement 9–13 px, souvent en graisse moyenne ou forte.
- Dans les bandeaux de marque, les titres sont blancs et les petits textes bleu-gris clair.

### Composants, formes et profondeur

- **Fond :** `#F4F6FA`, avec des pages surtout composées de listes verticales.
- **Cartes :** blanches, rayon 18 px, contour discret `#E9EDF3`, ombre très légère bleu marine. Certaines cartes définissent leur propre rayon ou élévation.
- **Champs :** fond blanc, remplissage confortable, rayon 13 px, bordure grise; focus turquoise (1,5 px), erreur rouge.
- **Boutons pleins :** fond bleu marine, texte blanc, hauteur minimale 50 px, rayon 13 px. Les boutons secondaires sont contour gris et texte bleu marine.
- **Navigation :** barre Material 3 blanche, indicateur turquoise translucide, libellés 12 px; onglet actif bleu marine et plus gras.
- **Bandeaux de page :** dégradé marine `#142B4A` → `#1B4266`, rayon 20 px, icône turquoise dans un pavé translucide, ombre douce.
- **Pastilles :** fonds teintés à environ 10 % de la couleur de statut, forme capsule.
- **Icônes :** principalement Material Icons, avec formes arrondies et variantes en contour pour les états inactifs.
- **Espacement courant :** marges latérales de 16 à 20 px; espacements de 8, 10, 12, 16 et 20 px; certains blocs utilisent 22 à 28 px.

### Comportement responsive et animations

Les pages principales limitent la largeur à 1 120 px; la connexion à 460 px et l’édition d’équipement à 760 px. Les tableaux et grilles s’adaptent à la largeur : métriques en une à quatre colonnes, filtres d’équipement en une à trois colonnes, graphiques côte à côte à partir de 820 px. Les écrans restent majoritairement en défilement vertical sur téléphone.

Les animations sont sobres : apparition et léger déplacement du formulaire de connexion, transitions fondu/glissement entre les onglets principaux, apparition des cartes de métriques et animation des valeurs et graphiques. L’interface n’expose pas de thème sombre applicatif.

## 3. Interfaces et parcours

### Connexion et états d’accès

**Connexion.** Sur fond dégradé bleu nuit, contenu centré et limité à 460 px : carte d’identité malienne, bannière illustrée, puis panneau de connexion bleu translucide bordé de turquoise. Le panneau contient un titre, une phrase d’introduction, les champs e-mail et mot de passe, l’affichage/masquage du mot de passe, les erreurs de validation et un bouton turquoise « Se connecter ». Une note rappelle que les comptes et rôles sont administrés. L’écran s’adapte à la largeur de l’appareil et peut défiler verticalement.

**Session ou rôle non attribué.** Écran minimal sur fond standard avec logo, titre, message centré et bouton de déconnexion lorsqu’il est pertinent. Une erreur de session reprend ce format. Si Supabase n’est pas configuré, l’application ouvre directement l’espace local; sinon elle affiche la connexion puis dirige les comptes techniciens et chefs d’unité vers leur espace respectif.

### Tableau de bord partagé

L’en-tête réunit le wordmark sur fond dégradé, une pastille de rôle, un bouton d’actualisation, le message d’accueil et le drapeau/devise. Il est suivi d’accès rapides lorsqu’ils sont fournis, d’une grille de cartes chiffrées, puis d’une zone de graphiques. Les indicateurs sont accompagnés d’icônes colorées et leurs nombres s’animent à l’arrivée. Les états de chargement, l’erreur d’indicateurs et la conservation des dernières données ont chacun un rendu dédié.

- **Vue chef d’unité :** parc total, pannes, signalements en attente, équipements opérationnels/en maintenance, interventions en cours/terminées et préventif à venir. Graphiques : évolution des pannes sur six mois, répartition circulaire de l’état du parc, interventions réalisées et performance/taux de clôture.
- **Vue technicien :** interventions en cours, signalements en attente et équipements en panne en priorité; puis terminées, préventif à venir, parc total, opérationnels et en maintenance. Graphiques : interventions clôturées et taux de clôture sur six mois.
- Les graphiques sont dessinés avec `CustomPainter`; ils utilisent des repères et légendes compacts plutôt qu’une bibliothèque de visualisation externe.

### Espace technicien : onglets principaux

La barre inférieure contient quatre onglets : **Vue d’ensemble**, **Signalements**, **Équipements**, **Suivi**. Une cloche de notifications, l’accès au profil, l’actualisation et la déconnexion éventuelle sont dans la barre supérieure. Le bouton flottant étendu « Nouveau signalement » apparaît sur le tableau de bord et la liste des signalements.

1. **Vue d’ensemble technicien.** Tableau de bord personnalisé avec quatre accès rapides : nouveau signalement, équipements, mes interventions et notifications. En dessous, trois signalements récents avec accès « Tout voir ».
2. **Signalements.** Liste défilante avec bandeau d’accueil, carte d’état de connexion/synchronisation locale, nombre d’éléments et cartes cliquables. Chaque carte peut montrer une miniature, une référence, un équipement, un extrait de description, priorité, statut, état de synchronisation et présence d’un vocal. Affichage prévu pour chargement, erreur, liste vide et erreur de statut distant.
3. **Équipements.** Inventaire filtrable (voir la fiche détaillée ci-dessous); le technicien peut consulter les fiches et lancer un signalement depuis un équipement.
4. **Suivi.** Centre de maintenance à trois onglets : entretiens, historique et stock (détails plus bas).

### Espace chef d’unité

La barre inférieure offre trois onglets : **Tableau de bord**, **Équipements**, **Suivi**. La barre supérieure donne accès aux notifications, au profil, à l’actualisation et à la déconnexion.

- **Tableau de bord :** indicateurs globaux et graphiques de supervision, suivis d’une liste des derniers signalements. Chaque carte affiche référence/équipement, priorité, description, date, statut et pièces jointes éventuelles.
- **Examen d’un signalement :** toucher une carte ouvre une feuille modale remontant du bas de l’écran. Elle regroupe le résumé du signalement, les informations d’équipement/localisation/déclarant, l’affectation d’un technicien, le choix d’une échéance, les photos ou le vocal, la chronologie, le statut, une observation du chef et le bouton d’enregistrement. Les chargements internes ont des indicateurs linéaires.
- **Équipements :** même inventaire que le technicien, avec ajout et modification de fiches activés.
- **Suivi :** même centre de maintenance à trois onglets.

### Création d’un signalement

Écran avec AppBar « Nouveau signalement », bandeau « Déclarer un incident » puis formulaire en une colonne. Les sections sont : équipement concerné, catégorie de panne, localisation, description écrite, photographies, horodatage, agent déclarant, message vocal et priorité. Les sélecteurs d’équipement et de catégorie sont des menus; la date et l’identité sont présentées en lignes informatives; les priorités sont des `ChoiceChip`.

La prise de photo et la sélection de plusieurs photos sont proposées côte à côte; les aperçus ont un bouton de retrait. L’enregistrement vocal passe d’un bouton microphone à un contrôle d’écoute/suppression lorsque le clip existe. Le bouton final pleine largeur est bleu marine. Le formulaire affiche validation, erreurs de chargement et note sur la sauvegarde locale/synchronisation.

### Suivi d’un signalement

Écran de détail avec AppBar et bandeau chronologique. Une grande carte présente la référence, le badge d’état, l’équipement, la catégorie, le lieu, le déclarant, la date, la priorité et la description. Des photos apparaissent dans une galerie horizontale; le suivi distant s’affiche en frise verticale avec icônes, ligne de progression, statut, date et observations.

Pour le technicien affecté, une carte de mise à jour permet de modifier le statut parmi « assigné », « en cours », « en attente de pièces » et « résolu », d’ajouter un compte rendu et d’enregistrer. Si le signalement attend sa synchronisation, un message explique que le suivi en ligne sera disponible ensuite. Les erreurs distantes disposent d’un bouton de réessai.

### Inventaire des équipements

Le bandeau indique le nombre de résultats et la source des données. Il contient l’action de scan QR; le rôle chef dispose aussi d’un bouton d’ajout. En dessous : recherche par nom/référence/série, trois filtres (catégorie, état, localisation), puis les cartes d’équipement. Chaque carte montre une icône teintée par état, le nom, la référence, la catégorie, le statut et éventuellement le lieu. Les rendus vide, sans résultat, erreur et chargement sont prévus.

### Fiche équipement

La fiche commence par une grande photo (ou un pictogramme de remplacement), puis les badges d’état et référence, le nom et la catégorie. La section suivante rassemble marque, modèle, numéro de série, localisation, date d’acquisition, responsable/service et description dans une grille responsive. Un bloc QR affiche le code unique et sa référence. Un bouton pleine largeur propose de signaler une panne. La fin de page contient trois historiques : pannes, interventions et prochains entretiens. Le rôle chef voit aussi l’action de modification dans l’AppBar.

### Création et modification d’équipement

Formulaire centré, limité à 760 px, avec trois groupes : informations générales (photo, nom, référence, catégorie), identification technique (marque, modèle, série), affectation et état (localisation, responsable, état, date d’acquisition, description). La photo occupe un aperçu horizontal de 190 px avec actions appareil photo, galerie et retrait. Les champs réutilisent les champs Material blancs. Le bouton « Enregistrer la fiche » ferme le formulaire.

### Scanner QR

Vue caméra pleine page sous une AppBar « Scanner un équipement ». Un cadre blanc carré aux coins arrondis marque la zone de lecture; le premier QR reconnu ouvre la fiche correspondante. Une erreur caméra apparaît dans un panneau blanc en bas de l’image.

### Centre de maintenance

Le centre est intégré à l’onglet **Suivi**. Le bandeau « Centre de maintenance » est suivi d’une TabBar défilable avec trois contenus :

- **Entretiens :** cartes avec icône calendrier ou alerte, équipement, date, description et mention « À prévoir » si l’échéance est dépassée. Un bouton inférieur pleine largeur « Programmer un entretien » ouvre une boîte de dialogue avec équipement, description et date.
- **Historique :** cartes de journal avec icône outil, type d’événement, référence du signalement, statut, date et observation.
- **Stock :** liste de pièces avec quantité et seuil minimal. La quantité basse est mise en évidence à l’orange. Le code précise que ces quantités sont de démonstration.

### Notifications

La cloche dans l’AppBar porte un badge de non-lus (ou un indicateur d’erreur) et ouvre le centre. Ce dernier présente son titre dans l’AppBar, les actions « Tout marquer comme lu » et actualiser, puis le bandeau « Votre activité », le compte des notifications et une liste de cartes. Les cartes non lues ont un fond légèrement bleuté et titre plus gras; chaque notification montre une icône par type d’événement, priorité, texte, date et action de lecture. Les cartes vides, erreur et chargement sont prévues.

### Profil

Page courte et simple : carte dégradée avec logo, nom et rôle, carte blanche contenant le compte e-mail et le niveau d’accès, puis bouton rouge sombre « Se déconnecter » pleine largeur.

## 4. Cohérence visuelle et points à noter

1. **La base graphique est reconnaissable et stable :** bleu marine, turquoise, fond clair, cartes blanches, icônes de maintenance et signalisation des statuts forment le langage dominant.
2. **Les couleurs sémantiques sont dispersées :** les variantes `#18A6A6`, `#17815E`, `#B36B12` et `#B84242`, les fonds doux additionnels et les couleurs nommées Flutter coexistent avec les tokens. La même intention peut donc avoir une nuance différente d’un écran à l’autre.
3. **Les arrondis suivent une même famille, mais pas une valeur unique :** 12–14 px pour champs/boutons/petits visuels, 18–22 px pour cartes et grands bandeaux, jusqu’à 26–28 px dans la connexion.
4. **L’identité malienne est très visible à la connexion et dans les dashboards**, tandis que les pages secondaires utilisent surtout le langage VIGIMAT marine/turquoise.
5. **Le niveau typographique est cohérent, mais la famille n’est pas verrouillée.** Le rendu peut donc varier légèrement entre plateformes.
6. **Certaines surfaces ont un traitement particulier :** la connexion est nettement plus sombre et contrastée; le reste de l’application reste clair. Les écrans de formulaire et de détail alternent des sections titrées simples et des cartes sans toujours utiliser le bandeau commun.

## 5. Fichiers de référence

- Thème global : `lib/main.dart`
- Palette, logo et bandeau partagé : `lib/core/vigimat_brand.dart`
- Drapeau/devise : `lib/core/mali_identity.dart`
- Accès, rôles et connexion : `lib/features/auth/auth_gate.dart`
- Tableau de bord et navigation technicien : `lib/features/home/reports_home_page.dart`
- Tableau de bord et visualisations : `lib/features/dashboard/dashboard_overview.dart`
- Espace chef et revue modale : `lib/features/chief/chief_dashboard_page.dart`
- Formulaire et suivi de signalement : `lib/features/reports/report_form_page.dart`, `lib/features/reports/report_tracking_page.dart`
- Inventaire, fiche et scan : `lib/features/equipment/equipment_pages.dart`
- Édition d’équipement : `lib/features/equipment/equipment_edit_page.dart`
- Maintenance, notifications et profil : `lib/features/maintenance/maintenance_support_page.dart`, `lib/features/notifications/notification_center_page.dart`, `lib/features/profile/profile_page.dart`

## 6. Vérification de l’instance locale

La capture transmise par l’utilisateur montre le dashboard local à `http://localhost:53155/`. Le serveur répond en HTTP 200. Mon essai dans Chrome headless, avec un profil vierge, reste sur le chargeur aux ports 50904 et 53155; ce résultat n’est pas représentatif de la session Chrome existante. Le constat fonctionnel visible (mode local accompagné d’une erreur Supabase pour les indicateurs) et la limite de vérification sont détaillés dans [`design-analyse/ETAT_INSTANCE_LOCALE.md`](design-analyse/ETAT_INSTANCE_LOCALE.md). L’audit UX/visuel par écran se trouve dans [`design-analyse/AUDIT_COMPLET.md`](design-analyse/AUDIT_COMPLET.md).
