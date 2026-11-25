# État de l’instance locale

**Date : 24 novembre 2026**  
**Adresse actuelle :** `http://localhost:53155/`  
**Ancienne adresse :** `http://localhost:50904/`

## Résultat

La capture fournie par l’utilisateur montre le tableau de bord technicien rendu dans Chrome à `localhost:53155`, avec le badge « Mode local ». Le serveur de cette adresse répond aussi en HTTP 200.

Dans mon propre Chrome headless, ouvert avec un profil vierge, les deux ports (ancien 50904 et actuel 53155) restent sur la barre de chargement Flutter. Les captures `01-headless-50904-chargeur.png` et `02-headless-53155-chargeur.png` documentent ce résultat. Ce décalage entre la capture utilisateur et un profil navigateur neuf signifie que l’essai headless n’est pas représentatif de la session Chrome déjà ouverte; il ne permet pas de conclure que l’application ne fonctionne pas.

## Contrôles effectués

- `GET http://localhost:50904/` : HTTP 200, `text/html`.
- `GET http://localhost:50904/flutter_bootstrap.js` : HTTP 200, `text/javascript`.
- `GET http://localhost:50904/main.dart.js` : HTTP 200, annoncé `application/javascript`; la réponse reçue fait 7 729 caractères et commence par le code CSS/JavaScript du chargeur Flutter.
- Le bundle local `build/web/main.dart.js` fait 3 451 212 octets. La différence avec la réponse servie indique que l’instance du port 50904 n’expose pas le même artefact que le build local observé; cela ne suffit pas à établir la cause.
- `GET http://localhost:53155/` : HTTP 200, `text/html`.
- Chrome headless a produit les deux captures d’écran de chargement mentionnées plus haut. Il n’a pas permis de parcourir l’application avec une nouvelle session.
- La capture utilisateur confirme néanmoins le rendu réel du tableau de bord local. L’audit de toutes les autres pages combine le code Flutter et les assets; elles n’ont pas été parcourues dans une session navigateur interactive.

## Constat fonctionnel visible sur la capture utilisateur

La capture montre « Mode local » en même temps que « Indicateurs indisponibles » et un message demandant de vérifier Supabase. Le code confirme la cause de cet état : `DashboardService.load()` lève une erreur lorsque Supabase n’est pas configuré, puis `DashboardOverview` affiche la carte d’erreur distante. Les autres fonctions locales existent, mais aucun indicateur de démonstration n’est affiché dans ce tableau de bord.

## Portée de l’analyse design

L’audit détaillé (`AUDIT_COMPLET.md`) s’appuie sur la capture fournie pour le dashboard local, sur les contrôles de l’instance et sur le code source de toutes les autres interfaces. Le blocage headless est conservé comme limite de vérification, pas comme défaut confirmé de l’application en session normale.
