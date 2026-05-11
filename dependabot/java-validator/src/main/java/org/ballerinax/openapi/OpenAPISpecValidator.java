package org.ballerinax.openapi;

import io.swagger.parser.OpenAPIParser;
import io.swagger.v3.parser.core.models.SwaggerParseResult;
import io.swagger.v3.parser.core.models.ParseOptions;

/**
 * OpenAPISpecValidator — thin wrapper around swagger-parser for use via
 * Ballerina Java interoperability.
 *
 * All methods take and return plain Java Strings so no Ballerina runtime
 * types are needed on the compile-time classpath.
 *
 * Build: cd java-validator && mvn package -DskipTests
 *        (produces target/openapi-validator-jar-with-dependencies.jar)
 * Then copy it:  cp target/openapi-validator-jar-with-dependencies.jar ../libs/openapi-validator.jar
 */
public class OpenAPISpecValidator {

    /**
     * Validates a string of OpenAPI/Swagger spec content.
     *
     * @param content Raw YAML or JSON content of the spec (may be truncated).
     * @return "valid:<openapi-version>" if it is a valid spec,
     *         "invalid:<reason>" otherwise.
     */
    public static String validate(String content) {
        if (content == null || content.trim().isEmpty()) {
            return "invalid:empty content";
        }
        try {
            ParseOptions opts = new ParseOptions();
            opts.setResolve(false);           // Don't try to resolve $ref URLs

            SwaggerParseResult result = new OpenAPIParser()
                    .readContents(content, null, opts);

            if (result == null) {
                return "invalid:parser returned null";
            }

            if (result.getOpenAPI() != null) {
                String version = result.getOpenAPI().getOpenapi();
                if (version == null || version.isEmpty()) {
                    // getSpecVersion() is more reliable for Swagger 2.0 specs where
                    // getOpenapi() returns null; fall back to "2.0" if both are absent.
                    Object specVersion = result.getOpenAPI().getSpecVersion();
                    version = specVersion != null ? specVersion.toString() : "2.0";
                }
                return "valid:" + version;
            }

            // Build a concise reason from parse messages
            String reason = "not an OpenAPI spec";
            if (result.getMessages() != null && !result.getMessages().isEmpty()) {
                reason = result.getMessages().get(0);
                if (reason.length() > 200) {
                    reason = reason.substring(0, 200);
                }
            }
            return "invalid:" + reason;

        } catch (Exception e) {
            String msg = e.getMessage();
            if (msg == null) msg = e.getClass().getName();
            if (msg.length() > 200) msg = msg.substring(0, 200);
            return "invalid:exception: " + msg;
        }
    }

    /**
     * Quick boolean check — true if content is a valid OpenAPI/Swagger spec.
     */
    public static boolean isValid(String content) {
        return validate(content).startsWith("valid:");
    }
}
