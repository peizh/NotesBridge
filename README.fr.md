# NotesBridge

[English](./README.md) | [简体中文](./README.zh-CN.md) | [Français](./README.fr.md)

[![CI](https://img.shields.io/github/actions/workflow/status/peizh/NoteBridge/ci.yml?branch=main&label=CI)](https://github.com/peizh/NoteBridge/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/network/members)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

![NotesBridge social banner](./images/notesbridge-social.svg)

> Ce document peut être légèrement en retard par rapport à la version anglaise.

NotesBridge est une application compagnon native pour macOS dédiée à Apple Notes. Elle fonctionne dans la barre de menus, ajoute des améliorations d'édition en ligne à Apple Notes et exporte les notes vers un coffre Obsidian.

## État du projet

NotesBridge est en développement actif. La version macOS distribuée en direct reste l'expérience principale, et l'intégration avec Apple Notes dépend actuellement des autorisations macOS locales ainsi que d'un accès direct au conteneur de données Apple Notes.

## Ce que fait actuellement ce prototype

- Fonctionne comme une application compagnon dans la barre de menus avec une fenêtre de réglages légère.
- Surveille Apple Notes lorsqu'il est au premier plan et que l'éditeur a le focus.
- Affiche une barre d'outils de mise en forme flottante au-dessus du texte sélectionné dans les builds pris en charge.
- Convertit les déclencheurs Markdown / listes en début de ligne en commandes de formatage natives Apple Notes.
- Prend en charge les slash commands, avec exécution immédiate des commandes exactes et menu flottant de suggestions.
- Synchronise Apple Notes vers un coffre Obsidian avec métadonnées front matter et export natif des pièces jointes.

## Contraintes produit

Apple Notes n'expose aucune API publique de plugin ou d'extension. NotesBridge se comporte donc comme une application compagnon plutôt que comme une véritable extension intégrée à Notes.

L'implémentation actuelle reste volontairement prudente :

- Les améliorations en ligne dépendent d'Accessibility et de la synthèse d'événements ; la version distribuée directement est donc le principal véhicule pour l'expérience complète.
- La variante App Store peut être simulée avec `NOTESBRIDGE_APPSTORE=1`, ce qui désactive les améliorations Apple Notes en ligne tout en laissant les réglages et la synchronisation actifs.
- Le sens principal de synchronisation reste Apple Notes -> Obsidian.
- La navigation clavier du menu slash command peut nécessiter Input Monitoring ; si l'interception n'est pas disponible, les commandes exactes suivies d'un espace et la sélection à la souris restent utilisables.
- La synchronisation complète demande de choisir le dossier macOS `group.com.apple.notes` afin que NotesBridge puisse lire directement la base de données Apple Notes et les fichiers binaires des pièces jointes.

## Construire et lancer

```bash
./scripts/run-bundled-app.sh
```

C'est le point d'entrée recommandé pour le développement. Il construit l'exécutable SwiftPM, l'enveloppe dans une `NotesBridge.app` signée et lance l'application depuis `~/Library/Application Support/NotesBridge/NotesBridge.app`.

L'application bundle utilise désormais une exigence désignée stable, afin que les autorisations Accessibility et Input Monitoring restent attachées après les recompilations. Si vous aviez autorisé une ancienne version de NotesBridge et que l'application affiche encore `Required`, supprimez l'ancienne entrée dans Réglages Système puis ajoutez à nouveau l'application bundle actuelle.

Pour un lancement rapide sans bundle, vous pouvez toujours utiliser :

```bash
swift run
```

Mais `swift run` lance un exécutable nu ; les flux d'autorisation macOS qui dépendent d'un vrai bundle d'application, en particulier Input Monitoring pour la navigation clavier du menu slash, ne fonctionneront pas correctement dans ce mode.

Si vous souhaitez seulement reconstruire l'application `.app` sans la lancer :

```bash
./scripts/run-bundled-app.sh --build-only
```

Au premier lancement en mode bundle, macOS peut demander les autorisations Accessibility et Automation afin que NotesBridge puisse observer Apple Notes et synchroniser son contenu. La première synchronisation complète vous demandera aussi de choisir `~/Library/Group Containers/group.com.apple.notes`, afin que l'application puisse lire `NoteStore.sqlite` et les pièces jointes binaires.

## Prochaines étapes suggérées

1. Renforcer l'ancrage de sélection et le positionnement de la barre de formatage sur plusieurs écrans et dans les espaces plein écran.
2. Ajouter un index de synchronisation plus riche et un suivi incrémental des changements de notes.
3. Produire à partir de la même base de code des livrables distincts pour le téléchargement direct et l'App Store.

## License

MIT. Voir [LICENSE](./LICENSE).
