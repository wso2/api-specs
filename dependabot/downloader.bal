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

// downloader.bal
// Downloads a verified spec from its URL and saves it to the correct openapi/ folder.
//
// Folder layout: {openApiDir}/{vendor}/{apiId}/{versionFolder}/openapi.{ext}
//                {openApiDir}/{vendor}/{apiId}/{versionFolder}/.metadata.json
//
// .metadata.json is only created when a NEW version folder is created for the
// first time. It is never modified when an existing spec file is replaced.
//
// Version folder naming:
//   - Version is used exactly as stated in the spec's info.version field.
//     e.g. info.version "4.0.0" → folder "4.0.0", "v3.0.1" → folder "v3.0.1".
//   - nil or empty apiVersion → "latest" is used as the folder name.

import ballerina/crypto;
import ballerina/file;
import ballerina/io;
import ballerina/log;

# Downloads a spec and saves it to the appropriate folder.
#
# + specUrl - URL to fetch the spec from
# + format - File format: "json" or "yaml"
# + apiVersion - API version from the spec's info.version, or nil for "latest"
# + vendor - Vendor identifier derived from the connector name
# + apiId - API identifier derived from the connector name
# + openApiDir - Base directory for storing downloaded specs
# + connectorName - Display name of the connector
# + sourceUrl - Documentation URL used as the metadata documentationUrl
# + return - `[true, hash]` if the file was added or updated, `[false, hash]` if unchanged
function downloadAndSaveSpec(
    string specUrl,
    string format,
    string? apiVersion,
    string vendor,
    string apiId,
    string openApiDir,
    string connectorName,
    string sourceUrl
) returns [boolean, string]|error {

    string versionFolder = normalizeVersion(apiVersion ?: "");
    string fileName = format == "json" ? "openapi.json" : "openapi.yaml";

    string specDir = string `${openApiDir}/${vendor}/${apiId}`;
    string versionDir = string `${specDir}/${versionFolder}`;
    string specFile = string `${versionDir}/${fileName}`;
    string otherFileName = format == "json" ? "openapi.yaml" : "openapi.json";
    string otherFile = string `${versionDir}/${otherFileName}`;
    string metaFile = string `${versionDir}/.metadata.json`;

    log:printInfo(string `  [download] --- BEGIN ${vendor}/${apiId}@${versionFolder} ---`);
    log:printInfo(string `  [download] openApiDir  : ${openApiDir}`);
    log:printInfo(string `  [download] versionDir  : ${versionDir}`);
    log:printInfo(string `  [download] specFile    : ${specFile}`);
    log:printInfo(string `  [download] otherFile   : ${otherFile}`);
    log:printInfo(string `  [download] metaFile    : ${metaFile}`);
    log:printInfo(string `  [download] fetching    : ${specUrl}`);

    string|error content = httpGetBodyFull(specUrl);
    if content is error {
        return error(string `Failed to download ${specUrl}: ${content.message()}`);
    }
    log:printInfo(string `  [download] fetched ${content.length()} bytes`);

    string newHash = calculateHash(content);
    log:printInfo(string `  [download] newHash     : ${newHash.substring(0, 16)}...`);

    boolean versionDirExists = check file:test(versionDir, file:IS_DIR);
    log:printInfo(string `  [download] IS_DIR(versionDir) = ${versionDirExists}`);

    if versionDirExists {
        boolean targetExists = check file:test(specFile, file:EXISTS);
        boolean otherExists = check file:test(otherFile, file:EXISTS);
        boolean metaExistsNow = check file:test(metaFile, file:EXISTS);
        log:printInfo(string `  [download] EXISTS(${fileName})       = ${targetExists}`);
        log:printInfo(string `  [download] EXISTS(${otherFileName})  = ${otherExists}`);
        log:printInfo(string `  [download] EXISTS(.metadata.json)    = ${metaExistsNow}`);

        string? oldHash = check readExistingSpecHash(specFile, otherFile, targetExists, otherExists, fileName, otherFileName);

        if oldHash is string && !hasContentChanged(oldHash, newHash) {
            log:printInfo(string `  [download] SKIP — content unchanged for ${vendor}/${apiId}@${versionFolder}`);
            return [false, newHash];
        }
        log:printInfo(string `  [download] content changed (or no prior file) — will replace`);

        check removeExistingSpecFiles(specFile, otherFile, targetExists, otherExists, fileName, otherFileName);

        log:printInfo(string `  [download] writing new spec (metadata WILL NOT be touched)`);
    } else {
        log:printInfo(string `  [download] version dir does not exist — creating: ${versionDir}`);
        check file:createDir(versionDir, file:RECURSIVE);
        log:printInfo(string `  [download] created dir: ${versionDir}`);

        boolean metaExists = check file:test(metaFile, file:EXISTS);
        log:printInfo(string `  [download] EXISTS(.metadata.json) after createDir = ${metaExists}`);
        if !metaExists {
            log:printInfo(string `  [download] creating .metadata.json`);
            string? baseUrl = extractSpecBaseUrl(content);
            string? description = extractSpecDescription(content);
            string[] tags = deriveTags(connectorName, vendor);
            check io:fileWriteString(metaFile, buildMetadataJson(connectorName, baseUrl, sourceUrl, description, tags));
            log:printInfo(string `  [download] created .metadata.json`);
        } else {
            log:printInfo(string `  [download] .metadata.json already exists — skipping creation`);
        }
    }

    log:printInfo(string `  [download] writing spec: ${specFile}`);
    check io:fileWriteString(specFile, content);
    log:printInfo(string `  [download] saved: ${specFile}`);

    return [true, newHash];
}

// ─── Hash helpers ─────────────────────────────────────────────────────────────

function calculateHash(string content) returns string {
    byte[] contentBytes = content.toBytes();
    byte[] hashBytes = crypto:hashSha256(contentBytes);
    return hashBytes.toBase16();
}

isolated function hasContentChanged(string? oldHash, string newHash) returns boolean {
    if oldHash is () || oldHash == "" {
        return true;
    }
    return oldHash != newHash;
}

# Reads the hash of whichever spec file currently exists in the version folder.
# Prefers the target-format file; falls back to the other-format file.
#
# + specFile - Path to the spec file in the target format
# + otherFile - Path to the spec file in the alternate format
# + targetExists - Whether specFile exists
# + otherExists - Whether otherFile exists
# + fileName - Filename of the target format (for logging)
# + otherFileName - Filename of the alternate format (for logging)
# + return - SHA-256 hash of the existing file content, or nil if no file exists
function readExistingSpecHash(
    string specFile,
    string otherFile,
    boolean targetExists,
    boolean otherExists,
    string fileName,
    string otherFileName
) returns string?|error {
    if targetExists {
        string existingContent = check io:fileReadString(specFile);
        string hash = calculateHash(existingContent);
        log:printInfo(string `  [download] oldHash(${fileName})  : ${hash.substring(0, 16)}...`);
        return hash;
    }
    if otherExists {
        string existingContent = check io:fileReadString(otherFile);
        string hash = calculateHash(existingContent);
        log:printInfo(string `  [download] oldHash(${otherFileName}): ${hash.substring(0, 16)}...`);
        return hash;
    }
    log:printInfo(string `  [download] no existing spec file found in version dir`);
    return ();
}

# Removes existing spec files from a version folder before writing updated content.
#
# + specFile - Path to the target-format spec file
# + otherFile - Path to the alternate-format spec file
# + targetExists - Whether specFile exists and should be removed
# + otherExists - Whether otherFile exists and should be removed
# + fileName - Filename of the target format (for logging)
# + otherFileName - Filename of the alternate format (for logging)
function removeExistingSpecFiles(
    string specFile,
    string otherFile,
    boolean targetExists,
    boolean otherExists,
    string fileName,
    string otherFileName
) returns error? {
    if targetExists {
        log:printInfo(string `  [download] removing: ${specFile}`);
        check file:remove(specFile);
        log:printInfo(string `  [download] removed ${fileName}`);
    }
    if otherExists {
        log:printInfo(string `  [download] removing: ${otherFile}`);
        check file:remove(otherFile);
        log:printInfo(string `  [download] removed stale ${otherFileName}`);
    }
}

// ─── Version / path helpers ───────────────────────────────────────────────────

isolated function normalizeVersion(string version) returns string {
    string v = version.trim();
    if v.length() == 0 { return "latest"; }
    return v;
}

isolated function deriveVendor(string connectorName) returns string {
    string[] parts = re ` `.split(connectorName);
    if parts.length() > 0 {
        return parts[0].toLowerAscii();
    }
    return connectorName.toLowerAscii();
}

isolated function deriveApiId(string connectorName) returns string {
    string[] parts = re ` `.split(connectorName);
    if parts.length() > 1 {
        string result = "";
        boolean first = true;
        foreach int i in 1 ..< parts.length() {
            if !first { result += "."; }
            result += parts[i].toLowerAscii();
            first = false;
        }
        return result;
    }
    return connectorName.toLowerAscii();
}

// Derives tags from the connector display name (lowercase meaningful words).
isolated function deriveTags(string connectorName, string vendor) returns string[] {
    string[] stopwords = ["api", "rest", "the", "a", "an", "of", "for", "and", "or", "with"];
    string[] tags = [];
    map<boolean> seen = {};

    foreach string word in re ` `.split(connectorName.toLowerAscii()) {
        if word.length() <= 1 { continue; }
        boolean stop = false;
        foreach string sw in stopwords {
            if word == sw { stop = true; break; }
        }
        if !stop && !seen.hasKey(word) {
            seen[word] = true;
            tags.push(word);
        }
    }

    string vendorLower = vendor.toLowerAscii();
    if !seen.hasKey(vendorLower) {
        tags.push(vendorLower);
    }
    return tags;
}

// ─── Metadata generation ──────────────────────────────────────────────────────

function buildMetadataJson(
    string connectorName,
    string? baseUrl,
    string sourceUrl,
    string? description,
    string[] tags
) returns string {
    string tagsJson = buildTagsJson(tags);
    return string `{
    "name": "${jsonEsc(connectorName)}",
    "baseUrl": "${jsonEsc(baseUrl ?: "")}",
    "documentationUrl": "${jsonEsc(sourceUrl)}",
    "description": "${jsonEsc(description ?: "")}",
    "tags": ${tagsJson}
}`;
}

isolated function buildTagsJson(string[] tags) returns string {
    if tags.length() == 0 { return "[]"; }
    string result = "[";
    boolean first = true;
    foreach string tag in tags {
        if !first { result += ", "; }
        result += "\"" + jsonEsc(tag) + "\"";
        first = false;
    }
    return result + "]";
}
