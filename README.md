# Guidora

Guidora is a multi-tenant platform for creating and delivering guided tours,
contextual help, searchable FAQs, and proactive in-app assistance.

## What is Guidora?

Software users often get stuck when they encounter an unfamiliar screen,
cannot find the next action, or need an answer while completing a task.
Guidora helps product teams support users directly inside their web
application, without sending them to a separate help center or requiring a
support agent for every question.

With Guidora, a product team can:

- create guided tours that explain a workflow step by step;
- display contextual help and searchable FAQs next to the current task;
- collect interaction and friction signals from the user journey;
- identify users who may abandon a workflow and offer proactive assistance;
- manage tours, content, organizations, projects, and SDK access from a central
  dashboard.

## How it works

1. An administrator creates and publishes a tour or help content in the
	dashboard.
2. A developer integrates the React SDK into the product application.
3. The SDK displays the relevant tour, FAQ, or contextual suggestion in the
	user's current interface.
4. The backend stores configuration and interaction events, and serves the
	appropriate content to each organization and project.
5. Optional ML services analyze friction and abandonment risk so the product
	can offer help at the right moment.

Guidora is designed for SaaS product teams, developers integrating in-app
experiences, and end users who need guidance while completing a workflow.

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

- [Backend development](https://github.com/DHRezgui/Guidora-backend/blob/newDevelop/README.md)
- [Dashboard development](https://github.com/DHRezgui/Guidora-dashboard/blob/newDevelop/README.md)
- [ML development](https://github.com/DHRezgui/Guidora-ml/blob/newDevelop/README.md)
- [React SDK development](https://github.com/DHRezgui/Guidora-sdk/blob/newDevelop/react/README.md)

The `docs/` directory is local project documentation and is intentionally not
part of this public repository.

## Security

Never commit `.env` files, tokens, passwords, private keys, production
credentials, or model data containing personal information. Use the example
environment files as templates and rotate any credential that may be exposed.

## License

The component package metadata declares the MIT license. Add a repository-level
`LICENSE` file before publishing a formal open-source release.


