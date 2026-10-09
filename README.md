# TP – Flashshop

## 🎯 Objectif
Déployer une petite boutique en ligne sur GCP avec une architecture **modulaire** :
- réseau (VPC, NAT, firewalls)
- groupe d’instances géré (MIG) avec auto‑scaling
- load‑balancer (HTTP/HTTPS) et Cloud Armor
- observabilité : alerte email quand l’utilisation CPU d’une VM dépasse le seuil configuré.

## 📂 Structure du dépôt
```
flashop_prod/
│   README.md          ← (ce fichier)
│   startup.sh         ← script d’initialisation local
│
├─ envs/               ← environnements (lab, prod…)
│   └─ lab/            ← configuration de test
│       ├─ main.tf     ← agrège les modules
│       ├─ variables.tf
│       └─ terraform.tfvars   ← valeurs concrètes (ex. notification_email)
│
└─ modules/            ← modules réutilisables
    ├─ network/        ← VPC, sous‑réseau, NAT, firewalls
    ├─ web_fleet/      ← instance template, MIG, autoscaling
    ├─ edge/           ← load‑balancer, Cloud Armor, SSL
    └─ observability/  ← monitoring, canal de notification, alerte CPU
```

## 🧩 Modules (résumé)
| Module | Rôle | Fichier principal |
|--------|------|-------------------|
| **network** | Crée le VPC, le sous‑réseau, le NAT et les règles firewall. | `modules/network/main.tf` |
| **web_fleet** | Déploie un **Managed Instance Group** avec autoscaling basé sur la CPU. | `modules/web_fleet/main.tf` |
| **edge** | Provisionne le **load‑balancer** (HTTP/HTTPS) et la politique Cloud Armor. | `modules/edge/main.tf` |
| **observability** | Définit un canal de notification e‑mail et une alerte qui se déclenche quand `compute.googleapis.com/instance/cpu/utilization` dépasse `cpu_threshold_percent`. | `modules/observability/main.tf` |

## ⚙️ Variables d’environnement (`envs/lab/variables.tf`)
```hcl
variable "region" {}            # ex. "europe-west9"
variable "machine_type" {}     # type de VM pour le MIG
variable "app_version" {}      # version de l’application
variable "notification_email" {} # adresse e‑mail pour les alertes
```
Ces variables sont injectées dans les modules via `envs/lab/main.tf`.

## 🚀 Déploiement rapide
```bash
cd flashop_prod               # se placer à la racine du projet
terraform init                # installer le provider Google
terraform plan -var-file=envs/lab/terraform.tfvars
terraform apply -var-file=envs/lab/terraform.tfvars
```
Après l’application, l’IP publique du load‑balancer est affichée ; ouvrez‑la dans un navigateur.

## 📈 Observabilité
Le module **observability** crée :
- `google_monitoring_notification_channel.email` : canal e‑mail (adresse définie par `notification_email`).
- `google_monitoring_alert_policy.cpu_high` : alerte déclenchée quand l’utilisation CPU dépasse `cpu_threshold_percent` (par défaut **70 %**) pendant `duration_seconds` (par défaut **300 s**).


## 🛠️ Bonnes pratiques
- Gardez les valeurs sensibles (e‑mail, secrets) dans `terraform.tfvars` et ne les commitez pas.
- Utilisez `terraform destroy` pour nettoyer les ressources après les tests.

