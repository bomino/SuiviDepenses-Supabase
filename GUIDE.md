# Guide d'utilisation — Suivi des Dépenses (Supabase)

Bienvenue dans **Suivi des Dépenses**, version Supabase. Cette édition fonctionne sans serveur dédié : votre application discute directement avec une base de données Supabase, et tout reste synchronisé en temps réel entre les membres de l'équipe.

Ce guide s'adresse aux **utilisateurs finaux** : administrateurs (chefs de projet) et superviseurs (chefs de chantier, contremaîtres). Pour la mise en place technique, voir [`SETUP.md`](./SETUP.md).

---

## Sommaire

1. [Présentation](#1-présentation)
2. [Premiers pas — recevoir une invitation et se connecter](#2-premiers-pas--recevoir-une-invitation-et-se-connecter)
3. [Pour les superviseurs](#3-pour-les-superviseurs)
4. [Pour les administrateurs](#4-pour-les-administrateurs)
5. [Reçus et photos](#5-reçus-et-photos)
6. [Synchronisation en temps réel et travail hors-ligne](#6-synchronisation-en-temps-réel-et-travail-hors-ligne)
7. [Installer l'application sur votre téléphone](#7-installer-lapplication-sur-votre-téléphone)
8. [Trucs et astuces](#8-trucs-et-astuces)
9. [Dépannage](#9-dépannage)

---

## 1. Présentation

**À quoi sert l'application ?**
Saisir, classer et suivre toutes les dépenses d'un ou plusieurs chantiers — matériaux, main-d'œuvre, transport, permis, etc. — depuis un téléphone, une tablette ou un ordinateur. Les chiffres se mettent à jour pour toute l'équipe **en temps réel** (vous voyez les saisies des autres dans la seconde).

**Deux types d'utilisateurs :**

| Rôle | Ce qu'ils peuvent faire |
|---|---|
| **Admin** (chef de projet) | Voir **toutes** les dépenses de **tous les projets**. Créer/renommer/supprimer des projets. **Définir un budget par projet**. **Inviter et supprimer des utilisateurs**. Affecter chaque utilisateur à un projet. Promouvoir/rétrograder les autres admins. Modifier ou supprimer n'importe quelle dépense. |
| **Superviseur** (par défaut) | Voir uniquement les dépenses qu'il a saisies, **sur le projet auquel il est affecté**. Ajouter, modifier, supprimer ses propres dépenses. Joindre une photo de reçu à chaque dépense. **Travailler hors-ligne** ; ses saisies se synchronisent à la reconnexion. |

**Multi-projet** — une seule installation peut suivre plusieurs chantiers en parallèle (ex. « Villa Tower », « Rénovation 14e »). Les superviseurs ne voient que leur chantier ; l'admin voit tout, en temps réel, avec un **suivi du budget** par projet.

---

## 2. Premiers pas — recevoir une invitation et se connecter

L'accès à l'application est **sur invitation uniquement**. Vous ne pouvez pas créer un compte vous-même : votre administrateur vous envoie un lien d'invitation par e-mail.

### 2.1 Accepter l'invitation

1. Votre administrateur vous invite via le panneau **Gérer les utilisateurs**. Vous recevez un e-mail intitulé *« You have been invited »* (ou similaire).
2. Cliquez sur le lien dans l'e-mail. Vous arrivez sur l'application avec un écran **« Bienvenue — choisissez votre mot de passe »**.
3. Saisissez un mot de passe (minimum 6 caractères) et cliquez sur **Enregistrer le mot de passe**.
4. Vous êtes connecté(e). À partir de maintenant, vous vous connectez avec votre e-mail et ce mot de passe.

> 📌 Vous n'avez pas reçu d'e-mail ? Vérifiez le dossier spam, puis demandez à votre administrateur de relancer l'invitation.

### 2.2 Connexion habituelle

1. Ouvrez l'URL de l'application.
2. Saisissez votre e-mail et votre mot de passe.
3. Cliquez sur **Se connecter**.

### 2.3 Mot de passe oublié

Sur l'écran de connexion, cliquez sur **Mot de passe oublié ?** → saisissez votre e-mail → vous recevez un lien. En cliquant dessus, vous arrivez sur un écran **« Définir un nouveau mot de passe »** : saisissez le nouveau mot de passe, validez, vous êtes connecté(e).

---

## 3. Pour les superviseurs

### 3.1 Aperçu de l'écran

Une fois connecté(e), vous voyez :

- **En-tête** : titre **Suivi des Dépenses**, le nom du chantier auquel vous êtes affecté(e), une pastille **En ligne** (vert), et les boutons **FR/EN**, **Exporter**, **Tout effacer**, **Déconnexion**.
- **Tableau de bord** : 5 cartes — Total, Payé, Impayé, Attente, et **Budget** (visible si votre admin a défini un budget pour le projet ; voir §4.4).
- **Formulaire** « Ajouter une dépense ».
- **Liste** des dépenses avec barre de filtres et une colonne **Sync** indiquant les saisies en attente de synchronisation.

### 3.2 Ajouter une dépense

1. Remplissez le formulaire :
   - **Description** *(obligatoire)* — ex. « Sacs de ciment 50 kg ».
   - **Montant** *(obligatoire)* — chiffre positif.
   - **Catégorie** — Matériaux, Main-d'œuvre, Équipement, Permis, Sous-traitants, Transport, Services, Divers.
   - **Date** — préremplie à aujourd'hui.
   - **Payé par** — qui a réglé (texte libre).
   - **État** — **Payé**, **Attente**, ou **Impayé**.
   - **Remarques** — note libre, optionnelle.
   - **Photo du reçu** *(optionnel)* — voir §5.
2. Cliquez sur **Ajouter**.

### 3.3 Modifier ou supprimer

- ✎ (crayon) → modifier ; bouton devient **Mettre à jour**.
- ✕ (croix rouge) → supprimer (confirmation requise).

### 3.4 Filtrer

Au-dessus de la liste : Catégorie, État, période Du/Au, recherche texte. Le bouton **Réinitialiser** efface tous les filtres.

### 3.5 Exporter en CSV

Le bouton **Exporter** télécharge un fichier `.csv` des dépenses **visibles** (donc filtrées si des filtres sont actifs).

### 3.6 « Aucun projet affecté »

Si vous voyez ce message, votre admin ne vous a pas encore assigné(e) à un chantier. Demandez-lui ; tant que vous n'êtes pas affecté(e), vous ne pouvez pas saisir de dépense.

---

## 4. Pour les administrateurs

Le bouton **Gérer les utilisateurs** apparaît dans l'en-tête. Le panneau contient deux sections : **Projets** et **Utilisateurs**.

### 4.1 Gérer les projets

Pour chaque projet, vous pouvez :

- **Ajouter** : saisissez un nom unique → **Ajouter un projet**.
- **Définir un budget** : saisissez un montant et un seuil d'alerte (% — par défaut 80) → **Enregistrer**. Voir §4.4.
- **Renommer** : bouton **Renommer**.
- **Supprimer** : bouton **Supprimer** (rouge).

> ⚠️ Supprimer un projet **efface toutes ses dépenses et leurs reçus**, et **désaffecte les superviseurs** qui y étaient (ils restent inscrits mais voient « Aucun projet affecté »).

### 4.2 Inviter un utilisateur

Dans la section **Utilisateurs** :

1. Saisissez l'e-mail de la personne dans le champ **user@example.com**.
2. Cliquez sur **Inviter**.
3. La personne reçoit un e-mail avec un lien magique. En cliquant dessus, elle arrive sur l'application, choisit son mot de passe (§2.1), et se retrouve dans votre liste d'utilisateurs.
4. Pour les superviseurs, **affectez-les à un projet** via le menu déroulant à côté de leur ligne. Sans projet, ils ne peuvent pas saisir de dépense.

> 📌 **Étiquette « En attente »** — un utilisateur invité mais qui ne s'est jamais connecté apparaît avec une pastille orange « En attente ». Une fois qu'il s'est connecté, l'étiquette disparaît.

> 📌 **Limite d'envoi** — Supabase limite par défaut les e-mails d'invitation à environ 3 par heure (offre gratuite). Si vous invitez beaucoup d'utilisateurs, demandez à votre admin technique de configurer un fournisseur SMTP personnalisé (Resend, etc.).

### 4.3 Gérer les utilisateurs existants

Pour chaque ligne d'utilisateur, vous pouvez :

- **Affecter à un projet** via le menu déroulant.
- **Promouvoir admin** ou **Rétrograder** via le bouton correspondant.
- **Supprimer** (bouton rouge) — supprime définitivement l'utilisateur, **toutes ses dépenses et tous ses reçus**. Une confirmation est demandée.

> 🛡️ **Auto-protection** : vous **ne pouvez pas** vous rétrograder ni vous supprimer vous-même. Le bouton est désactivé sur votre propre ligne.

### 4.4 Suivre les budgets de projet

Dès qu'un budget est défini (§4.1), une **carte « Budget »** apparaît dans le tableau de bord pour tous les utilisateurs affectés à ce projet.

- **Vert** : moins de 80% du budget consommé (seuil ajustable).
- **Orange** : entre 80% et 100% du budget — alerte de proximité.
- **Rouge** + libellé **« Dépassement »** : budget dépassé.

Les saisies des **autres superviseurs sur le même projet** sont incluses dans le total — chacun voit le vrai total partagé, pas seulement ses propres saisies. Toute modification de budget (par l'admin) ou nouvelle dépense (par n'importe qui) met à jour la carte en temps réel sans recharger la page.

> 💡 Le budget est **informatif**, pas bloquant. Une dépense au-delà du budget est enregistrée normalement — c'est volontaire (les chantiers réels dépassent parfois leur budget et il faut quand même tout tracer).

### 4.5 Renommer le projet en cours

Cliquez sur le nom du chantier dans l'en-tête (à côté du crayon). C'est un raccourci pour renommer le projet auquel **vous-même** êtes affecté(e).

---

## 5. Reçus et photos

Chaque dépense peut avoir **une photo de reçu** attachée.

### Ajouter un reçu lors de la saisie

Dans le formulaire, le champ **Photo du reçu** accepte :
- JPEG, PNG, WebP (photos)
- PDF (factures scannées)
- Limite : **5 Mo** par fichier

Une fois la dépense enregistrée, la photo est uploadée sur Supabase Storage. Une icône 📎 apparaît dans la liste à côté de la ligne.

### Consulter un reçu

Cliquez sur l'icône 📎 dans la ligne. Une URL signée est générée à la volée (valide 60 secondes) et le reçu s'ouvre dans un nouvel onglet.

### Confidentialité des reçus

Chaque superviseur ne peut voir que **ses propres reçus**. Les admins peuvent tous les voir. La règle est appliquée au niveau de Supabase Storage (Row-Level Security), pas seulement dans l'interface — un utilisateur malveillant ne peut pas accéder aux reçus des autres en bricolant les requêtes.

---

## 6. Synchronisation en temps réel et travail hors-ligne

### 6.1 En temps réel

Quand un autre membre de l'équipe saisit, modifie ou supprime une dépense visible pour vous, **votre liste se met à jour automatiquement** sans rechargement.

Idem pour les changements de budget, le renommage de projet, et l'arrivée/départ d'utilisateurs dans le panneau d'administration.

### 6.2 Hors-ligne

L'application enregistre vos dépenses même sans connexion. Quand vous êtes hors réseau (sous-sol, ascenseur, zone blanche) :

- L'indicateur en haut affiche **Hors ligne (n en attente)** — `n` est le nombre de saisies à synchroniser.
- Vos nouvelles dépenses apparaissent dans la liste avec une icône 🕒 et un effet grisé : elles sont stockées sur votre téléphone.
- Dès que la connexion revient, elles partent automatiquement vers le serveur. L'icône 🕒 disparaît, l'effet grisé s'efface.
- Si une saisie est rejetée par le serveur (par exemple parce qu'un admin vous a retiré du projet entretemps), elle apparaît en rouge avec ⚠️. Vous pouvez la **réessayer** ou la **supprimer**.

La carte **Budget** affiche un cadre en pointillés tant que des saisies sont en attente : c'est un total approximatif (vos changements locaux + dernière valeur connue du serveur). Une fois la synchronisation faite, le cadre redevient plein.

> 💡 Vous pouvez fermer l'onglet (ou même redémarrer le téléphone) avec des saisies en attente — elles sont sauvegardées localement et seront envoyées dès la prochaine connexion.

---

## 7. Installer l'application sur votre téléphone

L'application est une **PWA** : installable comme une application native, fonctionne hors-ligne pour la consultation et la saisie.

### Sur Android (Chrome / Edge)

1. Ouvrez l'URL dans Chrome.
2. Bannière **« Installer pour un accès rapide »** au bas de l'écran → **Installer**.
3. *(Alternative)* Menu Chrome (⋮) → **Installer l'application** ou **Ajouter à l'écran d'accueil**.

### Sur iPhone / iPad (Safari)

1. Ouvrez l'URL dans **Safari** (pas Chrome — Safari uniquement sur iOS).
2. Touchez **Partager** (carré + flèche).
3. Faites défiler → **Sur l'écran d'accueil** → **Ajouter**.

### Sur ordinateur (Chrome, Edge)

1. Icône **Installer** dans la barre d'adresse → **Installer**.

---

## 8. Trucs et astuces

### 8.1 Mises à jour

Quand votre administrateur déploie une nouvelle version, vous recevez la nouvelle interface à la prochaine ouverture (le cache du navigateur est invalidé automatiquement à chaque déploiement). Si vous voulez forcer immédiatement : ouvrez les paramètres de votre navigateur → **Effacer les données du site** → rechargez.

### 8.2 Catégories disponibles

| Catégorie | Pour quoi |
|---|---|
| **Matériaux** | Ciment, sable, gravier, fer à béton, briques, peinture |
| **Main-d'œuvre** | Salaires des ouvriers, journées de chantier |
| **Équipement** | Location/achat d'outils, échafaudages, bétonnière |
| **Permis** | Frais administratifs, autorisations municipales |
| **Sous-traitants** | Plombier, électricien, peintre payés à la tâche |
| **Transport** | Carburant, location de camion, livraisons |
| **Services** | Eau, électricité du chantier, internet temporaire |
| **Divers** | Tout ce qui ne rentre pas dans les autres catégories |

### 8.3 États de paiement

- **Payé** — la dépense a été réglée.
- **Attente** — engagée mais en attente de validation/paiement.
- **Impayé** — somme due, non encore réglée.

### 8.4 Sauvegarde

Cliquez sur **Exporter** au moins une fois par semaine pour conserver une copie locale en CSV. C'est une assurance en cas de problème côté Supabase.

---

## 9. Dépannage

| Problème | Cause probable | Solution |
|---|---|---|
| « Configuration manquante » sur l'écran de connexion | L'admin n'a pas saisi l'URL/clé Supabase dans `index.html` | Voir [`SETUP.md`](./SETUP.md) §5. |
| Pas reçu l'e-mail d'invitation | Spam, ou limite d'envoi atteinte (3/h) | Vérifier le spam ; demander à l'admin de relancer plus tard. |
| Lien d'invitation amène sur une page 404 | URL de site mal configurée côté Supabase | Demander à l'admin de vérifier **Auth → URL Configuration** (voir [`SETUP.md`](./SETUP.md) §4). |
| « Identifiants invalides » à la connexion | Faute de frappe, ou mot de passe oublié | Cliquez sur **Mot de passe oublié ?**. |
| « Aucun projet affecté » bloque la saisie | L'admin ne vous a pas affecté(e) à un chantier | Contactez l'admin (§4.3). |
| Photo de reçu refusée | > 5 Mo, ou format non accepté | Compresser la photo, ou prendre une nouvelle photo en qualité moyenne. |
| Pastille **Hors ligne** alors que vous avez du réseau | Déconnexion temporaire de Supabase | Patientez ; rechargez la page si ça persiste. |
| Mes saisies n'apparaissent pas chez l'admin en temps réel | Le canal Realtime n'est pas actif | Rechargez la page. Si ça persiste, l'admin doit vérifier les migrations (voir [`SETUP.md`](./SETUP.md)). |
| Saisie en attente avec ⚠️ | Saisie rejetée par le serveur (RLS, projet retiré, etc.) | Cliquer **Réessayer** ou **Supprimer** sur la ligne concernée. |
| La carte Budget ne montre pas le bon total | Cache local décalé | Rechargez la page ; le total se recalcule via la base. |
| Je vois des dépenses qui ne sont pas les miennes (en tant que superviseur) | Vous êtes admin sans le savoir | L'admin peut vérifier votre rôle dans **Gérer les utilisateurs**. |

Bonne gestion de chantier ! 🏗️
