\## Environnement de Développement (Docker)



\### Prérequis

\- Docker Engine 20.10+ (\[installation](https://docs.docker.com/engine/install/))

\- Docker Compose 2.0+ (inclus dans Docker Desktop)



\### Démarrage rapide

```bash

\# 1. Copier le template des variables d'environnement

cp .env.example .env



\# 2. Démarrer les services en arrière-plan

docker-compose up -d



\# 3. Vérifier l'état des containers

docker-compose ps

\#  Tous les services doivent afficher "Up (healthy)"


