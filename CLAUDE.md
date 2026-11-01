# mLINKS

Version personnelle de QuickLinks (Appyogi) : liens vers applis, dossiers, fichiers et adresses web, depuis la barre
des menus ou par raccourci global. Swift, sans bac à sable : aucun blocage sur les disques externes.

- Interface : suivre le design system Socle (https://claude.ai/artifact/TkNj2Y6SQGZwT6EyME92Ah). `Sources/mLINKS/Socle.swift`
  est recopié de Socle par `build_app.sh`, ne pas le modifier ici.
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr d'abord, puis en, es, it), un test vérifie les clés.
- Données : `~/Library/Application Support/mLINKS/links.json` (`MLINKS_DATA_DIR` pour les essais).
- Rien de ce qui touche un volume externe ne s'exécute sur le fil principal (`LinkStore.refreshTargets`, `Opener`).
- Essais sans fenêtre : `mLINKS --capture sortie.png`, `--capture-about sortie.png`, `--import fichier`.
- Tests : `swift test`. Build et installation : `./build_app.sh` ou `build_all.sh mLINKS`.
