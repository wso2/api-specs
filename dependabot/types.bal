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

public type Frequency "daily"|"weekly"|"monthly"|"quarterly";

public type Status "pending"|"found"|"found_malformed"|"not_found";

public type Connector record {|
    string name;
    string sourceUrl;
    string? targetTitle;
|};

public type SpecResult record {|
    string specUrl;
    string? specRepo;
    string? apiVersion;
    string format;
    boolean malformed = false;
    string? validationError = ();
|};

// All fields except name and sourceUrl have defaults so that a user can add a
// new entry to openapi_specs.json with just {"name":"…","sourceUrl":"…","connectorRepo":"…"}.
public type ResultEntry record {|
    string name;
    string sourceUrl;
    string? connectorRepo = ();
    string? targetTitle = ();
    string? specUrl = ();
    string? specRepo = ();
    string? apiVersion = ();
    string? format = ();
    Frequency? frequency = "monthly";
    Status status = "pending";
    string checkedAt = "";
    decimal elapsedSeconds = 0.0d;
    string? contentHash = ();
    string? validationError = ();
|};

// Output of the discovery step
public type DiscoveryResult record {|
    string[] candidateUrls;   // raw downloadable URLs to try
    string? specRepo;         // github owner/repo if found
    string discoveryMethod;   // "known_url_valid" | "github" | "direct" | "none"
|};

// Output of the verification step
public type VerifyResult record {|
    string specUrl;
    string? specRepo;
    string format;
    string openApiVersion;    // e.g. "3.0.3"
    string apiVersion;        // from info.version
|};
