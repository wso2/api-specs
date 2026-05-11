// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

// extractor.bal
// Extracts fields from a spec's content (JSON or YAML).
// Primary path: proper YAML/JSON parsing via ballerina/data.yaml and data.jsondata.
// Fallback path: line-by-line regex scan when parsing fails.

import ballerina/data.jsondata;
import ballerina/data.yaml;
import ballerina/log;

// Extracts the apiVersion from spec content (info.version).
// Returns nil if extraction fails.
function extractSpecMetadata(string content) returns string? {
    do {
        json|error parsed = parseSpecContent(content);
        if parsed is error {
            string|error ver = extractApiVersionWithRegex(content);
            return ver is string ? ver : ();
        }
        if parsed is map<json> {
            json? infoField = parsed["info"];
            if infoField is map<json> {
                json? v = infoField["version"];
                if v is string { return v; }
                if v is int || v is decimal || v is float { return v.toString(); }
                fail error(string `Unexpected version type: ${(typeof v).toString()}`);
            }
        }
    } on fail error e {
        log:printDebug(string `  [extract] apiVersion extraction failed: ${e.message()}`);
    }
    return ();
}

// Extracts the base URL from spec content.
// OAS3: servers[0].url   Swagger 2.0: scheme + host + basePath
function extractSpecBaseUrl(string content) returns string? {
    do {
        json|error parsed = parseSpecContent(content);
        if parsed is error { return (); }
        if parsed is map<json> {
            // OAS3
            json? serversField = parsed["servers"];
            if serversField is json[] && serversField.length() > 0 {
                json first = serversField[0];
                if first is map<json> {
                    json? urlField = first["url"];
                    if urlField is string && urlField.length() > 0 {
                        return urlField;
                    }
                }
            }
            // Swagger 2.0
            json? hostField = parsed["host"];
            if hostField is string {
                string scheme = "https";
                json? schemesField = parsed["schemes"];
                if schemesField is json[] && schemesField.length() > 0 {
                    json s = schemesField[0];
                    if s is string { scheme = s; }
                }
                json? basePathField = parsed["basePath"];
                string basePath = basePathField is string ? basePathField : "";
                return scheme + "://" + hostField + basePath;
            }
        }
    } on fail error e {
        log:printDebug(string `  [extract] baseUrl extraction failed: ${e.message()}`);
    }
    return ();
}

// Extracts the description from spec content (info.description).
function extractSpecDescription(string content) returns string? {
    do {
        json|error parsed = parseSpecContent(content);
        if parsed is error { return (); }
        if parsed is map<json> {
            json? infoField = parsed["info"];
            if infoField is map<json> {
                json? descField = infoField["description"];
                if descField is string && descField.length() > 0 {
                    return descField;
                }
            }
        }
    } on fail error e {
        log:printDebug(string `  [extract] description extraction failed: ${e.message()}`);
    }
    return ();
}

// Parses spec content as JSON or YAML and returns the root json value.
function parseSpecContent(string content) returns json|error {
    string trimmed = content.trim();
    if trimmed.startsWith("{") || trimmed.startsWith("[") {
        return jsondata:parseString(content);
    }
    return yaml:parseString(content);
}

// Fallback: regex-based line-by-line scan for info.version.
function extractApiVersionWithRegex(string content) returns string|error {
    string[] lines = re `\n`.split(content);
    boolean inInfoSection = false;

    foreach string line in lines {
        string trimmedLine = line.trim();

        // JSON format: "version": "1.0"
        if trimmedLine.startsWith("\"version\":") || trimmedLine.startsWith("'version':") {
            string[] parts = re `:`.split(trimmedLine);
            if parts.length() >= 2 {
                string versionValue = parts[1].trim();
                versionValue = removeQuotes(versionValue);
                versionValue = re `,`.replaceAll(versionValue, "").trim();
                if versionValue.length() > 0 {
                    return versionValue;
                }
            }
        }

        // YAML format: inside info: block
        if trimmedLine == "info:" {
            inInfoSection = true;
            continue;
        }

        if inInfoSection {
            if !line.startsWith(" ") && !line.startsWith("\t") && trimmedLine != "" && !trimmedLine.startsWith("#") {
                break;
            }
            if trimmedLine.startsWith("version:") {
                string[] parts = re `:`.split(trimmedLine);
                if parts.length() >= 2 {
                    string versionValue = parts[1].trim();
                    versionValue = removeQuotes(versionValue);
                    return versionValue;
                }
            }
        }
    }

    return error("Could not extract API version from spec using regex");
}

isolated function removeQuotes(string s) returns string {
    string trimmed = s.trim();
    if trimmed.length() >= 2 {
        if (trimmed.startsWith("\"") && trimmed.endsWith("\"")) ||
           (trimmed.startsWith("'") && trimmed.endsWith("'")) {
            return trimmed.substring(1, trimmed.length() - 1).trim();
        }
    }
    return trimmed;
}
