# mLINKS

Version personnelle de QuickLinks (Appyogi) : liens vers applis, dossiers, fichiers et adresses web, depuis la barre
des menus ou par raccourci global. Swift, sans bac à sable : aucun blocage sur les disques externes.

- Interface : suivre le design system Socle (https://claude.ai/artifact/TkNj2Y6SQGZwT6EyME92Ah). `Sources/mLINKS/Socle.swift`
  est recopié de Socle par `build_app.sh`, ne pas le modifier ici.
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr d'abord, puis en, es, it), un test vérifie les clés.
- Données : `~/Library/Application Support/mLINKS/links.json` (`MLINKS_DATA_DIR` pour les essais).
- Rien de ce qui touche un volume externe ne s'exécute sur le fil principal (`LinkStore.refreshTargets`, `Opener`).
- Essais sans fenêtre : `mLINKS --capture sortie.png`, `--capture-about sortie.png`, `--capture-chooser sortie.png`, `--import fichier`.
- Menu Services (`Services.swift`, déclaré dans `NSServices` par `build_app.sh`, nom traduit par `Resources/<langue>.lproj/InfoPlist.strings`) : « Ajouter à mLINKS » sur un volume, un dossier, une appli ou un fichier du Finder, ou sur une adresse sélectionnée (barre d'adresse d'un navigateur ; `LinkItem.webTarget(fromText:)` complète « https:// »). Plusieurs groupes : panneau de choix à la souris (`AddLink`), un seul : ajout direct ; un lien déjà dans le groupe est ignoré. Essai de bout en bout : lancer l'appli avec `MLINKS_DATA_DIR` et `MLINKS_SERVICE_GROUP=<groupe>` (aucune fenêtre), puis appeler `NSPerformService("Add to mLINKS", pasteboard)`. Doc obligatoire (READMEs, section « Ajout depuis n'importe où ») : le service est dans le sous-menu Services du clic droit et s'active dans Réglages Système › Clavier › Raccourcis clavier › Services (Fichiers et dossiers, Texte) ; le rappeler partout où le service est présenté (écran d'accueil, guide ou visite guidée s'il en existe un). Après un changement du plist : `/System/Library/CoreServices/pbs -update`.
- Tests : `swift test`. Build et installation (dans ~/Applications/Applications Personnelles) : `./build_app.sh` ou `build_all.sh mLINKS`.
- Menu de la barre des menus : titres colorés par `MenuStyle` (`attributedTitle`) : la couleur d'un groupe (`LinkGroup.color`, #RRGGBB choisi dans la fenêtre de gestion parmi `GroupColor.palette`) et « Gérer les liens… » en jaune Socle (`Socle.C.action`) ; le nom de l'appli reste en texte normal dans les menus (règle Socle du 04/11/2026). `mLINKS --dump-menu` décrit le menu et ses couleurs sans l'afficher.
- Mise à jour automatique : `UpdateManager` lit la dernière release GitHub (mLINKS.zip), vérifie la signature Developer ID (équipe 35KLMK53PN) et la notarisation, remplace l'appli et la relance. Publier : `scripts/release.sh <version>`.
