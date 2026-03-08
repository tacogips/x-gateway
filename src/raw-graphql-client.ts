import type {
  XGatewayAuthConfig,
  XGatewayError,
  XGatewayErrorPayload,
  XGatewayOperationType,
  XGatewayRequestOptions,
} from "./lib";

type OptionalTrace = (traceId?: string) => Readonly<{ traceId?: string }>;

type RawGraphqlRequesterDependencies = Readonly<{
  auth: XGatewayAuthConfig;
  configuredAuthMode: "oauth1" | "bearer" | undefined;
  graphqlBaseUrl: string;
  executeWithRetry: <T>(
    operation: () => Promise<T>,
    traceId?: string,
  ) => Promise<T>;
  createError: (payload: XGatewayErrorPayload) => XGatewayError;
  createValidationError: (message: string) => XGatewayError;
  createUnsupportedError: (
    subject: string,
    details: string,
    remediations?: readonly string[],
  ) => XGatewayError;
  withOptionalTrace: OptionalTrace;
}>;

function isNonEmpty(value: string | undefined): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function parseRetryAfterMs(headerValue: string | null): number | undefined {
  if (headerValue === null || !isNonEmpty(headerValue)) {
    return undefined;
  }

  const seconds = Number(headerValue);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.floor(seconds * 1000);
  }

  const retryAt = Date.parse(headerValue);
  if (!Number.isFinite(retryAt)) {
    return undefined;
  }

  return Math.max(retryAt - Date.now(), 0);
}

function validateOperationType(
  operationType: XGatewayOperationType | undefined,
  createValidationError: (message: string) => XGatewayError,
): XGatewayOperationType {
  if (
    operationType === undefined ||
    operationType === "query" ||
    operationType === "mutation"
  ) {
    return operationType ?? "query";
  }

  throw createValidationError(
    "operationType must be either 'query' or 'mutation'.",
  );
}

function encodeGraphqlOperationName(operationName: string): string {
  return encodeURIComponent(operationName);
}

function joinGraphqlEndpoint(
  baseUrl: string,
  documentId: string,
  operationName: string,
): string {
  const trimmedBase = baseUrl.replace(/\/+$/, "");
  return `${trimmedBase}/${encodeURIComponent(documentId)}/${encodeGraphqlOperationName(operationName)}`;
}

async function parseResponseBody(response: Response): Promise<unknown> {
  const contentType = response.headers.get("content-type") ?? "";
  if (
    contentType.includes("application/json") ||
    contentType.includes("+json")
  ) {
    return (await response.json()) as unknown;
  }
  const text = await response.text();
  return { raw: text };
}

export function createRawGraphqlRequester(
  dependencies: RawGraphqlRequesterDependencies,
): Readonly<{
  request: <T>(options: XGatewayRequestOptions) => Promise<T>;
}> {
  function ensureRequired(value: string | undefined, fieldName: string): string {
    if (!isNonEmpty(value)) {
      throw dependencies.createValidationError(`${fieldName} is required.`);
    }
    return value;
  }

  function getGraphqlBearerToken(): string {
    if (
      dependencies.configuredAuthMode === "bearer" &&
      isNonEmpty(dependencies.auth.token)
    ) {
      return dependencies.auth.token;
    }
    if (dependencies.configuredAuthMode === "oauth1") {
      throw dependencies.createUnsupportedError(
        "GraphQL transport authentication",
        "GraphQL-only mode currently supports bearer-token authentication only. OAuth1 credentials cannot be translated automatically.",
        [
          "Set X_GW_TOKEN or pass auth.token when creating the client.",
          "Add an explicit GraphQL auth adapter before enabling OAuth1-only callers.",
        ],
      );
    }
    throw dependencies.createError({
      code: "AUTH_MISSING",
      summary: "Authentication configuration missing",
      details:
        "GraphQL requests require X_GW_TOKEN or auth.token. OAuth1-only credentials are not sufficient in the current GraphQL-only transport.",
      likelyCauses: [
        "Bearer token was not configured",
        "Only OAuth1 credentials were provided",
      ],
      remediations: [
        "Set X_GW_TOKEN for CLI usage.",
        "Or pass auth.token when creating the client.",
      ],
      classification: "auth",
      retryable: false,
    });
  }

  async function request<T>(options: XGatewayRequestOptions): Promise<T> {
    const {
      operationName,
      operationType,
      documentId,
      query,
      variables,
      features,
      fieldToggles,
      traceId,
    } = options;
    const safeOperationName = ensureRequired(operationName, "operationName");
    const safeOperationType = validateOperationType(
      operationType,
      dependencies.createValidationError,
    );
    const hasDocumentId = isNonEmpty(documentId);
    const hasQuery = isNonEmpty(query);
    if (!hasDocumentId && !hasQuery) {
      throw dependencies.createValidationError(
        "GraphQL request requires either documentId for persisted queries or query for an inline GraphQL document.",
      );
    }
    if (hasDocumentId && hasQuery) {
      throw dependencies.createValidationError(
        "GraphQL request must include exactly one request source: either documentId or query, but not both.",
      );
    }

    const token = getGraphqlBearerToken();
    return dependencies.executeWithRetry(async () => {
      const endpoint = hasDocumentId
        ? joinGraphqlEndpoint(
            dependencies.graphqlBaseUrl,
            documentId,
            safeOperationName,
          )
        : dependencies.graphqlBaseUrl;
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
          "x-twitter-active-user": "yes",
        },
        body: JSON.stringify({
          operationName: safeOperationName,
          operationType: safeOperationType,
          query,
          variables: variables ?? {},
          features: features ?? {},
          fieldToggles: fieldToggles ?? {},
        }),
      });

      const payload = await parseResponseBody(response);
      if (!response.ok) {
        const retryAfterMs = parseRetryAfterMs(
          response.headers.get("retry-after"),
        );
        const detail =
          typeof payload === "object" && payload !== null
            ? JSON.stringify(payload)
            : String(payload);
        throw dependencies.createError({
          code:
            response.status === 401
              ? "AUTH_INVALID"
              : response.status === 403
                ? "PERMISSION_DENIED"
                : response.status === 404
                  ? "RESOURCE_NOT_FOUND"
                  : response.status === 409
                    ? "CONFLICT"
                    : response.status === 429
                      ? "RATE_LIMITED"
                      : "UPSTREAM_FAILURE",
          summary: "GraphQL request failed",
          details: `HTTP ${response.status} returned from GraphQL endpoint for operation '${safeOperationName}'. Response body: ${detail}`,
          likelyCauses: [
            "Persisted query id is invalid or stale",
            "GraphQL operation variables/features do not match upstream expectations",
            "Credential lacks permission for the requested GraphQL operation",
          ],
          remediations: [
            "Verify the GraphQL documentId or inline query and retry.",
            "Inspect the variables/features payload for schema mismatches.",
            "Confirm the bearer token is valid for the target operation.",
          ],
          classification:
            response.status === 401
              ? "auth"
              : response.status === 403
                ? "permission"
                : response.status === 429
                  ? "rate_limit"
                  : "upstream",
          retryable: response.status === 429 || response.status >= 500,
          httpStatus: response.status,
          ...(retryAfterMs === undefined ? {} : { retryAfterMs }),
          ...dependencies.withOptionalTrace(traceId),
        });
      }

      if (
        typeof payload === "object" &&
        payload !== null &&
        "errors" in payload &&
        Array.isArray((payload as { errors?: unknown }).errors) &&
        ((payload as { errors?: readonly unknown[] }).errors?.length ?? 0) > 0
      ) {
        throw dependencies.createError({
          code: "UPSTREAM_FAILURE",
          summary: "GraphQL response included errors",
          details: JSON.stringify(
            (payload as { errors: readonly unknown[] }).errors,
          ),
          likelyCauses: [
            "Operation variables or feature flags do not satisfy the upstream schema",
            "The operation is blocked for the current account, scope, or rollout state",
          ],
          remediations: [
            "Inspect GraphQL errors and align the request shape with the upstream schema.",
            "Retry only after correcting variables, features, or credentials.",
          ],
          classification: "upstream",
          retryable: false,
          ...dependencies.withOptionalTrace(traceId),
        });
      }

      return payload as T;
    }, traceId);
  }

  return {
    request,
  };
}
