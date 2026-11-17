# mLINKS

[English](README.md)

Vos applications, dossiers, fichiers et adresses web à portée de clic, depuis la barre des menus de macOS ou par un raccourci clavier global.

## Fonctions

- **Menu de la barre des menus** : vos groupes en sous-menus, avec les icônes. ⌥ maintenu affiche l'élément dans le Finder au lieu de l'ouvrir.
- **Liens vers tout** : applis, dossiers, fichiers et adresses web. Une cible absente (disque débranché) est signalée « Introuvable » ; un disque externe endormi ne fige jamais le menu.
- **Raccourcis globaux** : un par lien, sans autorisation d'accessibilité.
- **Ajout depuis n'importe où (menu Services)** : clic droit sur un volume, un dossier, une application ou un fichier dans le Finder, ou sur une adresse sélectionnée dans la barre d'adresse de n'importe quel navigateur, puis **Services › Ajouter à mLINKS**. Avec plusieurs groupes, un petit panneau près du pointeur demande où placer le lien ; avec un seul, il y entre directement. Un court message confirme l'ajout, et un lien déjà présent dans le groupe n'est pas ajouté deux fois.
- **Fenêtre de gestion** : créer, renommer et réorganiser les groupes, glisser-déposer depuis le Finder, masquer des liens du menu.
- **Import depuis QuickLinks** : lit la base de QuickLinks (Appyogi) ou un export `.CSV`, sans jamais les modifier, et sans doublon en cas de réimport. Proposé sur l'écran d'accueil d'une bibliothèque vide, ou par `mLINKS --import fichier`.
- **Mises à jour automatiques** : cherche les releases GitHub une fois par jour (désactivable), vérifie la signature Developer ID et la notarisation, puis remplace et relance l'appli depuis le menu.
- **Quatre langues** (français, anglais, espagnol, italien), choisies d'après la langue du système.
- Interface sombre et plate ; pas d'icône dans le Dock ; lancement à l'ouverture de session en option.

## Compiler

Nécessite macOS 14+ et Xcode (Swift 6).

```bash
swift test          # tests unitaires
./build_app.sh      # compile mLINKS.app, le signe et l'installe
```

`NO_INSTALL=1 ./build_app.sh` produit `./mLINKS.app` sans l'installer. Sans identité de signature locale, l'appli est signée ad hoc. Les liens sont enregistrés dans `~/Library/Application Support/mLINKS/links.json`.

Les Services apparaissent d'eux-mêmes dans le menu du clic droit. Si « Ajouter à mLINKS » manque, cochez-le dans Réglages Système › Clavier › Raccourcis clavier › Services (Fichiers et dossiers, et Texte).

## À propos

mLINKS est une recréation personnelle, repartie de zéro, de l'idée de [QuickLinks](https://appyogi.com/webapps/index.php?product_id=40&source=com.appyogi.quicklinks&ref=about) d'Appyogi. Elle n'a aucun lien avec Appyogi et ne partage ni son code ni ses ressources.

mLINKS fait partie du **DESKTOP MAC TOOLKIT**, la collection d'applis macOS de Starbudweiser.

Auteurs : Starbudweiser & Claude Code (Anthropic). Licence MIT, © 2026 Starbudweiser. Fourni en l'état, sans garantie.
