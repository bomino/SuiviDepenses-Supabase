# Guide d'utilisation — Suivi des Dépenses (Supabase)

Bienvenue dans **Suivi des Dépenses**, version Supabase. Cette édition fonctionne sans serveur dédié : votre application discute directement avec une base de données Supabase, et tout reste synchronisé en temps réel entre les membres de l'équipe.

Ce guide s'adresse aux **utilisateurs finaux** : administrateurs (chefs de projet) et superviseurs (chefs de chantier, contremaîtres). Pour la mise en place technique, voir [`SETUP.md`](./SETUP.md).

---

## Sommaire

1. [Présentation](#1-présentation)
2. [Premiers pas — créer un compte et se connecter](#2-premiers-pas--créer-un-compte-et-se-connecter)
3. [Pour les superviseurs](#3-pour-les-superviseurs)
4. [Pour les administrateurs](#4-pour-les-administrateurs)
5. [Reçus et photos](#5-reçus-et-photos)
6. [Synchronisation en temps réel](#6-synchronisation-en-temps-réel)
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
| **Admin** (chef de projet) | Voir **toutes** les dépenses de **tous les projets**. Créer/renommer/supprimer des projets. Affecter chaque utilisateur à un projet. Promouvoir/rétrograder les autres admins. Modifier ou supprimer n'importe quelle dépense. |
| **Superviseur** (par défaut) | Voir uniquement les dépenses qu'il a saisies, **sur le projet auquel il est affecté**. Ajouter, modifier, supprimer ses propres dépenses. Joindre une photo de reçu à chaque dépense. |

**Multi-projet** — une seule installation peut suivre plusieurs chantiers en parallèle (ex. « Villa Tower », « Rénovation 14e »). Les superviseurs ne voient que leur chantier ; l'admin voit tout, en temps réel.

---

## 2. Premiers pas — créer un compte et se connecter

À la différence de la version Tier 2, **vous créez votre compte vous-même** ; il n'y a pas de mot de passe à demander à un admin.

### 2.1 Créer un compte

1. Ouvrez l'URL de l'application (fournie par votre administrateur).
2. Sur l'écran de connexion, cliquez sur l'onglet **Inscription**.
3. Saisissez votre **e-mail** et un **mot de passe** (minimum 6 caractères).
4. Cliquez sur **Créer un compte**.
5. *(Selon la configuration)* Vérifiez votre boîte mail et cliquez sur le lien de confirmation.
6. Revenez sur l'écran de connexion, onglet **Connexion**, et entrez vos identifiants.

> 📌 **Le tout premier utilisateur** d'une nouvelle installation devient automatiquement admin. Les suivants sont des superviseurs par défaut.

### 2.2 Connexion avec lien magique (sans mot de passe)

Si vous oubliez votre mot de passe, ou si vous préférez ne pas en saisir :

1. Onglet **Lien magique** sur l'écran de connexion.
2. Saisissez votre e-mail → **Envoyer le lien magique**.
3. Vous recevez un e-mail avec un bouton de connexion. Cliquez dessus depuis le **même appareil** où vous avez demandé le lien.
4. Vous êtes connecté(e), sans mot de passe.

### 2.3 Mot de passe oublié

Onglet **Connexion** → bouton **Mot de passe oublié ?** → e-mail → vous recevez un lien pour définir un nouveau mot de passe.

---

## 3. Pour les superviseurs

### 3.1 Aperçu de l'écran

Une fois connecté(e), vous voyez :

- **En-tête** : titre **Suivi des Dépenses**, le nom du chantier auquel vous êtes affecté(e), une pastille **En ligne** (vert), et les boutons **FR/EN**, **Exporter**, **Tout effacer**, **Déconnexion**.
- **Tableau de bord** : 4 cartes — Total, Payé, Impayé, Attente.
- **Formulaire** « Ajouter une dépense ».
- **Liste** des dépenses avec barre de filtres.

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

- **Ajouter** : saisissez un nom unique → **Ajouter un projet**.
- **Renommer** : bouton **Renommer** à côté du projet.
- **Supprimer** : bouton **Supprimer** (rouge).

> ⚠️ Supprimer un projet **efface toutes ses dépenses et leurs reçus**, et **désaffecte les superviseurs** qui y étaient (ils restent inscrits mais voient « Aucun projet affecté »).

### 4.2 Gérer les utilisateurs

Contrairement à la version Tier 2, vous **n'ajoutez pas** les utilisateurs vous-même : ils s'inscrivent sur l'écran de connexion. Vous, en tant qu'admin, vous :

- **Affectez chaque utilisateur à un projet** via le menu déroulant à côté de son nom.
- **Promouvez ou rétrogradez** les autres admins via le bouton **Promouvoir admin** / **Rétrograder**.
- *(Pas de bouton supprimer en panneau pour l'instant — la suppression d'un compte se fait depuis le tableau Supabase Auth, pour respecter la séparation des préoccupations.)*

> Auto-protection : vous **ne pouvez pas** vous rétrograder vous-même.

### 4.3 Renommer le projet en cours

Cliquez sur le nom du chantier dans l'en-tête (à côté du crayon). C'est un raccourci pour renommer le projet auquel **vous-même** êtes affecté(e).

---

## 5. Reçus et photos

L'une des grosses nouveautés de cette version : chaque dépense peut avoir **une photo de reçu** attachée.

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

## 6. Synchronisation en temps réel

Quand un autre membre de l'équipe saisit, modifie ou supprime une dépense visible pour vous, **votre liste se met à jour automatiquement** sans rechargement.

Ça marche pour :
- Les superviseurs voient les dépenses qu'ils saisissent depuis un autre appareil (utile si vous saisissez en double sur téléphone et tablette).
- Les admins voient en temps réel les dépenses entrées par chaque superviseur de chaque chantier.

Pas besoin d'actualiser. Si la connexion réseau est rompue, les modifications faites pendant la coupure apparaissent à la reconnexion.

---

## 6.bis Travailler hors-ligne

L'application enregistre vos dépenses même sans connexion. Quand vous êtes hors réseau (sous-sol, ascenseur, zone blanche) :

- L'indicateur en haut affiche **Hors ligne (n en attente)** — `n` est le nombre de saisies à synchroniser.
- Vos nouvelles dépenses apparaissent dans la liste avec une icône 🕒 et un effet grisé : elles sont stockées sur votre téléphone.
- Dès que la connexion revient, elles partent automatiquement vers le serveur. L'icône 🕒 disparaît, l'effet grisé s'efface.
- Si une saisie est rejetée par le serveur (par exemple parce qu'un admin vous a retiré du projet entretemps), elle apparaît en rouge avec ⚠️. Vous pouvez la **réessayer** ou la **supprimer**.

La carte **Budget** affiche un cadre en pointillés tant que des saisies sont en attente : c'est un total approximatif (vos changements locaux + dernière valeur connue du serveur). Une fois la synchronisation faite, le cadre redevient plein.

---

## 7. Installer l'application sur votre téléphone

L'application est une **PWA** : installable comme une application native, fonctionne hors-ligne pour la consultation.

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

Quand votre administrateur déploie une nouvelle version, vous recevrez la nouvelle interface à la prochaine ouverture. Si vous voulez forcer immédiatement : ouvrez les paramètres de votre navigateur → **Effacer les données du site** → rechargez.

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
| « Identifiants invalides » à la connexion | Faute de frappe, ou mot de passe oublié | Bouton **Mot de passe oublié ?** ou onglet **Lien magique**. |
| Lien magique reçu mais ne fonctionne pas | Vous l'ouvrez sur un autre appareil que celui où vous l'avez demandé | Ré-envoyez et ouvrez sur le même appareil. |
| « Aucun projet affecté » bloque la saisie | L'admin ne vous a pas affecté(e) à un chantier | Contactez l'admin (§4.2). |
| Photo de reçu refusée | > 5 Mo, ou format non accepté | Compresser la photo (la plupart des téléphones ont une option « réduire la taille » dans l'écran de partage), ou prendre une nouvelle photo en qualité moyenne. |
| Pastille **Hors ligne** alors que vous avez du réseau | Déconnexion temporaire de Supabase | Patientez quelques secondes ; rechargez la page si ça persiste. |
| Mes saisies n'apparaissent pas chez l'admin en temps réel | Le canal Realtime n'est pas actif | Rechargez la page. Si ça persiste, l'admin doit vérifier que la migration #1 a bien activé Realtime sur la table `expenses` (voir [`SETUP.md`](./SETUP.md)). |
| Je vois des dépenses qui ne sont pas les miennes (en tant que superviseur) | Vous êtes admin sans le savoir | L'admin peut vérifier votre rôle dans **Gérer les utilisateurs**. |

Bonne gestion de chantier ! 🏗️
