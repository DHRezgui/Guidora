# Guidora

Guidora is a multi-tenant platform for creating and delivering guided tours,
contextual help, searchable FAQs, and proactive in-app assistance.

This repository is the local integration workspace for the Guidora services.

| Component | Repository | Purpose |
| --- | --- | --- |
| Backend | [Guidora-backend](https://github.com/DHRezgui/Guidora-backend) | NestJS API, authentication, tours, tracking, FAQ, and ML endpoints |
| Dashboard | [Guidora-dashboard](https://github.com/DHRezgui/Guidora-dashboard) | Next.js administration interface |
| Machine learning | [Guidora-ml](https://github.com/DHRezgui/Guidora-ml) | LightGBM training, semantic FAQ search, and risk inference |
| React SDK | [Guidora-sdk](https://github.com/DHRezgui/Guidora-sdk) | React and Next.js integration package |

## Architecture

The dashboard and client SDK communicate with the backend API. The backend
uses PostgreSQL for persistent data, Redis for caching and coordination, and
RabbitMQ for asynchronous tracking work. The ML component is mounted into the
backend container for semantic FAQ search and abandonment prediction.

## Prerequisites

- Docker Engine 20.10 or newer
- Docker Compose v2
- Git with submodule support

## Clone the workspace

```bash
git clone --recurse-submodules https://github.com/DHRezgui/Guidora.git
cd Guidora
```

If the repository was cloned without submodules:

```bash
git submodule update --init --recursive
```

## Run the full stack

The root Compose file starts PostgreSQL, Redis, RabbitMQ, pgAdmin, the backend,
and the dashboard.

```bash
cp .env.example .env
docker compose up --build -d
docker compose ps
```

On Windows PowerShell, use `Copy-Item .env.example .env` instead of `cp`.

Default local endpoints:

| Service | URL |
| --- | --- |
| Backend API | http://localhost:3002/api/v1 |
| Swagger documentation | http://localhost:3002/api/v1/docs |
| Dashboard | http://localhost:3003 |
| pgAdmin | http://localhost:5050 |
| RabbitMQ management | http://localhost:15672 |

The values in `.env.example` are development defaults only. Change passwords
and credentials before using the stack outside a local environment.

Stop the stack with:

```bash
docker compose down
```

Add `-v` only when you intentionally want to delete local service volumes.

## Component development

- [Backend development](backend/README.md)
- [Dashboard development](dashboard/README.md)
- [ML development](ml/README.md)
- [React SDK development](sdks/react/README.md)

The `docs/` directory is local project documentation and is intentionally not
part of this public repository.

## Security

Never commit `.env` files, tokens, passwords, private keys, production
credentials, or model data containing personal information. Use the example
environment files as templates and rotate any credential that may be exposed.

## License

The component package metadata declares the MIT license. Add a repository-level
`LICENSE` file before publishing a formal open-source release.


