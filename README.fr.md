# NotesBridge

[English](./README.md) | [简体中文](./README.zh-CN.md) | [Français](./README.fr.md)

[![CI](https://img.shields.io/github/actions/workflow/status/peizh/NoteBridge/ci.yml?branch=main&label=CI)](https://github.com/peizh/NoteBridge/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/network/members)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

![NotesBridge social banner](./images/notesbridge-social.svg)

NotesBridge est une application compagnon native macOS pour Apple Notes. Elle fonctionne comme une app de barre de menus, ajoute des améliorations d'édition en ligne au-dessus d'Apple Notes et exporte les notes vers des fichiers et dossiers Markdown locaux que vous pouvez conserver, rechercher, versionner et utiliser avec des agents IA.

## État du projet

NotesBridge est une application compagnon macOS en développement actif, destinée aux personnes qui reçoivent ou organisent des notes dans Apple Notes, mais qui veulent conserver une version de référence fiable à long terme dans des fichiers et dossiers Markdown locaux.

La version en téléchargement direct se concentre actuellement sur deux objectifs :

- ajouter des outils d'édition en ligne dans Apple Notes, comme les slash commands et les déclencheurs de style Markdown
- synchroniser Apple Notes vers des dossiers locaux de style Obsidian, en préservant la structure des dossiers, les pièces jointes, le front matter, les liens internes et les autres éléments associés

Apple Notes est très pratique pour l'édition simple sur téléphone ou pour les notes partagées avec la famille et les amis. NotesBridge transforme cette matière partagée en un espace de travail Markdown plus simple à organiser, automatiser, versionner et faire exploiter par des agents IA.

Si vous utilisez déjà Apple Notes pour la capture et Obsidian, ou d'autres applications de notes local-first, pour l'organisation à long terme, NotesBridge est conçu pour ce flux de travail.

## Pourquoi l'essayer

- Utiliser des slash commands et des outils de mise en forme directement au-dessus d'Apple Notes.
- Fonctionner comme une application légère de barre de menus macOS au lieu de remplacer votre flux de prise de notes.
- Préserver la structure Apple Notes sous forme de vrais fichiers et dossiers Markdown.
- Conserver les pièces jointes natives, les scans exportés, les tableaux et les liens internes entre notes.
- Rendre les notes synchronisées plus faciles à rechercher, versionner et traiter avec des agents IA.

## Démarrage rapide

1. Téléchargez le dernier build en téléchargement direct depuis [Releases](https://github.com/peizh/NoteBridge/releases).
2. Déplacez `NotesBridge.app` dans `/Applications`.
3. Lancez l'application et accordez les autorisations macOS demandées.
4. Choisissez votre dossier de données Apple Notes lors de la première synchronisation complète.
5. Commencez à synchroniser vers votre coffre Obsidian.

## Ce que l'application fait aujourd'hui

- Fonctionne comme une application compagnon de barre de menus avec une fenêtre de réglages légère.
- Affiche une barre d'outils de formatage flottante après sélection du texte, avec des actions rapides pour les titres, le gras, l'italique, le barré et d'autres opérations de mise en forme.
- Convertit les déclencheurs markdown / liste en début de ligne en commandes de formatage natives Apple Notes.
- Prend en charge les slash commands avec exécution sur correspondance exacte en ligne et un menu flottant de suggestions.
- Synchronise Apple Notes vers des dossiers locaux avec métadonnées front matter et export natif des pièces jointes.

## Contraintes produit

Apple Notes n'expose aucune API publique de plugin ou d'extension. NotesBridge se comporte donc comme une application compagnon plutôt que comme une véritable extension intégrée à Notes.

L'implémentation actuelle reste volontairement prudente :

- Les améliorations en ligne dépendent d'Accessibility et de la synthèse d'événements ; la version en téléchargement direct est donc le principal véhicule pour l'expérience complète.
- Le sens principal de synchronisation aujourd'hui est Apple Notes -> dossiers locaux, sans synchronisation inverse.
- Les slash commands prennent actuellement en charge la forme « commande exacte + espace » et la sélection des suggestions à la souris, sans nécessiter Input Monitoring.
- La synchronisation complète demande de choisir le dossier macOS `group.com.apple.notes` afin que NotesBridge puisse lire directement la base de données Apple Notes et les fichiers binaires des pièces jointes.

## Soutien

Si NotesBridge vous est utile dans votre flux de travail, vous pouvez soutenir la maintenance continue du projet et les coûts de publication via le bouton Sponsor sur GitHub.

Ce soutien aide à couvrir le temps passé sur les correctifs, les releases, la signature / notarization et l'entretien général du projet. Il ne crée pas de SLA de support et ne garantit pas une priorité de développement.

## Licence

MIT. Voir [LICENSE](./LICENSE).
