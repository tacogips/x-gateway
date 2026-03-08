export type XGatewayErrorCode =
  | "VALIDATION_ERROR"
  | "AUTH_MISSING"
  | "AUTH_INVALID"
  | "AUTH_EXPIRED"
  | "AUTH_REVOKED"
  | "PERMISSION_DENIED"
  | "RATE_LIMITED"
  | "RESOURCE_NOT_FOUND"
  | "CONFLICT"
  | "UPSTREAM_FAILURE"
  | "NETWORK_FAILURE"
  | "UNSUPPORTED"
  | "INTERNAL_ERROR";

export type XGatewayErrorClassification =
  | "validation"
  | "auth"
  | "permission"
  | "rate_limit"
  | "network"
  | "upstream"
  | "unsupported"
  | "internal";

export type RetryBackoffStrategy = "exponential-jitter" | "fixed" | "none";
export type XGatewayAuthMode = "env" | "params" | "mixed";
export type XGatewayOperationType = "query" | "mutation";

export type XGatewayAuthConfig = Readonly<{
  token?: string | undefined;
  consumerKey?: string | undefined;
  consumerSecret?: string | undefined;
  accessToken?: string | undefined;
  accessTokenSecret?: string | undefined;
  clientId?: string | undefined;
  clientSecret?: string | undefined;
}>;

export type XGatewayRetryConfig = Readonly<{
  retries?: number | undefined;
  backoff?: RetryBackoffStrategy | undefined;
  baseDelayMs?: number | undefined;
  maxDelayMs?: number | undefined;
}>;

export type XGatewayConfig = Readonly<{
  authMode?: XGatewayAuthMode | undefined;
  auth?: XGatewayAuthConfig | undefined;
  graphqlBaseUrl?: string | undefined;
  timeoutMs?: number | undefined;
  retry?: XGatewayRetryConfig | undefined;
  strictCapabilityChecks?: boolean | undefined;
}>;

export type XGatewayResolvedConfig = Readonly<{
  authMode: XGatewayAuthMode;
  auth: XGatewayAuthConfig;
  graphqlBaseUrl?: string;
  timeoutMs: number;
  retry: Readonly<{
    retries: number;
    backoff: RetryBackoffStrategy;
    baseDelayMs: number;
    maxDelayMs: number;
  }>;
  strictCapabilityChecks: boolean;
}>;

export type XGatewayErrorPayload = Readonly<{
  code: XGatewayErrorCode;
  summary: string;
  details: string;
  likelyCauses: readonly string[];
  remediations: readonly string[];
  classification: XGatewayErrorClassification;
  retryable: boolean;
  httpStatus?: number;
  traceId?: string;
  attempts?: number;
  elapsedMs?: number;
  retryAfterMs?: number;
}>;

const DEFAULT_TIMEOUT_MS = 30_000;
const DEFAULT_RETRY_COUNT = 2;
const DEFAULT_RETRY_BASE_MS = 300;
const DEFAULT_RETRY_MAX_MS = 10_000;
const DEFAULT_GRAPHQL_BASE_URL = "https://x.com/i/api/graphql";

const CAPABILITY_REGISTRY: readonly CapabilityDescriptor[] = [
  {
    id: "graphql.request",
    endpointFamily: "graphql",
    operation: "raw GraphQL query or mutation execution",
    status: "implemented",
    authModes: ["bearer"],
    notes:
      "Primary GraphQL-first interface. Requires operationName plus documentId or inline query, and bearer auth.",
  },
  {
    id: "auth.verify",
    endpointFamily: "auth",
    operation: "verify identity and access",
    status: "blocked_by_plan",
    authModes: ["bearer", "oauth1"],
    notes: "GraphQL-only transport is enforced; operation mapping is not defined yet.",
  },
  {
    id: "post.create",
    endpointFamily: "posts",
    operation: "create post/reply/quote",
    status: "blocked_by_plan",
    authModes: ["bearer", "oauth1"],
    notes: "GraphQL-only transport is enforced; mutation mapping is not defined yet.",
  },
  {
    id: "post.article",
    endpointFamily: "posts",
    operation: "long-form article style post",
    status: "blocked_by_scope",
    authModes: ["bearer", "oauth1"],
    notes: "Depends on provider-level article availability; strict mode can block.",
  },
  {
    id: "media.upload",
    endpointFamily: "media",
    operation: "upload media and set alt text",
    status: "blocked_by_plan",
    authModes: ["oauth1", "bearer"],
    notes: "REST v1 upload flow was removed; GraphQL/media upload mapping is pending.",
  },
  {
    id: "tweet.references",
    endpointFamily: "tweets",
    operation: "thread, quote, likes, retweet user views",
    status: "blocked_by_plan",
    authModes: ["bearer", "oauth1"],
    notes: "GraphQL-only transport is enforced; query mapping is not defined yet.",
  },
  {
    id: "timeline.search",
    endpointFamily: "timelines",
    operation: "home/user/mentions/recent search with pagination",
    status: "blocked_by_plan",
    authModes: ["bearer", "oauth1"],
    notes: "GraphQL-only transport is enforced; query mapping is not defined yet.",
  },
  {
    id: "social.follows",
    endpointFamily: "social-graph",
    operation: "followers/following and follow/unfollow mutations",
    status: "blocked_by_plan",
    authModes: ["bearer", "oauth1"],
    notes: "GraphQL-only transport is enforced; query and mutation mapping is not defined yet.",
  },
  {
    id: "dm.core",
    endpointFamily: "dm",
    operation: "send/list direct messages",
    status: "blocked_by_scope",
    authModes: ["oauth1", "bearer"],
    notes: "Availability varies by auth mode and API tier.",
  },
];

function readEnv(name: string): string | undefined {
  const raw = process.env[name];
  if (!raw) {
    return undefined;
  }
  const value = raw.trim();
  return value.length > 0 ? value : undefined;
}

function parseIntegerEnv(
  input: string | undefined,
  fallback: number,
  name: string,
  minimum: number,
): number {
  if (!input) {
    return fallback;
  }
  if (!/^(0|[1-9][0-9]*)$/.test(input)) {
    throw createValidationError(
      `${name} must be an integer greater than or equal to ${minimum}.`,
    );
  }
  const parsed = Number.parseInt(input, 10);
  if (!Number.isFinite(parsed) || parsed < minimum) {
    throw createValidationError(
      `${name} must be an integer greater than or equal to ${minimum}.`,
    );
  }
  return parsed;
}

function validateRetryBackoff(
  input: string | undefined,
  fallback: RetryBackoffStrategy,
  name: string,
): RetryBackoffStrategy {
  if (!input) {
    return fallback;
  }
  if (
    input === "exponential-jitter" ||
    input === "fixed" ||
    input === "none"
  ) {
    return input;
  }
  throw createValidationError(
    `${name} must be one of 'exponential-jitter', 'fixed', or 'none'.`,
  );
}

function validateAuthMode(
  input: string | undefined,
  fallback: XGatewayAuthMode,
  name: string,
): XGatewayAuthMode {
  if (!input) {
    return fallback;
  }
  if (input === "env" || input === "params" || input === "mixed") {
    return input;
  }
  throw createValidationError(
    `${name} must be one of 'env', 'params', or 'mixed'.`,
  );
}

function parseBoolean(
  input: string | undefined,
  fallback: boolean,
  name: string,
): boolean {
  if (!input) {
    return fallback;
  }
  const normalized = input.toLowerCase();
  if (normalized === "true" || normalized === "1" || normalized === "yes") {
    return true;
  }
  if (normalized === "false" || normalized === "0" || normalized === "no") {
    return false;
  }
  throw createValidationError(`${name} must be a boolean value ('true' or 'false').`);
}

function validateOptionalInteger(
  input: number | undefined,
  name: string,
  minimum: number,
): number | undefined {
  if (input === undefined) {
    return undefined;
  }
  if (!Number.isInteger(input) || input < minimum) {
    throw createValidationError(
      `${name} must be an integer greater than or equal to ${minimum}.`,
    );
  }
  return input;
}

function validateOptionalGraphqlBaseUrl(
  input: string | undefined,
  name: string,
): string | undefined {
  if (input === undefined) {
    return undefined;
  }
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    throw createValidationError(`${name} must not be empty.`);
  }
  let protocol: string;
  try {
    protocol = new globalThis.URL(trimmed).protocol;
  } catch {
    throw createValidationError(`${name} must be an absolute http(s) URL.`);
  }
  if (protocol !== "http:" && protocol !== "https:") {
    throw createValidationError(`${name} must use http or https.`);
  }
  return trimmed;
}

export function resolveConfig(config: XGatewayConfig = {}): XGatewayResolvedConfig {
  const authMode = validateAuthMode(
    config.authMode ?? readEnv("X_GW_AUTH_MODE"),
    "mixed",
    config.authMode === undefined ? "X_GW_AUTH_MODE" : "config.authMode",
  );
  const envAuth: XGatewayAuthConfig = {
    token: readEnv("X_GW_TOKEN"),
    consumerKey: readEnv("X_GW_CONSUMER_KEY"),
    consumerSecret: readEnv("X_GW_CONSUMER_SECRET"),
    accessToken: readEnv("X_GW_ACCESS_TOKEN"),
    accessTokenSecret: readEnv("X_GW_ACCESS_TOKEN_SECRET"),
    clientId: readEnv("X_GW_CLIENT_ID"),
    clientSecret: readEnv("X_GW_CLIENT_SECRET"),
  };

  const paramAuth = config.auth ?? {};
  const mergedAuth: XGatewayAuthConfig =
    authMode === "env"
      ? envAuth
      : authMode === "params"
        ? {
            token: paramAuth.token,
            consumerKey: paramAuth.consumerKey,
            consumerSecret: paramAuth.consumerSecret,
            accessToken: paramAuth.accessToken,
            accessTokenSecret: paramAuth.accessTokenSecret,
            clientId: paramAuth.clientId,
            clientSecret: paramAuth.clientSecret,
          }
        : {
            token: paramAuth.token ?? envAuth.token,
            consumerKey: paramAuth.consumerKey ?? envAuth.consumerKey,
            consumerSecret: paramAuth.consumerSecret ?? envAuth.consumerSecret,
            accessToken: paramAuth.accessToken ?? envAuth.accessToken,
            accessTokenSecret:
              paramAuth.accessTokenSecret ?? envAuth.accessTokenSecret,
            clientId: paramAuth.clientId ?? envAuth.clientId,
            clientSecret: paramAuth.clientSecret ?? envAuth.clientSecret,
          };

  const timeoutMs =
    validateOptionalInteger(config.timeoutMs, "config.timeoutMs", 1) ??
    parseIntegerEnv(
      readEnv("X_GW_TIMEOUT_MS"),
      DEFAULT_TIMEOUT_MS,
      "X_GW_TIMEOUT_MS",
      1,
    );
  const retries =
    validateOptionalInteger(config.retry?.retries, "config.retry.retries", 0) ??
    parseIntegerEnv(readEnv("X_GW_RETRY"), DEFAULT_RETRY_COUNT, "X_GW_RETRY", 0);
  const backoff =
    validateRetryBackoff(
      config.retry?.backoff ?? readEnv("X_GW_RETRY_BACKOFF"),
      "exponential-jitter",
      config.retry?.backoff === undefined
        ? "X_GW_RETRY_BACKOFF"
        : "config.retry.backoff",
    );
  const baseDelayMs =
    validateOptionalInteger(config.retry?.baseDelayMs, "config.retry.baseDelayMs", 0) ??
    parseIntegerEnv(
      readEnv("X_GW_RETRY_BASE_MS"),
      DEFAULT_RETRY_BASE_MS,
      "X_GW_RETRY_BASE_MS",
      0,
    );
  const maxDelayMs =
    validateOptionalInteger(config.retry?.maxDelayMs, "config.retry.maxDelayMs", 0) ??
    parseIntegerEnv(
      readEnv("X_GW_RETRY_MAX_MS"),
      DEFAULT_RETRY_MAX_MS,
      "X_GW_RETRY_MAX_MS",
      0,
    );

  const graphqlBaseUrl = validateOptionalGraphqlBaseUrl(
    config.graphqlBaseUrl ?? readEnv("X_GW_GRAPHQL_BASE_URL"),
    config.graphqlBaseUrl !== undefined
      ? "config.graphqlBaseUrl"
      : "X_GW_GRAPHQL_BASE_URL",
  );
  return {
    authMode,
    auth: mergedAuth,
    ...(graphqlBaseUrl === undefined ? {} : { graphqlBaseUrl }),
    timeoutMs,
    retry: {
      retries,
      backoff,
      baseDelayMs,
      maxDelayMs,
    },
    strictCapabilityChecks:
      config.strictCapabilityChecks ??
      parseBoolean(
        readEnv("X_GW_STRICT_CAPABILITY_CHECKS"),
        false,
        "X_GW_STRICT_CAPABILITY_CHECKS",
      ),
  };
}

function hasOauth1(auth: XGatewayAuthConfig): boolean {
  return Boolean(
    auth.consumerKey &&
      auth.consumerSecret &&
      auth.accessToken &&
      auth.accessTokenSecret,
  );
}

function getConfiguredAuthMode(
  auth: XGatewayAuthConfig,
): "bearer" | "oauth1" | undefined {
  if (isNonEmpty(auth.token)) {
    return "bearer";
  }
  if (hasOauth1(auth)) {
    return "oauth1";
  }
  return undefined;
}

function isNonEmpty(value: string | undefined): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function withOptionalTrace(traceId?: string): Readonly<{ traceId?: string }> {
  return traceId === undefined ? {} : { traceId };
}

export class XGatewayError extends Error {
  readonly payload: XGatewayErrorPayload;

  constructor(payload: XGatewayErrorPayload) {
    super(payload.summary);
    this.name = "XGatewayError";
    this.payload = payload;
  }

  toJSON(): Readonly<{ ok: false; error: XGatewayErrorPayload }> {
    return {
      ok: false,
      error: this.payload,
    };
  }
}

function createError(payload: XGatewayErrorPayload): XGatewayError {
  return new XGatewayError(payload);
}

function createValidationError(message: string): XGatewayError {
  return createError({
    code: "VALIDATION_ERROR",
    summary: "Input validation failed",
    details: message,
    likelyCauses: ["Missing required parameter", "Invalid parameter format"],
    remediations: [
      "Inspect required arguments for this command",
      "Pass a valid value and retry",
    ],
    classification: "validation",
    retryable: false,
  });
}

function createUnsupportedError(
  feature: string,
  details: string,
  remediations: readonly string[],
): XGatewayError {
  return createError({
    code: "UNSUPPORTED",
    summary: `${feature} is not supported in current configuration`,
    details,
    likelyCauses: [
      "Endpoint is not available for this API plan/tier",
      "Auth mode cannot satisfy endpoint requirements",
    ],
    remediations,
    classification: "unsupported",
    retryable: false,
  });
}

function deriveAuthErrorCode(detail: string): XGatewayErrorCode {
  const lower = detail.toLowerCase();
  if (lower.includes("expired") || lower.includes("expire")) {
    return "AUTH_EXPIRED";
  }
  if (lower.includes("revoked") || lower.includes("revoke")) {
    return "AUTH_REVOKED";
  }
  return "AUTH_INVALID";
}

function isNetworkFailure(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  const message = error.message.toLowerCase();
  return (
    message.includes("network") ||
    message.includes("fetch") ||
    message.includes("econnreset") ||
    message.includes("enotfound") ||
    message.includes("timed out") ||
    message.includes("timeout")
  );
}

type LegacyApiResponseError = Readonly<{
  code: number;
  message: string;
  data?: Readonly<{
    title?: string;
    detail?: string;
  }>;
}>;

function isLegacyApiResponseError(
  error: unknown,
): error is LegacyApiResponseError {
  if (typeof error !== "object" || error === null) {
    return false;
  }

  const candidate = error as {
    code?: unknown;
    message?: unknown;
    data?: unknown;
  };

  return (
    typeof candidate.code === "number" &&
    typeof candidate.message === "string"
  );
}

function normalizeApiError(
  error: LegacyApiResponseError,
  traceId?: string,
): XGatewayError {
  const status = error.code;
  const title = error.data?.title ?? "X API request failed";
  const detail = error.data?.detail ?? error.message;
  const baseLikely = [
    "API credentials are missing required access",
    "Requested operation is blocked by account/app settings",
  ];
  const baseRemediations = [
    "Verify credential scopes and X app permissions",
    "Review X developer portal app/token status",
  ];

  if (status === 401) {
    const code = deriveAuthErrorCode(detail);
    return createError({
      code,
      summary: "Authentication failed",
      details: `${title}: ${detail}`,
      likelyCauses: [
        "Credential is invalid, expired, or revoked",
        "Token does not match app/user context",
      ],
      remediations: [
        "Re-issue token and retry",
        "Confirm token/app pairing and auth mode",
      ],
      classification: "auth",
      retryable: false,
      httpStatus: status,
      ...withOptionalTrace(traceId),
    });
  }

  if (status === 403) {
    return createError({
      code: "PERMISSION_DENIED",
      summary: "Authorization failed",
      details: `${title}: ${detail}`,
      likelyCauses: [
        "Token lacks required scope for this endpoint",
        "X API plan/tier does not permit this operation",
      ],
      remediations: [
        "Grant required read/write scope",
        "Upgrade plan or use permitted endpoint",
      ],
      classification: "permission",
      retryable: false,
      httpStatus: status,
      ...withOptionalTrace(traceId),
    });
  }

  if (status === 404) {
    return createError({
      code: "RESOURCE_NOT_FOUND",
      summary: "Requested resource was not found",
      details: `${title}: ${detail}`,
      likelyCauses: ["Resource id is invalid", "Resource is deleted or inaccessible"],
      remediations: ["Verify resource identifier", "Check resource visibility"],
      classification: "upstream",
      retryable: false,
      httpStatus: status,
      ...withOptionalTrace(traceId),
    });
  }

  if (status === 409) {
    return createError({
      code: "CONFLICT",
      summary: "Request conflicted with current remote state",
      details: `${title}: ${detail}`,
      likelyCauses: ["Duplicate action", "State changed between requests"],
      remediations: ["Fetch latest state and retry once", "Use idempotency key"],
      classification: "upstream",
      retryable: false,
      httpStatus: status,
      ...withOptionalTrace(traceId),
    });
  }

  if (status === 429) {
    return createError({
      code: "RATE_LIMITED",
      summary: "Rate limit exceeded",
      details: `${title}: ${detail}`,
      likelyCauses: ["Too many requests in current window", "Quota exhausted"],
      remediations: [
        "Retry after wait window",
        "Lower request frequency or batch calls",
      ],
      classification: "rate_limit",
      retryable: true,
      httpStatus: status,
      ...withOptionalTrace(traceId),
    });
  }

  if (status >= 500 && status <= 599) {
    return createError({
      code: "UPSTREAM_FAILURE",
      summary: "X API service failure",
      details: `${title}: ${detail}`,
      likelyCauses: ["Temporary X API outage", "Transient upstream failure"],
      remediations: [
        "Retry with backoff",
        "If persistent, inspect X API status and logs",
      ],
      classification: "upstream",
      retryable: true,
      httpStatus: status,
      ...withOptionalTrace(traceId),
    });
  }

  return createError({
    code: "UPSTREAM_FAILURE",
    summary: "X API returned an error",
    details: `${title}: ${detail}`,
    likelyCauses: baseLikely,
    remediations: baseRemediations,
    classification: "upstream",
    retryable: false,
    httpStatus: status,
    ...withOptionalTrace(traceId),
  });
}

export function normalizeError(error: unknown, traceId?: string): XGatewayError {
  if (error instanceof XGatewayError) {
    return error;
  }
  if (isLegacyApiResponseError(error)) {
    return normalizeApiError(error, traceId);
  }
  if (isNetworkFailure(error)) {
    const detail = error instanceof Error ? error.message : "Network failure";
    return createError({
      code: "NETWORK_FAILURE",
      summary: "Network request failed",
      details: detail,
      likelyCauses: [
        "DNS or connection issue",
        "Temporary connectivity loss",
        "Timeout while calling X API",
      ],
      remediations: [
        "Retry with backoff",
        "Check network connectivity and DNS",
        "Increase timeout if the network is slow",
      ],
      classification: "network",
      retryable: true,
      ...withOptionalTrace(traceId),
    });
  }

  if (error instanceof Error) {
    return createError({
      code: "INTERNAL_ERROR",
      summary: "Unexpected internal error",
      details: error.message,
      likelyCauses: ["Unhandled runtime failure"],
      remediations: ["Inspect stack trace and input payload", "Retry after validation"],
      classification: "internal",
      retryable: false,
      ...withOptionalTrace(traceId),
    });
  }

  return createError({
    code: "INTERNAL_ERROR",
    summary: "Unknown internal error",
    details: "An unknown non-Error failure occurred",
    likelyCauses: ["Unhandled non-standard failure object"],
    remediations: ["Enable trace logging and retry"],
    classification: "internal",
    retryable: false,
    ...withOptionalTrace(traceId),
  });
}

export function computeBackoffDelayMs(
  attempt: number,
  strategy: RetryBackoffStrategy,
  baseDelayMs: number,
  maxDelayMs: number,
  randomValue = Math.random(),
): number {
  if (strategy === "none") {
    return 0;
  }
  if (strategy === "fixed") {
    return Math.min(baseDelayMs, maxDelayMs);
  }
  const exponential = Math.min(baseDelayMs * 2 ** attempt, maxDelayMs);
  const jitter = Math.floor(randomValue * baseDelayMs);
  return Math.min(exponential + jitter, maxDelayMs);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeoutPromise = new Promise<T>((_resolve, reject) => {
      timer = setTimeout(() => {
        reject(new Error(`Request timed out after ${timeoutMs}ms`));
      }, timeoutMs);
    });
    return await Promise.race([promise, timeoutPromise]);
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}

export type XGatewayRequestOptions = Readonly<{
  operationName: string;
  operationType?: XGatewayOperationType;
  documentId?: string;
  query?: string;
  variables?: Readonly<Record<string, unknown>>;
  features?: Readonly<Record<string, unknown>>;
  fieldToggles?: Readonly<Record<string, unknown>>;
  traceId?: string;
}>;

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

export type CapabilityStatus =
  | "implemented"
  | "planned"
  | "blocked_by_scope"
  | "blocked_by_plan"
  | "unsupported";

export type CapabilityDescriptor = Readonly<{
  id: string;
  endpointFamily: string;
  operation: string;
  status: CapabilityStatus;
  authModes: readonly ("bearer" | "oauth1")[];
  notes: string;
}>;

export type XGatewayClient = Readonly<{
  getResolvedConfig: () => XGatewayResolvedConfig;
  request: <T>(options: XGatewayRequestOptions) => Promise<T>;
  authVerify: () => Promise<unknown>;
  authScopes: () => Promise<Readonly<{ authMode: string; notes: readonly string[] }>>;
  capabilitiesList: () => readonly CapabilityDescriptor[];
  capabilitiesGet: (id: string) => CapabilityDescriptor;
}>;

export type CommandError = Readonly<{ exitCode: number; error: XGatewayError }>;

function mapErrorToExitCode(error: XGatewayError): number {
  switch (error.payload.code) {
    case "VALIDATION_ERROR":
      return 2;
    case "AUTH_MISSING":
      return 3;
    case "AUTH_INVALID":
    case "AUTH_EXPIRED":
    case "AUTH_REVOKED":
      return 4;
    case "PERMISSION_DENIED":
      return 5;
    case "RESOURCE_NOT_FOUND":
      return 6;
    case "CONFLICT":
      return 7;
    case "RATE_LIMITED":
      return 8;
    case "UPSTREAM_FAILURE":
    case "NETWORK_FAILURE":
      return 9;
    case "UNSUPPORTED":
    case "INTERNAL_ERROR":
      return 10;
    default: {
      const _unreachable: never = error.payload.code;
      return _unreachable;
    }
  }
}

export function toCommandError(error: unknown, traceId?: string): CommandError {
  const normalized = normalizeError(error, traceId);
  return {
    exitCode: mapErrorToExitCode(normalized),
    error: normalized,
  };
}

function ensureRequired(value: string | undefined, fieldName: string): string {
  if (!isNonEmpty(value)) {
    throw createValidationError(`${fieldName} is required.`);
  }
  return value;
}

function encodeGraphqlOperationName(operationName: string): string {
  return encodeURIComponent(operationName);
}

function joinGraphqlEndpoint(baseUrl: string, documentId: string, operationName: string): string {
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

export function createXGatewayClient(config: XGatewayConfig = {}): XGatewayClient {
  const resolved = resolveConfig(config);
  const graphQlBaseUrl = resolved.graphqlBaseUrl ?? DEFAULT_GRAPHQL_BASE_URL;

  function getGraphqlBearerToken(): string {
    const configuredAuthMode = getConfiguredAuthMode(resolved.auth);
    if (configuredAuthMode === "bearer" && isNonEmpty(resolved.auth.token)) {
      return resolved.auth.token;
    }
    if (configuredAuthMode === "oauth1") {
      throw createUnsupportedError(
        "GraphQL transport authentication",
        "GraphQL-only mode currently supports bearer-token authentication only. OAuth1 credentials cannot be translated automatically.",
        [
          "Set X_GW_TOKEN or pass auth.token when creating the client.",
          "Add an explicit GraphQL auth adapter before enabling OAuth1-only callers.",
        ],
      );
    }
    throw createError({
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

  async function executeWithRetry<T>(
    operation: () => Promise<T>,
    traceId?: string,
  ): Promise<T> {
    const startedAt = Date.now();
    let lastError: XGatewayError | undefined;

    for (let attempt = 0; attempt <= resolved.retry.retries; attempt += 1) {
      try {
        return await withTimeout(operation(), resolved.timeoutMs);
      } catch (error) {
        const normalized = normalizeError(error, traceId);
        lastError = normalized;
        const canRetry = normalized.payload.retryable;
        if (!canRetry || attempt >= resolved.retry.retries) {
          const retryContext = `Retry policy exhausted after ${attempt + 1} attempt(s) using ${resolved.retry.backoff} backoff.`;
          throw createError({
            ...normalized.payload,
            details: `${normalized.payload.details} ${retryContext}`,
            attempts: attempt + 1,
            elapsedMs: Date.now() - startedAt,
          });
        }

        const delayMs =
          normalized.payload.retryAfterMs ??
          computeBackoffDelayMs(
            attempt,
            resolved.retry.backoff,
            resolved.retry.baseDelayMs,
            resolved.retry.maxDelayMs,
          );

        if (delayMs > 0) {
          await sleep(delayMs);
        }
      }
    }

    throw (
      lastError ??
      createError({
        code: "INTERNAL_ERROR",
        summary: "Unexpected retry state",
        details: "Retry loop exited without success or captured error",
        likelyCauses: ["Internal control-flow defect"],
        remediations: ["Inspect retry implementation"],
        classification: "internal",
        retryable: false,
        ...withOptionalTrace(traceId),
      })
    );
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
    const safeOperationType = validateOperationType(operationType);
    const hasDocumentId = isNonEmpty(documentId);
    const hasQuery = isNonEmpty(query);
    if (!hasDocumentId && !hasQuery) {
      throw createValidationError(
        "GraphQL request requires either documentId for persisted queries or query for an inline GraphQL document.",
      );
    }
    if (hasDocumentId && hasQuery) {
      throw createValidationError(
        "GraphQL request must include exactly one request source: either documentId or query, but not both.",
      );
    }

    const token = getGraphqlBearerToken();
    return executeWithRetry(async () => {
      const endpoint = hasDocumentId
        ? joinGraphqlEndpoint(graphQlBaseUrl, documentId, safeOperationName)
        : graphQlBaseUrl;
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
        const retryAfterMs = parseRetryAfterMs(response.headers.get("retry-after"));
        const detail =
          typeof payload === "object" && payload !== null
            ? JSON.stringify(payload)
            : String(payload);
        throw createError({
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
                      : response.status >= 500
                        ? "UPSTREAM_FAILURE"
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
          ...withOptionalTrace(traceId),
        });
      }

      if (
        typeof payload === "object" &&
        payload !== null &&
        "errors" in payload &&
        Array.isArray((payload as { errors?: unknown }).errors) &&
        ((payload as { errors?: readonly unknown[] }).errors?.length ?? 0) > 0
      ) {
        throw createError({
          code: "UPSTREAM_FAILURE",
          summary: "GraphQL response included errors",
          details: JSON.stringify((payload as { errors: readonly unknown[] }).errors),
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
          ...withOptionalTrace(traceId),
        });
      }

      return payload as T;
    }, traceId);
  }

  function capabilitiesList(): readonly CapabilityDescriptor[] {
    return CAPABILITY_REGISTRY;
  }

  function capabilitiesGet(id: string): CapabilityDescriptor {
    const safeId = ensureRequired(id, "id");
    const found = CAPABILITY_REGISTRY.find((entry) => entry.id === safeId);
    if (!found) {
      throw createError({
        code: "RESOURCE_NOT_FOUND",
        summary: "Capability id not found",
        details: `No capability entry exists for '${safeId}'.`,
        likelyCauses: [
          "Capability id is misspelled",
          "Capability has not been registered yet",
        ],
        remediations: [
          "Run capabilities list and choose a listed id.",
          "Add registry entry if this is a new capability.",
        ],
        classification: "upstream",
        retryable: false,
      });
    }
    return found;
  }

  async function authVerify(): Promise<unknown> {
    const configuredAuthMode = getConfiguredAuthMode(resolved.auth);
    return {
      ready: configuredAuthMode === "bearer",
      verifiedAt: new Date().toISOString(),
      authMode: configuredAuthMode ?? "unconfigured",
      transport: "graphql-only",
      message:
        configuredAuthMode === "bearer"
          ? "Bearer token is configured. Use graphql request or client.request(...) with a concrete GraphQL operation to perform a live verification."
          : configuredAuthMode === "oauth1"
            ? "OAuth1 credentials are configured, but GraphQL-only transport currently requires bearer auth."
            : "No GraphQL-capable bearer token is configured.",
    };
  }

  async function authScopes(): Promise<Readonly<{ authMode: string; notes: readonly string[] }>> {
    const authMode = getConfiguredAuthMode(resolved.auth) ?? "unconfigured";
    return {
      authMode,
      notes: [
        "Scope introspection endpoint availability differs by auth mode and X plan.",
        "Use permission-denied errors from concrete operations as authoritative diagnostics.",
        `Configured auth resolution mode: ${resolved.authMode}.`,
        "GraphQL-only transport currently requires bearer auth for live requests.",
      ],
    };
  }

  return {
    getResolvedConfig: () => resolved,
    request,
    authVerify,
    authScopes,
    capabilitiesList,
    capabilitiesGet,
  };
}
