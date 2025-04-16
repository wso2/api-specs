# API Contracts Repository

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
6. Inside the API version directory, the OpenAPI spec file would be named as `openapi.yaml`.
    > **Note:** If an API contract is in the `JSON` format, it should be converted to `YAML` format before committing to the repository.
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
    * OpenAPI: The OpenAPI spec should be in YAML format and should follow the OpenAPI specification.
    * GraphQL: The GraphQL schema should be in SDL format and should follow the GraphQL specification.
    * AsyncAPI: The AsyncAPI spec should be in YAML format and should follow the AsyncAPI specification.
2. Add a valid `.metadata.json` file to the API version directory.
3. Add the relevant `icon.png` file to the API directory.
4. Send a pull request to the `main` branch.
