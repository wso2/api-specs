# WSO2 API Specifications Repository

This repository contains API contracts for various vendors and APIs in a standardized format. The goal of this repository is to provide a centralized location for API contracts that can be used for client/connector generation, testing, and documentation.

## Description

### Branching Strategy

The repository will contain two primary branches:

- `main`
- `incubator`

#### The `main` Branch

The `main` branch contains the official API contracts that are stable and verified.

#### The `incubator` Branch

The `incubator` branch contains API contracts that are under development, experimental, or non-official. An API contract can be added to this branch if it is not yet stable or verified. Once the API contract is stable and verified, it can be graduated to the `main` branch.

### Repository Structure

This centralized repository is for storing API contracts in a standardized format such as OpenAPI, GraphQL SDL, AsyncAPI, or other relevant specifications.

The repository structure would be organized as follows:

```shell

api-specs/
├── asyncapi/
├── dependabot/
├── graphql/
└── openapi/
```

> **Note:** Additional directories can be added in the future for other API contract specifications.

The repository root contains subdirectories for each contract type, such as `openapi`, `graphql`, and `asyncapi`. Each subdirectory contains API contracts for different vendors, APIs, and versions.

#### OpenAPI Contracts Directory Structure

The following is the directory structure for OpenAPI specifications:

1. Each vendor has their own directory. (E.g.: `openapi/google`, `openapi/hubspot`, etc.)
2. Within the vendor directory, each API has its own directory. (E.g.: `openapi/google/docs`, `openapi/hubspot/crm.associations`, etc.)
   > **Note:** If the vendor and the API name are the same, the directory names would be the same. (E.g.: `openapi/asana/asana`, `openapi/dayforce/dayforce`, etc.)
3. If the API is categorized hierarchically, the API directory would be named with the hierarchy, separated with a dot (`.`). (E.g.: `openapi/hubspot/crm.associations`, `openapi/hubspot/automation.actions`, etc.)
4. Within the API directory, another directory would be created for each version of the API. (E.g.: `openapi/google/calendar/v3`, `openapi/hubspot/automation.actions/v4`, etc.)
5. Apart from the OpenAPI spec version directory, each API directory contains an `icon.png` file that contains the logo of the API.
6. Inside the API version directory, the OpenAPI spec file would be named as `openapi.yaml` or `openapi.json`.
7. The relevant icon for the API would be placed in the API directory as `icon.png`.
8. A `.metadata.json` file would be placed in the API version directory to store metadata such as the API name, version, vendor, and other relevant information.

##### OpenAPI Metadata File Structure

The `.metadata.json` file would contain the following information:

- `name`: The human-readable name of the API.
- `baseUrl`: The base URL of the API. This is added in metadata to easily identify the base URL of the API without parsing the OpenAPI spec.
- `documentationUrl`: The URL to the API documentation, if available.
- `description`: A brief description of the API.
- `tags`: An array of tags that are relevant to the API.

```json
{
    "name": "Google Docs API",
    "baseUrl": "https://docs.googleapis.com",
    "documentationUrl": "https://developers.google.com/docs",
    "description": "API Description",
    "tags": ["tag1", "tag2"]
}
```

###### Example: OpenAPI Contracts Directory Structure

```text
api-specs/
└── openapi
    ├── asana
    │   └── asana
    │       ├── 1.0
    │       │   └── openapi.yaml
    │       └── icon.png
    ├── candid
    │   ├── charityCheckPdf
    │   │   ├── 1.0
    │   │   │   └── openapi.yaml
    │   │   └── icon.png
    │   ├── essentials
    │   │   ├── 1.0
    │   │   │   └── openapi.yaml
    │   │   └── icon.png
    │   └── premier
    │       ├── 1.0
    │       │   └── openapi.yaml
    │       └── icon.png
    ├── dayforce
    │   └── dayforce
    │       └── v1
    │           └── openapi.yaml
    ├── discord
    │   └── discord
    │       ├── 10
    │       │   └── openapi.yaml
    │       └── icon.png
    ├── docusign
    │   ├── admin
    │   │   ├── icon.png
    │   │   └── v2.1
    │   │       └── openapi.yaml
    │   ├── click
    │   │   ├── icon.png
    │   │   └── v1
    │   │       └── openapi.yaml
    │   └── esign
    │       ├── icon.png
    │       └── v2.1
    │           └── openapi.yaml
```

#### GraphQL Contracts Directory Structure

The following is the directory structure for GraphQL specifications:

1. Each vendor has their own directory. (E.g.: `graphql/github`, `graphql/shopify`, etc.).
2. Within each vendor directory, each API has its own directory. (E.g.: `graphql/github/github`, `graphql/shopify/admin`, etc.).
    > **Note:** If the vendor and the API name are the same, the directory names would be the same. (E.g.: `graphql/github/github`.)
3. Each API directory will contain a `schema.graphql` file that contains the GraphQL schema.
    > **Note:** Since GraphQL APIs do not have versions, the schema file would be placed directly under the vendor directory.
4. The directory would also contain an `icon.png` file that contains the logo of the API.
5. This directory would also contain a `.metadata.json` file to store metadata.

##### GraphQL Metadata File Structure

The `.metadata.json` file would contain the following information:

- `name`: The human-readable name of the API.
- `description`: A brief description of the API.
- `endpoint`: The endpoint URL of the API.
- `documentationUrl`: The URL to the API documentation, if available.
- `tags`: An array of tags that are relevant to the API.

```json
{
    "name": "GitHub GraphQL API",
    "description": "Access GitHub data using GraphQL. Query repositories, issues, users, and more.",
    "endpoint": "https://api.github.com/graphql",
    "documentationUrl": "https://docs.github.com/en/graphql",
    "tags": ["developer", "github"],
}
```

###### Example: GraphQL Contracts Directory Structure

```text
api-specs/
└── graphql
    └── github
        └── github
            ├── .metadata.json
            ├── icon.png
            └── schema.graphql
```

#### AsyncAPI Contracts Directory Structure

The AsyncAPI directory structure would be similar to the [OpenAPI directory structure](#openapi-contracts-directory-structure). The only difference is that the AsyncAPI spec file would be named as `asyncapi.yaml`.

###### Example: AsyncAPI Contracts Directory Structure

```text
api-specs/
└── asyncapi
    └── slack
        └── events
            ├── 1.0.0
            │   └── asyncapi.yaml
            └── icon.png
```

##### AsyncAPI Metadata File Structure

The `.metadata.json` file would contain the following information:

- `name`: The human-readable name of the API.
- `description`: A brief description of the API.
- `protocol`: The protocol used by the API.
- `documentationUrl`: The URL to the API documentation, if available.
- `tags`: An array of tags that are relevant to the API.

```json
{
    "name": "Slack Events API",
    "description": "AsyncAPI contract for Slack Events API.",
    "protocol": "WebSocket",
    "documentationUrl": "https://api.slack.com/apis/events-api",
    "tags": ["slack", "events"],
}
```

### OpenAPI Dependabot

The repository includes an automated system that monitors upstream sources for updates to OpenAPI specifications and keeps the specs in this repository up to date.

#### `openapi/openapi_specs.json`

The file `openapi/openapi_specs.json` is the registry of all OpenAPI specs tracked by the dependabot. Each entry describes one API that the system monitors:

- `name`: The human-readable name of the API.
- `sourceUrl`: The upstream URL from which the latest spec is fetched.
- `connectorRepo`: The Ballerina connector repository associated with this API.

```json
[
    {
        "name": "Asana",
        "sourceUrl": "https://github.com/Asana/openapi",
        "connectorRepo": "ballerina-platform/module-ballerinax-asana"
    }
]
```

When adding a new API to be monitored, add an entry to this file following the structure above.

#### `dependabot/` Directory

The `dependabot/` directory contains a Ballerina agent that automates OpenAPI spec discovery and updates. The agent:

1. Reads `openapi/openapi_specs.json` to determine which APIs to monitor.
2. Fetches the latest OpenAPI spec from each API's `sourceUrl`.
3. Downloads updated specs into the appropriate directory under `openapi/`.
4. Produces an `UPDATE_SUMMARY.json` file (at the repo root, never committed) listing what changed.

Key files in `dependabot/`:

| File / Directory | Purpose |
|---|---|
| `main.bal` | Entry point — runs the agent sequentially for each connector |
| `agent.bal` | AI agent logic for discovering the latest spec URL |
| `downloader.bal` | Downloads the spec from the discovered URL |
| `extractor.bal` | Extracts and normalises the spec content |
| `pipeline.bal` | Orchestrates the per-connector update pipeline |
| `openapi_validator.bal` | Validates downloaded specs using the Java validator |
| `types.bal` | Shared Ballerina type definitions |
| `browser-service/` | Node.js service used for browser-based spec fetching |
| `java-validator/` | Java-based OpenAPI validator source and build scripts |
| `libs/openapi-validator.jar` | Pre-built validator JAR used at runtime |
| `resources/scripts/` | Shell scripts used by the GitHub Actions workflow |
| `Ballerina.toml` | Ballerina project configuration |

#### `.github/workflows/openapi-dependabot.yml`

The `openapi-dependabot.yml` workflow automates the full update lifecycle on a daily schedule (2 AM UTC) and can also be triggered manually.

**Workflow steps:**

1. **Run the dependabot agent** — executes `bal run` inside `dependabot/` to discover and download updated specs.
2. **Detect updates** — checks for the presence of `UPDATE_SUMMARY.json`; if absent, the workflow exits early with no changes.
3. **Create a branch and PR** — commits changed files under `openapi/` to a timestamped branch and opens a pull request.
4. **Validate the PR** — verifies that only files under `openapi/` were modified and that all OpenAPI spec files are structurally valid.
5. **Approve and merge** — if validation passes, the PR is automatically approved (using `REVIEWER_BOT_TOKEN`) and squash-merged.
6. **Trigger connector regeneration** — dispatches a workflow event to the `ballerina-library` repository to regenerate connectors for every updated spec.

**Required secrets:**

| Secret | Purpose |
|---|---|
| `GH_TOKEN` | Pushes branches and opens pull requests |
| `REVIEWER_BOT_TOKEN` | Approves and merges the PR (must be a different identity from the committer to satisfy branch-protection rules) |
| `ANTHROPIC_API_KEY` | Used by the Ballerina AI agent to discover spec URLs |
| `CROSS_REPO_PAT` | Dispatches the connector regeneration workflow in `ballerina-library` |

 **Least-privilege guidance:**
 - Prefer the default `GITHUB_TOKEN` where it is sufficient for repository-local automation.
 - If a personal access token is required, prefer a **fine-grained PAT** scoped only to the specific repository and only the minimum permissions needed for the workflow.
 - For `REVIEWER_BOT_TOKEN`, use a dedicated bot or GitHub App identity with only the permissions required to review and merge pull requests.
 - For `CROSS_REPO_PAT`, restrict the token to the target `ballerina-library` repository and grant only the minimum access needed to trigger the downstream workflow (for example, workflow dispatch / Actions access only). Prefer a GitHub App over a PAT where feasible.

### API Contract Validation

An API contract is considered verified if _one of the following conditions_ is met:

- The specification is from the official source.
- The specification is used to generate and publish a connector/client and is tested and verified.

The [`main`](https://github.com/wso2/api-specs/tree/main) branch contains only valid API contracts. The [`incubator`](https://github.com/wso2/api-specs/tree/incubator) branch may contain contracts that are not yet verified.

### API Contract Graduation

If an API contract is not from the official source, it can be graduated to the `main` branch after the following conditions are met:

- The API contract is used to generate a connector/client.
- The generated connector/client is tested and verified against the live API.

When graduating an API contract, the following steps should be followed:

1. Validate whether the API contract is in the correct format.
    * OpenAPI: The OpenAPI spec should be in YAML or JSON format and should follow the OpenAPI specification.
    * GraphQL: The GraphQL schema should be in SDL format and should follow the GraphQL specification.
    * AsyncAPI: The AsyncAPI spec should be in YAML format and should follow the AsyncAPI specification.
2. Add a valid `.metadata.json` file to the API version directory.
3. Add the relevant `icon.png` file to the API directory.
4. Send a pull request to the `main` branch.

## Reporting Issues

If you find any issues with the exiting API specifications, please raise an issue in the [Issues](https://github.com/wso2/api-specs/issues) section of this repository. If you have a new API specification that you would like to contribute, please send a pull request, following the above conventions.
