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

// openapi_validator.bal
// Ballerina bridge to OpenAPISpecValidator.java (via Java interop).
//
// The fat JAR must be built first:
//   cd java-validator && ./build.sh
//
// That script copies the JAR to libs/openapi-validator.jar.
// The [[platform.java21.dependency]] block in Ballerina.toml must be active.
//
// Usage (internal — called from pipeline.bal):
//   [boolean, string] [ok, detail] = javaValidateSpec(content);
//   // ok=true,  detail="3.0.3"                    → valid OAS3 spec
//   // ok=true,  detail="2.0"                      → valid Swagger 2.0 spec
//   // ok=false, detail=reason                     → invalid spec
//   // ok=false, detail="java-validator-unavailable" → JAR not on classpath

import ballerina/jballerina.java;
import ballerina/log;

// ─── Raw Java binding ─────────────────────────────────────────────────────────

// Mirrors OpenAPISpecValidator.validate(String content) → String
// Returns "valid:<version>" or "invalid:<reason>"
isolated function javaValidateInternal(handle content) returns handle = @java:Method {
    'class: "org.ballerinax.openapi.OpenAPISpecValidator",
    name: "validate",
    paramTypes: ["java.lang.String"]
} external;

// ─── Public API ───────────────────────────────────────────────────────────────

// Validates spec content using the Java swagger-parser library.
// Returns [isValid, detail]:
//   [true,  "3.0.3"]                      → valid OAS3 spec
//   [true,  "2.0"  ]                      → valid Swagger 2.0 spec
//   [false, reason ]                      → not a valid spec
//   [false, "java-validator-unavailable"] → JAR not on classpath; caller should
//                                           fall back to a text-based heuristic
public function javaValidateSpec(string content) returns [boolean, string] {
    do {
        handle resultHandle = javaValidateInternal(java:fromString(content));
        string? resultStr = java:toString(resultHandle);
        string res = resultStr is () ? "invalid:null" : resultStr;
        int cap = res.length() > 120 ? 120 : res.length();
        log:printDebug(string `  [java-validator] result: ${res.substring(0, cap)}`);
        if res.startsWith("valid:") {
            return [true, res.substring(6)];
        }
        string reason = res.startsWith("invalid:") ? res.substring(8) : res;
        return [false, reason];
    } on fail error e {
        // ClassNotFoundException or similar — JAR not on classpath
        log:printDebug(string `  [java-validator] unavailable (JAR not built yet): ${e.message()}`);
        return [false, "java-validator-unavailable"];
    }
}
