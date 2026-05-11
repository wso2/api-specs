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

// agent.bal
// Shared utilities used by all pipeline steps.
//
// FIX (2026-04-17): wrapped every HTTP GET in a wall-clock timeout using a
// Ballerina worker + `wait` with a timer.  Ballerina's http:Client `timeout`
// is NOT honoured across redirects when the redirect target is on a different
// host (the new client is created with defaults and can hang indefinitely on
// a stalled TLS handshake).  This was causing 15+ min hangs on docs.stripe.com
// and similar SPAs behind Cloudflare.
//
// The wall-clock timeout is enforced OUTSIDE the http client by racing the
// fetch against a sleep in a separate worker.  This guarantees progress even
// when the underlying socket is wedged.
//
// TIMEOUTS (hard wall-clock ceilings enforced by withTimeout):
//   Raw / spec files          : 30 s
//   HTML docs pages (plain)   : 20 s
//   Browser service           : 35 s
//   HEAD checks               : 15 s
//   Git Blobs API fallback    : 35 s
//   Full spec fetch (Java)    : 65 s

import ballerina/http;
import ballerina/lang.'array as langarray;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/os;
import ballerina/time;
import ballerina/url;

// ─── Tool definition ─────────────────────────────────────────────────────────

final json FETCH_PAGE_TOOL = {
    "name": "fetch_page",
    "description":
        "Fetches a URL and returns its content. " +
        "HTML → {spec_links, page_text, other_links}. " +
        "JSON/YAML → {type, content} with up to 12 KB of file content. " +
        "Never fetch github.com/blob or github.com/tree pages. " +
        "Use api.github.com/repos/OWNER/REPO/contents/PATH to list a folder. " +
        "Use api.github.com/repos/OWNER/REPO/git/trees/HEAD?recursive=1 for full flat listing (may truncate on large repos).",
    "input_schema": {
        "type": "object",
        "properties": {
            "url": {"type": "string", "description": "Full URL to fetch (https://...)"}
        },
        "required": ["url"]
    }
};

// ─── Wall-clock timeout helper ────────────────────────────────────────────────
//
// Races `fetch` against a sleep.  Whichever finishes first wins.  If the sleep
// wins, we return a timeout error — the underlying socket may still be open
// but the caller is no longer blocked on it.
//
// NOTE: this does NOT forcibly close the hung socket (Ballerina has no API
// for that from outside the client), but it does unblock the pipeline so the
// overall run makes progress.  The hung connection will eventually be GC'd.
//
// NOTE 2: `runtime:sleep` takes a decimal number of seconds.

type FetchFn function () returns string|error;

function withTimeout(FetchFn fetch, decimal timeoutSecs, string opName) returns string|error {
    worker fetcher returns string|error {
        return fetch();
    }
    worker timer returns string|error {
        runtime:sleep(timeoutSecs);
        return error(string `${opName}: wall-clock timeout after ${timeoutSecs}s`);
    }
    // wait for whichever worker completes first
    string|error result = wait fetcher | timer;
    return result;
}

// ─── URL safety guard ─────────────────────────────────────────────────────────

# Checks whether a URL is safe to fetch.
# Blocks non-HTTPS schemes and private/loopback/link-local address ranges to
# prevent SSRF from LLM-supplied URLs.
#
# + rawUrl - The URL to validate
# + return - `true` if the URL is safe to fetch, `false` if it should be blocked
isolated function isSafeUrl(string rawUrl) returns boolean {
    if !rawUrl.startsWith("https://") {
        return false;
    }
    string withoutScheme = rawUrl.substring(8);
    int hostEnd = withoutScheme.indexOf("/") ?: withoutScheme.length();
    string hostPort = withoutScheme.substring(0, hostEnd).toLowerAscii();
    int? colonPos = hostPort.lastIndexOf(":");
    string host = colonPos is int ? hostPort.substring(0, colonPos) : hostPort;
    if host.startsWith("[") && host.endsWith("]") {
        host = host.substring(1, host.length() - 1);
    }
    if host == "localhost" || host == "::1" || host == "0.0.0.0" {
        return false;
    }
    string[] octets = re`\.`.split(host);
    if octets.length() == 4 {
        int|error a = int:fromString(octets[0]);
        int|error b = int:fromString(octets[1]);
        if a is int {
            if a == 127 || a == 10 { return false; }
            if a == 192 && b is int && b == 168 { return false; }
            if a == 172 && b is int && b >= 16 && b <= 31 { return false; }
            if a == 169 && b is int && b == 254 { return false; }
        }
    }
    return true;
}

// ─── fetch_page tool handler ──────────────────────────────────────────────────

const string EMPTY_HTML_RESULT = "{\"type\":\"html\",\"spec_links\":[],\"page_text\":\"\",\"other_links\":[]}";

function executeFetchPage(string fetchUrl) returns string {
    if !isSafeUrl(fetchUrl) {
        log:printWarn(string `    [fetch] blocked unsafe URL: ${fetchUrl}`);
        return string `{"error":"blocked: URL must use https and must not target a private or loopback address"}`;
    }
    log:printInfo(string `    [fetch] ${fetchUrl}`);
    log:printDebug(string `    [fetch:debug] starting fetch at ${timeNow()}`);

    do {
        time:Utc t0 = time:utcNow();
        string|error body = httpGetBody(fetchUrl);
        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));

        if body is error {
            log:printInfo(string `      error: ${body.message()}`);
            log:printDebug(string `    [fetch:debug] fetch failed after ${elapsed}s — url=${fetchUrl} err=${body.message()}`);
            if !isRawContentUrl(fetchUrl) {
                return EMPTY_HTML_RESULT;
            }
            return string `{"error":"fetch failed: ${jsonEsc(body.message())}"}`;
        }

        log:printDebug(string `    [fetch:debug] fetch succeeded in ${elapsed}s — bytes=${body.length()}`);

        string lo = fetchUrl.toLowerAscii();

        // YAML
        if lo.endsWith(".yaml") || lo.endsWith(".yml") {
            string snippet = body.length() > 12000 ? body.substring(0, 12000) : body;
            log:printDebug("    [fetch:debug] detected YAML content");
            return string `{"type":"yaml","content":${jsonStr(snippet)}}`;
        }

        // JSON / GitHub API — use 100 KB cap for GitHub Contents API directory listings
        if lo.endsWith(".json") || lo.includes("api.github.com") || lo.includes("application/json") {
            int jsonCap = lo.includes("api.github.com") ? 100000 : 12000;
            string snippet = body.length() > jsonCap ? body.substring(0, jsonCap) : body;
            log:printDebug(string `    [fetch:debug] detected JSON content, cap=${jsonCap}`);
            return string `{"type":"json","content":${jsonStr(snippet)}}`;
        }

        // Detect by content if extension is ambiguous
        string trimmed = body.trim();
        if trimmed.startsWith("openapi:") || trimmed.startsWith("swagger:") || trimmed.startsWith("---") {
            string snippet = body.length() > 12000 ? body.substring(0, 12000) : body;
            log:printDebug("    [fetch:debug] detected YAML by content sniff");
            return string `{"type":"yaml","content":${jsonStr(snippet)}}`;
        }
        if trimmed.startsWith("{") || trimmed.startsWith("[") {
            string snippet = body.length() > 12000 ? body.substring(0, 12000) : body;
            log:printDebug("    [fetch:debug] detected JSON by content sniff");
            return string `{"type":"json","content":${jsonStr(snippet)}}`;
        }

        // HTML — extract links and text
        log:printDebug("    [fetch:debug] treating as HTML, extracting links");
        string[] specLinks = [];
        string[] otherLinks = [];
        string[] allLinks = extractHrefs(body, fetchUrl);

        foreach string lnk in allLinks {
            if isSpecLink(lnk) {
                specLinks.push(lnk);
            } else {
                otherLinks.push(lnk);
            }
        }

        string txt = htmlText(body);
        string txtSnippet = txt.length() > 3000 ? txt.substring(0, 3000) : txt;
        int otherCap = otherLinks.length() > 60 ? 60 : otherLinks.length();
        log:printDebug(string `    [fetch:debug] HTML: specLinks=${specLinks.length()} otherLinks=${otherLinks.length()} textLen=${txt.length()}`);

        return string `{"type":"html","spec_links":${jsonArr(specLinks)},"page_text":${jsonStr(txtSnippet)},"other_links":${jsonArr(otherLinks.slice(0, otherCap))}}`;
    } on fail error e {
        log:printWarn(string `      [fetch] unexpected error: ${e.message()}`);
        log:printDebug(string `    [fetch:debug] panic/unexpected error — url=${fetchUrl} err=${e.message()}`);
        return EMPTY_HTML_RESULT;
    }
}

// ─── GitHub raw URL decomposition ────────────────────────────────────────────

type GitHubRawUrl record {|
    string owner;
    string repo;
    string branch;
    string path;
|};

isolated function parseGitHubRawUrl(string rawUrl) returns GitHubRawUrl? {
    string prefix = "raw.githubusercontent.com/";
    int? pi = rawUrl.indexOf(prefix);
    if pi is () { return (); }
    string rest = rawUrl.substring(pi + prefix.length());

    int? s1 = rest.indexOf("/");
    if s1 is () { return (); }
    string owner = rest.substring(0, s1);
    string rem1 = rest.substring(s1 + 1);

    int? s2 = rem1.indexOf("/");
    if s2 is () { return (); }
    string repo = rem1.substring(0, s2);
    string rem2 = rem1.substring(s2 + 1);

    int? s3 = rem2.indexOf("/");
    if s3 is () { return (); }
    string branch = rem2.substring(0, s3);
    string path = rem2.substring(s3 + 1);

    return {owner, repo, branch, path};
}

// ─── Git Blobs API fallback for files > 1 MB ─────────────────────────────────

function fetchViaGitBlobsApi(string rawUrl, int maxBytes, string ghToken) returns string|error {
    log:printDebug(string `    [blobs-api] starting Git Blobs API fallback for: ${rawUrl}`);

    GitHubRawUrl? parsed = parseGitHubRawUrl(rawUrl);
    if parsed is () {
        return error("fetchViaGitBlobsApi: cannot parse raw GitHub URL");
    }
    string owner = parsed.owner;
    string repo = parsed.repo;
    string branch = parsed.branch;
    string path = parsed.path;

    map<string|string[]> headers = {"User-Agent": "openapi-spec-finder/1.0"};
    if ghToken.length() > 0 {
        headers["Authorization"] = string `Bearer ${ghToken}`;
    }

    // Step 1
    string metaUrl = string `https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${branch}`;
    log:printDebug(string `    [blobs-api:step1] fetching metadata: ${metaUrl}`);

    string metaBody = check withTimeout(function () returns string|error {
        time:Utc t0 = time:utcNow();
        http:Client metaClient = check new (metaUrl, {
            followRedirects: {enabled: true, maxCount: 3},
            timeout: 20,
            secureSocket: {enable: true}
        });
        http:Response metaResp = check metaClient->get("", headers);
        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
        log:printDebug(string `    [blobs-api:step1] status=${metaResp.statusCode} elapsed=${elapsed}s`);
        if metaResp.statusCode != 200 {
            return error(string `Git Blobs API step1: HTTP ${metaResp.statusCode}`);
        }
        return metaResp.getTextPayload();
    }, 35.0, "blobs-api-step1");

    json|error metaJson = metaBody.fromJsonString();
    if metaJson is error {
        return error(string `Git Blobs API step1: cannot parse metadata JSON: ${metaJson.message()}`);
    }

    string sha = "";
    int fileSize = 0;
    if metaJson is map<json> {
        json? shaVal = metaJson["sha"];
        if shaVal is string { sha = shaVal; }
        json? sizeVal = metaJson["size"];
        if sizeVal is int { fileSize = sizeVal; }
    }
    if sha.length() == 0 {
        return error("Git Blobs API step1: could not extract blob SHA from metadata");
    }
    log:printDebug(string `    [blobs-api:step1] blob SHA=${sha} size=${fileSize}`);

    // Step 2
    string blobUrl = string `https://api.github.com/repos/${owner}/${repo}/git/blobs/${sha}`;
    map<string|string[]> blobHeaders = {
        "User-Agent": "openapi-spec-finder/1.0",
        "Accept":     "application/vnd.github.raw+json"
    };
    if ghToken.length() > 0 {
        blobHeaders["Authorization"] = string `Bearer ${ghToken}`;
    }

    log:printDebug(string `    [blobs-api:step2] fetching raw blob: ${blobUrl}`);

    string blobBody = check withTimeout(function () returns string|error {
        time:Utc t1 = time:utcNow();
        http:Client blobClient = check new (blobUrl, {
            followRedirects: {enabled: true, maxCount: 5},
            timeout: 30,
            secureSocket: {enable: true}
        });
        http:Response blobResp = check blobClient->get("", blobHeaders);
        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t1));
        log:printDebug(string `    [blobs-api:step2] status=${blobResp.statusCode} elapsed=${elapsed}s`);
        if blobResp.statusCode != 200 {
            return error(string `Git Blobs API step2: HTTP ${blobResp.statusCode}`);
        }
        return blobResp.getTextPayload();
    }, 35.0, "blobs-api-step2");

    log:printDebug(string `    [blobs-api:step2] received ${blobBody.length()} bytes`);

    if blobBody.trim().startsWith("{") && blobBody.includes("\"encoding\"") {
        log:printDebug("    [blobs-api:step2] response looks like JSON blob envelope — attempting base64 decode");
        string? decoded = decodeGitHubBlobBase64(blobBody, maxBytes);
        if decoded is string {
            log:printInfo(string `    [blobs-api:step2] base64 decode succeeded — returning ${decoded.length()} bytes`);
            return decoded;
        }
        log:printWarn("    [blobs-api:step2] base64 decode failed — returning raw response (looksLikeSpec may reject it)");
    }

    string result = blobBody.length() > maxBytes ? blobBody.substring(0, maxBytes) : blobBody;
    log:printDebug(string `    [blobs-api:step2] returning ${result.length()} bytes (raw)`);
    return result;
}

// ─── Base64 blob decoder ──────────────────────────────────────────────────────

function decodeGitHubBlobBase64(string jsonBody, int maxBytes) returns string? {
    do {
        json parsed = check jsonBody.fromJsonString();
        if !(parsed is map<json>) { return (); }

        json? enc = parsed["encoding"];
        json? cnt = parsed["content"];

        if enc != "base64" { return (); }
        if !(cnt is string) { return (); }

        string cleanB64 = re `[\n\r\s]`.replaceAll(<string>cnt, "");
        log:printDebug(string `    [base64-decode] clean base64 length: ${cleanB64.length()}`);

        int b64Limit = (maxBytes / 3 + 1) * 4 + 4;
        string b64Slice = cleanB64.length() > b64Limit ? cleanB64.substring(0, b64Limit) : cleanB64;

        byte[] decoded = check langarray:fromBase64(b64Slice);
        string rawStr = check string:fromBytes(decoded);
        string capped = rawStr.length() > maxBytes ? rawStr.substring(0, maxBytes) : rawStr;
        log:printDebug(string `    [base64-decode] decoded ${decoded.length()} bytes, returning ${capped.length()}`);
        return capped;
    } on fail error e {
        log:printDebug(string `    [base64-decode] failed: ${e.message()}`);
        return ();
    }
}

// ─── Claude API call ──────────────────────────────────────────────────────────

function callClaude(string apiKey, string model, json[] messages, string systemPrompt) returns json|error {
    log:printDebug(string `    [claude] calling API model=${model} messages=${messages.length()} promptLen=${systemPrompt.length()}`);
    time:Utc t0 = time:utcNow();

    http:Client cl = check new ("https://api.anthropic.com", {
        timeout: 120,
        secureSocket: {enable: true}
    });

    json body = {
        "model": model,
        "max_tokens": 1024,
        "temperature": 0,
        "system": systemPrompt,
        "tools": [FETCH_PAGE_TOOL],
        "messages": messages
    };

    http:Response resp = check cl->post("/v1/messages", body, {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    });

    decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
    log:printDebug(string `    [claude] response status=${resp.statusCode} elapsed=${elapsed}s`);

    if resp.statusCode != 200 {
        string errBody = check resp.getTextPayload();
        int cap = errBody.length() > 300 ? 300 : errBody.length();
        return error(string `Claude API ${resp.statusCode}: ${errBody.substring(0, cap)}`);
    }

    return check resp.getJsonPayload();
}

// ─── HTTP helpers ─────────────────────────────────────────────────────────────

isolated function isRawContentUrl(string rawUrl) returns boolean {
    string lo = rawUrl.toLowerAscii();
    if lo.includes("api.github.com") { return true; }
    if lo.endsWith(".yaml") || lo.endsWith(".yml") { return true; }
    if lo.endsWith(".json") { return true; }
    return false;
}

function httpGetBodyViaBrowserService(string targetUrl) returns string|error {
    log:printInfo(string `    [browser-service] ${targetUrl}`);
    log:printDebug(string `    [browser-service:debug] connecting to localhost:3456`);

    return withTimeout(function () returns string|error {
        time:Utc t0 = time:utcNow();
        http:Client cl = check new ("http://localhost:3456", {timeout: 30});
        string encodedUrl = check url:encode(targetUrl, "UTF-8");
        http:Response resp = check cl->get(string `/fetch?url=${encodedUrl}`);

        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
        log:printDebug(string `    [browser-service:debug] response status=${resp.statusCode} elapsed=${elapsed}s`);

        if resp.statusCode != 200 {
            string errBody = check resp.getTextPayload();
            int cap = errBody.length() > 200 ? 200 : errBody.length();
            return error(string `BrowserService ${resp.statusCode}: ${errBody.substring(0, cap)}`);
        }

        json respJson = check resp.getJsonPayload();
        map<json> respMap = check respJson.cloneWithType();

        json errField = respMap["error"];
        if errField != () && errField.toString().length() > 0 {
            return error(string `BrowserService error: ${errField.toString()}`);
        }

        json htmlField = respMap["html"];
        if htmlField == () {
            return error("BrowserService: missing html field in response");
        }

        string html = htmlField.toString();
        string capped = html.length() > 500000 ? html.substring(0, 500000) : html;
        log:printInfo(string `    [browser-service] OK — ${html.length()} bytes (capped to ${capped.length()})`);
        return capped;
    }, 35.0, "browser-service");
}

const int MIN_USEFUL_TEXT_LENGTH = 500;
const int SPEC_SNIPPET_BYTES = 12000;

function httpGetBody(string fetchUrl) returns string|error {
    string ghToken = os:getEnv("GITHUB_TOKEN");
    map<string|string[]> headers = {"User-Agent": "openapi-spec-finder/1.0"};
    if (fetchUrl.includes("api.github.com") || fetchUrl.includes("raw.githubusercontent.com")) && ghToken.length() > 0 {
        headers["Authorization"] = string `Bearer ${ghToken}`;
    }

    if isRawContentUrl(fetchUrl) {
        int snapCap = SPEC_SNIPPET_BYTES - 1;
        headers["Range"] = string `bytes=0-${snapCap}`;
        log:printDebug(string `    [httpGetBody:debug] raw-content URL — direct fetch (Range:0-${snapCap}): ${fetchUrl}`);

        return withTimeout(function () returns string|error {
            time:Utc t0 = time:utcNow();
            http:Client cl = check new (fetchUrl, {
                followRedirects: {enabled: true, maxCount: 5},
                timeout: 25,
                secureSocket: {enable: true}
            });
            http:Response resp = check cl->get("", headers);
            decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
            log:printDebug(string `    [httpGetBody:debug] raw response status=${resp.statusCode} elapsed=${elapsed}s`);
            if resp.statusCode != 200 && resp.statusCode != 206 {
                return error(string `HTTP ${resp.statusCode}`);
            }
            string body = check resp.getTextPayload();
            log:printDebug(string `    [httpGetBody:debug] raw body length=${body.length()}`);
            return body;
        }, 30.0, "raw-fetch");
    }

    log:printDebug(string `    [httpGetBody:debug] HTML page — trying plain HTTP: ${fetchUrl}`);
    string|error plainResult = httpGetBodyPlain(fetchUrl, headers, 100000);

    if plainResult is string {
        string textContent = htmlText(plainResult);
        if textContent.length() >= MIN_USEFUL_TEXT_LENGTH {
            log:printInfo(string `    [plain-http] OK — ${plainResult.length()} bytes (${textContent.length()} chars text)`);
            log:printDebug(string `    [httpGetBody:debug] plain HTTP succeeded, text=${textContent.length()} chars`);
            return plainResult;
        }
        log:printInfo(string `    [plain-http] SPA detected (only ${textContent.length()} chars text) — trying browser service`);
        log:printDebug(string `    [httpGetBody:debug] SPA shell detected — body=${plainResult.length()} bytes, text=${textContent.length()} chars`);
    } else {
        log:printInfo(string `    [plain-http] failed: ${plainResult.message()} — trying browser service`);
        log:printDebug(string `    [httpGetBody:debug] plain HTTP failed: ${plainResult.message()}`);
    }

    string|error browserResult = httpGetBodyViaBrowserService(fetchUrl);
    if browserResult is string {
        log:printDebug(string `    [httpGetBody:debug] browser service succeeded, body=${browserResult.length()} bytes`);
        return browserResult;
    }
    log:printInfo(string `    [browser-service] also failed: ${browserResult.message()} — using plain HTTP fallback`);
    log:printDebug(string `    [httpGetBody:debug] browser service failed: ${browserResult.message()} — falling back to plain HTTP result`);

    if plainResult is string {
        return plainResult;
    }
    return plainResult;
}

function httpGetBodyPlain(string fetchUrl, map<string|string[]> headers, int maxBytes) returns string|error {
    log:printDebug(string `    [plain-http:debug] GET ${fetchUrl} maxBytes=${maxBytes}`);

    return withTimeout(function () returns string|error {
        time:Utc t0 = time:utcNow();
        http:Client cl = check new (fetchUrl, {
            followRedirects: {enabled: true, maxCount: 5},
            timeout: 15,
            secureSocket: {enable: true}
        });
        http:Response resp = check cl->get("", headers);
        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
        log:printDebug(string `    [plain-http:debug] status=${resp.statusCode} elapsed=${elapsed}s`);

        if resp.statusCode != 200 {
            return error(string `HTTP ${resp.statusCode}`);
        }
        string body = check resp.getTextPayload();
        string result = body.length() > maxBytes ? body.substring(0, maxBytes) : body;
        log:printDebug(string `    [plain-http:debug] body=${body.length()} capped=${result.length()}`);
        return result;
    }, 20.0, "plain-http");
}

// ─── Full content fetch for Java parser validation ────────────────────────────

const int FULL_FETCH_MAX_BYTES = 20000000;

function httpGetBodyFull(string rawUrl) returns string|error {
    string ghToken = os:getEnv("GITHUB_TOKEN");
    map<string|string[]> headers = {"User-Agent": "openapi-spec-finder/1.0"};

    string fetchUrl = rawUrl;
    boolean isGitHubRaw = rawUrl.includes("raw.githubusercontent.com/");

    if isGitHubRaw {
        fetchUrl = rawUrlToApiUrl(rawUrl);
        headers["Accept"] = "application/vnd.github.raw";
        log:printDebug(string `    [full-fetch:debug] GitHub raw → Contents API: ${fetchUrl}`);
    }

    if (fetchUrl.includes("api.github.com") || rawUrl.includes("raw.githubusercontent.com")) && ghToken.length() > 0 {
        headers["Authorization"] = string `Bearer ${ghToken}`;
    }

    log:printDebug(string `    [full-fetch:debug] fetching full body: ${fetchUrl}`);

    string|error bodyOrErr = withTimeout(function () returns string|error {
        time:Utc t0 = time:utcNow();
        http:Client cl = check new (fetchUrl, {
            followRedirects: {enabled: true, maxCount: 5},
            timeout: 60,
            secureSocket: {enable: true}
        });
        http:Response resp = check cl->get("", headers);
        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
        log:printDebug(string `    [full-fetch:debug] status=${resp.statusCode} elapsed=${elapsed}s`);

        if resp.statusCode == 403 {
            // Signal to outer scope for Git Blobs fallback
            return error(string `HTTP 403`);
        }
        if resp.statusCode != 200 && resp.statusCode != 206 {
            return error(string `HTTP ${resp.statusCode}`);
        }
        return resp.getTextPayload();
    }, 65.0, "full-fetch");

    if bodyOrErr is error {
        if isGitHubRaw && bodyOrErr.message().includes("403") {
            log:printInfo(string `    [full-fetch] Contents API 403 — switching to Git Blobs API: ${rawUrl}`);
            return fetchViaGitBlobsApi(rawUrl, FULL_FETCH_MAX_BYTES, ghToken);
        }
        return bodyOrErr;
    }

    string body = bodyOrErr;
    log:printDebug(string `    [full-fetch:debug] body length=${body.length()}`);

    if isGitHubRaw && isGitHubTooLargeError(body) {
        log:printInfo(string `    [full-fetch] Contents API: file too large (>1 MB) — switching to Git Blobs API`);
        return fetchViaGitBlobsApi(rawUrl, FULL_FETCH_MAX_BYTES, ghToken);
    }

    if body.length() > FULL_FETCH_MAX_BYTES {
        log:printWarn(string `    [full-fetch] body exceeds ${FULL_FETCH_MAX_BYTES} bytes — capping`);
        return body.substring(0, FULL_FETCH_MAX_BYTES);
    }

    log:printDebug(string `    [full-fetch:debug] returning ${body.length()} bytes`);
    return body;
}

function headOk(string headUrl) returns boolean {
    log:printDebug(string `    [headOk:debug] HEAD ${headUrl}`);

    string|error result = withTimeout(function () returns string|error {
        time:Utc t0 = time:utcNow();
        string ghToken = os:getEnv("GITHUB_TOKEN");
        map<string|string[]> headers = {"User-Agent": "openapi-spec-finder/1.0"};
        if (headUrl.includes("api.github.com") || headUrl.includes("raw.githubusercontent.com")) && ghToken.length() > 0 {
            headers["Authorization"] = string `Bearer ${ghToken}`;
        }
        http:Client cl = check new (headUrl, {
            followRedirects: {enabled: true, maxCount: 5},
            timeout: 12,
            secureSocket: {enable: true}
        });
        http:Response r = check cl->head("", headers);
        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
        log:printDebug(string `    [headOk:debug] status=${r.statusCode} elapsed=${elapsed}s`);
        if r.statusCode == 200 { return "ok"; }
        if r.statusCode == 405 || r.statusCode == 501 {
            log:printDebug("    [headOk:debug] HEAD not allowed, trying GET");
            http:Response r2 = check cl->get("", headers);
            if r2.statusCode == 200 { return "ok"; }
            return error(string `GET fallback returned ${r2.statusCode}`);
        }
        return error(string `HEAD returned ${r.statusCode}`);
    }, 15.0, "head-check");

    if result is string {
        return true;
    }
    log:printDebug(string `    [headOk:debug] failed: ${result.message()}`);
    return false;
}

function httpGetBodyPartial(string rawUrl, int maxBytes) returns string|error {
    string ghToken = os:getEnv("GITHUB_TOKEN");
    map<string|string[]> headers = {"User-Agent": "openapi-spec-finder/1.0"};

    string fetchUrl = rawUrl;
    boolean isGitHubRaw = rawUrl.includes("raw.githubusercontent.com/");

    if isGitHubRaw {
        fetchUrl = rawUrlToApiUrl(rawUrl);
        headers["Accept"] = "application/vnd.github.raw";
        log:printDebug(string `    [partial-fetch:debug] GitHub raw → Contents API: ${fetchUrl}`);
    }

    if (fetchUrl.includes("api.github.com") || rawUrl.includes("raw.githubusercontent.com")) && ghToken.length() > 0 {
        headers["Authorization"] = string `Bearer ${ghToken}`;
    }

    if !isGitHubRaw && !fetchUrl.includes("api.github.com") {
        int rangeEnd = maxBytes - 1;
        headers["Range"] = string `bytes=0-${rangeEnd}`;
    }

    string|error bodyOrErr = withTimeout(function () returns string|error {
        time:Utc t0 = time:utcNow();
        http:Client cl = check new (fetchUrl, {
            followRedirects: {enabled: true, maxCount: 5},
            timeout: 25,
            secureSocket: {enable: true}
        });
        http:Response resp = check cl->get("", headers);
        decimal elapsed = rd(time:utcDiffSeconds(time:utcNow(), t0));
        log:printDebug(string `    [partial-fetch:debug] status=${resp.statusCode} elapsed=${elapsed}s`);

        if resp.statusCode != 200 && resp.statusCode != 206 {
            return error(string `HTTP ${resp.statusCode}`);
        }
        return resp.getTextPayload();
    }, 30.0, "partial-fetch");

    if bodyOrErr is error { return bodyOrErr; }
    string body = bodyOrErr;
    log:printDebug(string `    [partial-fetch:debug] body length=${body.length()}`);

    if isGitHubRaw && isGitHubTooLargeError(body) {
        log:printInfo(string `    [partial-fetch] Contents API: file too large — switching to Git Blobs API`);
        return fetchViaGitBlobsApi(rawUrl, maxBytes, ghToken);
    }

    string result = body.length() > maxBytes ? body.substring(0, maxBytes) : body;
    return result;
}

isolated function isGitHubTooLargeError(string body) returns boolean {
    if body.includes("\"too_large\"") { return true; }
    if body.includes("too large to fetch via the API") { return true; }
    if body.includes("larger than") && body.includes("blob") { return true; }
    if body.includes("\"encoding\":\"none\"") && body.includes("\"content\":\"\"") { return true; }
    return false;
}

isolated function rawUrlToApiUrl(string rawUrl) returns string {
    string prefix = "raw.githubusercontent.com/";
    int? pi = rawUrl.indexOf(prefix);
    if pi is () { return rawUrl; }
    string rest = rawUrl.substring(pi + prefix.length());

    int? s1 = rest.indexOf("/");
    if s1 is () { return rawUrl; }
    string owner = rest.substring(0, s1);
    string rem1 = rest.substring(s1 + 1);

    int? s2 = rem1.indexOf("/");
    if s2 is () { return rawUrl; }
    string repo = rem1.substring(0, s2);
    string rem2 = rem1.substring(s2 + 1);

    int? s3 = rem2.indexOf("/");
    if s3 is () { return rawUrl; }
    string branch = rem2.substring(0, s3);
    string path = rem2.substring(s3 + 1);

    return string `https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${branch}`;
}

function getContentLength(string contentUrl) returns int {
    log:printDebug(string `    [content-length:debug] checking ${contentUrl}`);

    string|error result = withTimeout(function () returns string|error {
        string ghToken = os:getEnv("GITHUB_TOKEN");
        map<string|string[]> headers = {"User-Agent": "openapi-spec-finder/1.0"};
        if (contentUrl.includes("api.github.com") || contentUrl.includes("raw.githubusercontent.com")) && ghToken.length() > 0 {
            headers["Authorization"] = string `Bearer ${ghToken}`;
        }
        http:Client cl = check new (contentUrl, {
            followRedirects: {enabled: true, maxCount: 5},
            timeout: 12,
            secureSocket: {enable: true}
        });
        http:Response r = check cl->head("", headers);
        if r.statusCode == 200 {
            string clHeader = check r.getHeader("content-length");
            return clHeader;
        }
        return error(string `HEAD returned ${r.statusCode}`);
    }, 15.0, "content-length");

    if result is string {
        int|error parsed = int:fromString(result);
        if parsed is int {
            log:printDebug(string `    [content-length:debug] Content-Length=${parsed}`);
            return parsed;
        }
    } else {
        log:printDebug(string `    [content-length:debug] failed: ${result.message()}`);
    }
    return 0;
}

// ─── Inference helper ─────────────────────────────────────────────────────────

isolated function inferRepoFromRawUrl(string rawUrl) returns string? {
    string prefix = "raw.githubusercontent.com/";
    int? pi = rawUrl.indexOf(prefix);
    if pi is () { return (); }
    string rest = rawUrl.substring(pi + prefix.length());
    string[] parts = splitOn(rest, "/");
    if parts.length() >= 2 {
        return parts[0] + "/" + parts[1];
    }
    return ();
}

// ─── Parse SPEC_CANDIDATES output ────────────────────────────────────────────

function pickBestCandidate(string text) returns SpecResult? {
    log:printDebug("    [pickBestCandidate:debug] parsing SPEC_CANDIDATES block");
    int? idx = text.indexOf("SPEC_CANDIDATES:");
    if idx is () { return (); }
    string after = text.substring(idx + 16);

    string? specRepo = ();
    int? repoIdx = text.indexOf("SPEC_REPO:");
    if repoIdx is int {
        string repoLine = text.substring(repoIdx + 10);
        string[] repoLines = splitLines(repoLine);
        if repoLines.length() > 0 {
            string repo = repoLines[0].trim();
            if repo.length() > 0 { specRepo = repo; }
        }
    }

    string[] urls = [];
    map<boolean> seen = {};

    foreach string line in splitLines(after) {
        string t = line.trim();
        if t.startsWith("SPEC_REPO:") { break; }
        if !t.startsWith("http") { continue; }

        string candidateUrl = t;
        if candidateUrl.includes("github.com/") && candidateUrl.includes("/blob/") {
            int? ghIdx = candidateUrl.indexOf("github.com/");
            if ghIdx is int {
                string rest = candidateUrl.substring(ghIdx + 11);
                string[] parts = splitOn(rest, "/blob/");
                if parts.length() == 2 {
                    candidateUrl = "https://raw.githubusercontent.com/" + parts[0] + "/" + parts[1];
                }
            }
        }

        if !seen.hasKey(candidateUrl) { seen[candidateUrl] = true; urls.push(candidateUrl); }

        if candidateUrl.includes("raw.githubusercontent.com/") {
            if specRepo is () {
                specRepo = inferRepoFromRawUrl(candidateUrl);
            }
            string alt = "";
            if candidateUrl.includes("/main/") {
                int? mi = candidateUrl.indexOf("/main/");
                if mi is int { alt = candidateUrl.substring(0, mi) + "/master/" + candidateUrl.substring(mi + 6); }
            } else if candidateUrl.includes("/master/") {
                int? mi = candidateUrl.indexOf("/master/");
                if mi is int { alt = candidateUrl.substring(0, mi) + "/main/" + candidateUrl.substring(mi + 8); }
            }
            if alt.length() > 0 && !seen.hasKey(alt) { seen[alt] = true; urls.push(alt); }
        }
    }

    log:printDebug(string `    [pickBestCandidate:debug] found ${urls.length()} candidate URLs to try`);
    foreach string candidateUrl in urls {
        log:printInfo(string `  [check] ${candidateUrl}`);
        if headOk(candidateUrl) {
            string fmt = candidateUrl.toLowerAscii().endsWith(".json") ? "json" : "yaml";
            log:printInfo(string `  [ok] ${candidateUrl}`);
            return {specUrl: candidateUrl, specRepo: specRepo, apiVersion: (), format: fmt};
        }
        log:printInfo(string `  [dead] ${candidateUrl}`);
    }

    log:printInfo("  [agent] all candidate URLs failed HEAD check");
    return ();
}

// ─── HTML link extraction ─────────────────────────────────────────────────────

isolated function extractHrefs(string html, string baseUrl) returns string[] {
    string[] links = [];
    map<boolean> seen = {};
    string rem = html;

    while rem.length() > 0 && links.length() < 400 {
        string loRem = rem.toLowerAscii();
        int? idx = loRem.indexOf("href=");
        if idx is () { break; }
        int after = idx + 5;
        if after >= rem.length() { break; }
        string q = rem[after];
        if q != "\"" && q != "'" { rem = rem.substring(after); continue; }
        int valStart = after + 1;
        int valEnd = valStart;
        while valEnd < rem.length() && rem[valEnd] != q { valEnd += 1; }
        if valEnd >= rem.length() { rem = rem.substring(after); continue; }
        string href = rem.substring(valStart, valEnd);
        rem = rem.substring(valEnd + 1);
        string full = resolveUrl(href, baseUrl);
        if full.length() > 0 && !seen.hasKey(full) {
            seen[full] = true;
            links.push(full);
        }
    }
    return links;
}

isolated function isSpecLink(string linkUrl) returns boolean {
    string lo = linkUrl.toLowerAscii();
    if lo.endsWith(".yaml") || lo.endsWith(".yml") { return true; }
    if lo.includes("raw.githubusercontent.com") { return true; }
    if lo.includes("api.github.com") { return true; }
    if lo.includes("github.com/") { return true; }
    string[] kw = ["openapi", "swagger", "/spec", "/defs/", "api-description", "download", "reference"];
    foreach string k in kw {
        if lo.includes(k) { return true; }
    }
    if lo.endsWith(".json") && (lo.includes("api") || lo.includes("spec")) { return true; }
    return false;
}

isolated function htmlText(string html) returns string {
    string result = "";
    boolean inTag = false;
    boolean lastSpace = false;
    foreach string ch in html {
        if ch == "<" { inTag = true; continue; }
        if ch == ">" { inTag = false; result += " "; lastSpace = true; continue; }
        if inTag { continue; }
        boolean sp = ch == " " || ch == "\n" || ch == "\t" || ch == "\r";
        if sp { if !lastSpace { result += " "; lastSpace = true; } }
        else { result += ch; lastSpace = false; }
    }
    return result.trim();
}

isolated function resolveUrl(string href, string base) returns string {
    if href.length() == 0 { return ""; }
    if href.startsWith("http://") || href.startsWith("https://") { return href; }
    if href.startsWith("//") {
        string[] p = splitOn(base, "://");
        return (p.length() > 0 ? p[0] : "https") + ":" + href;
    }
    if href.startsWith("/") { return origin(base) + href; }
    if href.startsWith("#") || href.startsWith("javascript") || href.startsWith("mailto") || href.startsWith("data:") { return ""; }
    return dir(base) + href;
}

isolated function origin(string urlStr) returns string {
    string[] p = splitOn(urlStr, "://");
    if p.length() < 2 { return ""; }
    int? si = p[1].indexOf("/");
    return si is int ? p[0] + "://" + p[1].substring(0, si) : p[0] + "://" + p[1];
}

isolated function dir(string urlStr) returns string {
    int i = urlStr.length() - 1;
    while i >= 0 { if urlStr[i] == "/" { return urlStr.substring(0, i + 1); } i -= 1; }
    return urlStr + "/";
}

// ─── String utilities ─────────────────────────────────────────────────────────

isolated function splitOn(string s, string sep) returns string[] {
    string[] parts = [];
    string rem = s;
    while rem.length() > 0 {
        int? idx = rem.indexOf(sep);
        if idx is int { parts.push(rem.substring(0, idx)); rem = rem.substring(idx + sep.length()); }
        else { parts.push(rem); break; }
    }
    return parts;
}

isolated function splitLines(string s) returns string[] {
    return splitOn(s, "\n");
}

isolated function jsonEsc(string s) returns string {
    string r = "";
    foreach string ch in s {
        if ch == "\\" { r += "\\\\"; }
        else if ch == "\"" { r += "\\\""; }
        else if ch == "\n" { r += "\\n"; }
        else if ch == "\r" { r += "\\r"; }
        else if ch == "\t" { r += "\\t"; }
        else { r += ch; }
    }
    return r;
}

isolated function jsonStr(string s) returns string {
    return "\"" + jsonEsc(s) + "\"";
}

isolated function jsonArr(string[] items) returns string {
    string r = "[";
    boolean first = true;
    foreach string item in items {
        if !first { r += ","; }
        r += jsonStr(item);
        first = false;
    }
    return r + "]";
}

isolated function timeNow() returns string {
    return time:utcToString(time:utcNow());
}

isolated function rd(decimal d) returns decimal {
    return <decimal>(<int>(d * 10d)) / 10d;
}
