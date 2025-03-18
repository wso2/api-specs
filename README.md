# API Specifications

This repository contains API specifications (openAPI, GraphQL, etc.) for public APIs. The goal is to provide a central location for API specifications that can be used by developers, testers, and other stakeholders to understand the capabilities of the APIs.

## OpenAPI Specifications

OpenAPI specifications are available in the [`openapi`](./openapi/) directory. Each OpenAPI spec is stored in a separate directory. The directory structure follows the following convention:

1. Each vendor has their own directory. (Eg.: `openapi/azure`, `openapi/googleapis`, etc.)
2. Within the vendor directory, each API has its own directory. (Eg.: `openapi/googleapis/docs`, `openapi/docusign/monitor`, etc.)
    > If the vendor and the API name is the same, the directory names would be the same. (Eg.: `openapi/bitly/bitly`, `openapi/gitlab/gitlab`, etc.)
3. If the API is categorized in a hierarchical manner, the API directory would be named with the hierarchy, separated with a dot (`.`). (Eg.: `openapi/hubspot/cms.authors`, `openapi/hubspot/crm.emails`, etc.)
4. Within the API directory, another directory would be created for each version of the API. (Eg.: `openapi/googleapis/docs/v1`, `openapi/googleapis/oauth2/v2`, etc.)
5. Apart from the OpenAPI spec version directory, each API directory contains an `icon.png` file that contains the logo of the API.
6. Inside the API version directory, the OpenAPI spec file would be named as `openapi.yaml` or `openapi.json`.

## Reporting Issues

If you find any issues with the exiting API specifications, please raise an issue in the [Issues](https://github.com/wso2/api-specs/issues) section of this repository. If you have a new API specification that you would like to contribute, please send a pull request, following the above conventions.
