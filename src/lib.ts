import {
  CAPABILITY_PLANNING_REGISTRY,
  CAPABILITY_REGISTRY,
  isStableCapabilityId,
  type CapabilityDescriptor,
  type CapabilityPlanningDefinition,
  type StableCapabilityId,
} from "./capability-metadata";
import {
  buildAuthCapabilityReadiness,
  type CapabilityExecutionContext,
  type ResolvedCapabilityAuth,
  type XGatewayCapabilityReadiness,
} from "./capability-runtime";
import { createCapabilityAdapterFactories } from "./capability-adapters";
import { inferPublicGraphqlOperationType } from "./public-graphql-parser";
import {
  createPublicApiRequestPlan,
  projectPublicSelection,
} from "./public-api-contract";
import {
  createStableCapabilityExecutor,
  type StableCapabilityInputById,
} from "./stable-capability-executor";
import { createRawGraphqlRequester } from "./raw-graphql-client";

export type {
  CapabilityDescriptor,
  CapabilitySurfaceCategory,
  CapabilityStatus,
  CapabilityTransportStrategy,
  StableCapabilityId,
  XGatewayCapabilityAccessType,
  XGatewayCapabilityReadinessStatus,
  XGatewayCapabilityRequirement,
} from "./capability-metadata";
export type { XGatewayCapabilityReadiness } from "./capability-runtime";

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
export type XGatewayConfigMode = "env" | "params" | "mixed";
export type XGatewayAuthMode = XGatewayConfigMode;
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
  configMode?: XGatewayConfigMode | undefined;
  authMode?: XGatewayAuthMode | undefined;
  auth?: XGatewayAuthConfig | undefined;
  graphqlBaseUrl?: string | undefined;
  timeoutMs?: number | undefined;
  retry?: XGatewayRetryConfig | undefined;
  strictCapabilityChecks?: boolean | undefined;
}>;

export type XGatewayResolvedConfig = Readonly<{
  configMode: XGatewayConfigMode;
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
  if (input === "exponential-jitter" || input === "fixed" || input === "none") {
    return input;
  }
  throw createValidationError(
    `${name} must be one of 'exponential-jitter', 'fixed', or 'none'.`,
  );
}

function validateConfigMode(
  input: string | undefined,
  fallback: XGatewayConfigMode,
  name: string,
): XGatewayConfigMode {
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

function readConfigModeEnv(): string | undefined {
  const explicitConfigMode = readEnv("X_GW_CONFIG_MODE");
  if (explicitConfigMode !== undefined) {
    return explicitConfigMode;
  }

  const legacyAuthMode = readEnv("X_GW_AUTH_MODE");
  if (legacyAuthMode === undefined) {
    return undefined;
  }
  if (
    legacyAuthMode === "env" ||
    legacyAuthMode === "params" ||
    legacyAuthMode === "mixed"
  ) {
    return legacyAuthMode;
  }
  if (legacyAuthMode === "oauth1" || legacyAuthMode === "bearer") {
    return undefined;
  }
  throw createValidationError(
    "X_GW_AUTH_MODE must be one of 'oauth1', 'bearer', 'env', 'params', or 'mixed'. Use X_GW_CONFIG_MODE for env/params/mixed config resolution.",
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
  throw createValidationError(
    `${name} must be a boolean value ('true' or 'false').`,
  );
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

export function resolveConfig(
  config: XGatewayConfig = {},
): XGatewayResolvedConfig {
  const configMode = validateConfigMode(
    config.configMode ?? config.authMode ?? readConfigModeEnv(),
    "mixed",
    config.configMode !== undefined
      ? "config.configMode"
      : config.authMode !== undefined
        ? "config.authMode"
        : "X_GW_CONFIG_MODE",
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
    configMode === "env"
      ? envAuth
      : configMode === "params"
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
    parseIntegerEnv(
      readEnv("X_GW_RETRY"),
      DEFAULT_RETRY_COUNT,
      "X_GW_RETRY",
      0,
    );
  const backoff = validateRetryBackoff(
    config.retry?.backoff ?? readEnv("X_GW_RETRY_BACKOFF"),
    "exponential-jitter",
    config.retry?.backoff === undefined
      ? "X_GW_RETRY_BACKOFF"
      : "config.retry.backoff",
  );
  const baseDelayMs =
    validateOptionalInteger(
      config.retry?.baseDelayMs,
      "config.retry.baseDelayMs",
      0,
    ) ??
    parseIntegerEnv(
      readEnv("X_GW_RETRY_BASE_MS"),
      DEFAULT_RETRY_BASE_MS,
      "X_GW_RETRY_BASE_MS",
      0,
    );
  const maxDelayMs =
    validateOptionalInteger(
      config.retry?.maxDelayMs,
      "config.retry.maxDelayMs",
      0,
    ) ??
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
    configMode,
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

function hasBearerToken(auth: XGatewayAuthConfig): boolean {
  return isNonEmpty(auth.token);
}

function getAvailableAuthModes(
  auth: XGatewayAuthConfig,
): readonly ("oauth1" | "bearer")[] {
  const modes: ("oauth1" | "bearer")[] = [];
  if (hasOauth1(auth)) {
    modes.push("oauth1");
  }
  if (hasBearerToken(auth)) {
    modes.push("bearer");
  }
  return modes;
}

function createResolvedCapabilityAuth(
  auth: XGatewayAuthConfig,
): ResolvedCapabilityAuth {
  return {
    hasOauth1: hasOauth1(auth),
    hasBearerToken: hasBearerToken(auth),
    availableAuthModes: getAvailableAuthModes(auth),
  };
}

function getConfiguredAuthMode(
  auth: XGatewayAuthConfig,
): "bearer" | "oauth1" | undefined {
  if (hasBearerToken(auth)) {
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

function createStablePayloadShapeError(
  fieldName: string,
  detail: string,
): XGatewayError {
  return createError({
    code: "UPSTREAM_FAILURE",
    summary: `Stable capability '${fieldName}' returned an unexpected payload`,
    details: `The reviewed adapter for '${fieldName}' returned a payload that does not match the stable contract. ${detail}`,
    likelyCauses: [
      "The upstream adapter returned a different response shape than expected",
      "The normalization layer is out of sync with the selected transport",
    ],
    remediations: [
      "Inspect the adapter response and update the project-owned response mapper.",
    ],
    classification: "upstream",
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
    typeof candidate.code === "number" && typeof candidate.message === "string"
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
      likelyCauses: [
        "Resource id is invalid",
        "Resource is deleted or inaccessible",
      ],
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
      remediations: [
        "Fetch latest state and retry once",
        "Use idempotency key",
      ],
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

export function normalizeError(
  error: unknown,
  traceId?: string,
): XGatewayError {
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
      remediations: [
        "Inspect stack trace and input payload",
        "Retry after validation",
      ],
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

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
): Promise<T> {
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

export type XGatewayAccountProfile = Readonly<{
  id: string;
  username: string;
  name: string;
}>;

export type XGatewayPostAttachmentKind = "image";

export type XGatewayPostAttachmentInput = Readonly<{
  kind: XGatewayPostAttachmentKind;
  filePath: string;
  altText?: string;
}>;

export type XGatewayPostCreateOptions = Readonly<{
  text: string;
  attachments?: readonly XGatewayPostAttachmentInput[];
}>;

export type XGatewayPostGetOptions = Readonly<{
  postId: string;
}>;

export type XGatewayPostReplyOptions = Readonly<{
  text: string;
  replyToPostId: string;
  attachments?: readonly XGatewayPostAttachmentInput[];
}>;

export type XGatewayPostDeleteOptions = Readonly<{
  postId: string;
}>;

export type XGatewayPostSummary = Readonly<{
  id: string;
  text: string;
  author?: XGatewayAccountProfile;
  createdAt?: string;
  conversationId?: string;
  replyToUserId?: string;
}>;

export type XGatewayPostReferenceRelation =
  | "replied_to"
  | "quoted"
  | "retweeted";

export type XGatewayReferencedPost = Readonly<
  XGatewayPostSummary & {
    relation: XGatewayPostReferenceRelation;
  }
>;

export type XGatewayPostLookupResult = Readonly<{
  post: XGatewayPostSummary;
  referencedPosts: readonly XGatewayReferencedPost[];
}>;

export type XGatewayPageInfo = Readonly<{
  resultCount: number;
  nextToken?: string;
  previousToken?: string;
  newestId?: string;
  oldestId?: string;
}>;

export type XGatewayPostPage = Readonly<{
  posts: readonly XGatewayPostSummary[];
  pageInfo: XGatewayPageInfo;
}>;

export type XGatewayTimelinePageOptions = Readonly<{
  maxResults?: number;
  paginationToken?: string;
}>;

export type XGatewayTimelineSearchOptions = Readonly<
  XGatewayTimelinePageOptions & {
    query: string;
  }
>;

export type XGatewayTimelineUserOptions = Readonly<
  XGatewayTimelinePageOptions & {
    userId: string;
  }
>;

export type XGatewayPostQuoteOptions = Readonly<{
  text: string;
  quotedPostId: string;
  attachments?: readonly XGatewayPostAttachmentInput[];
}>;

export type XGatewayPostRepostOptions = Readonly<{
  postId: string;
}>;

export type XGatewayAuthVerifyResult = Readonly<{
  ready: boolean;
  verifiedAt: string;
  authMode: string;
  availableAuthModes: readonly ("oauth1" | "bearer")[];
  transport: "hybrid";
  message: string;
  capabilities: readonly XGatewayCapabilityReadiness[];
}>;

export type XGatewayApiRequestOptions = Readonly<{
  query: string;
  traceId?: string;
}>;

export type XGatewayClient = Readonly<{
  getResolvedConfig: () => XGatewayResolvedConfig;
  request: <T>(options: XGatewayRequestOptions) => Promise<T>;
  apiRequest: (
    options: XGatewayApiRequestOptions,
  ) => Promise<Readonly<{ data: Readonly<Record<string, unknown>> }>>;
  authVerify: () => Promise<XGatewayAuthVerifyResult>;
  authScopes: () => Promise<
    Readonly<{ authMode: string; notes: readonly string[] }>
  >;
  accountMe: () => Promise<XGatewayAccountProfile>;
  postGet: (
    options: XGatewayPostGetOptions,
  ) => Promise<XGatewayPostLookupResult>;
  timelineSearch: (
    options: XGatewayTimelineSearchOptions,
  ) => Promise<XGatewayPostPage>;
  timelineHome: (
    options?: XGatewayTimelinePageOptions,
  ) => Promise<XGatewayPostPage>;
  timelineUser: (
    options: XGatewayTimelineUserOptions,
  ) => Promise<XGatewayPostPage>;
  timelineMentions: (
    options: XGatewayTimelineUserOptions,
  ) => Promise<XGatewayPostPage>;
  postCreate: (options: XGatewayPostCreateOptions) => Promise<unknown>;
  postDelete: (options: XGatewayPostDeleteOptions) => Promise<unknown>;
  postReply: (options: XGatewayPostReplyOptions) => Promise<unknown>;
  postQuote: (options: XGatewayPostQuoteOptions) => Promise<unknown>;
  postRepost: (options: XGatewayPostRepostOptions) => Promise<unknown>;
  postUndoRepost: (options: XGatewayPostRepostOptions) => Promise<unknown>;
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

export function inferApiRequestOperationType(
  query: string,
): XGatewayOperationType {
  return inferPublicGraphqlOperationType(query, createValidationError);
}

function dedupeStrings(items: readonly string[]): readonly string[] {
  return [...new Set(items)];
}

export function createXGatewayClient(
  config: XGatewayConfig = {},
): XGatewayClient {
  const resolved = resolveConfig(config);
  const resolvedCapabilityAuth = createResolvedCapabilityAuth(resolved.auth);
  const graphQlBaseUrl = resolved.graphqlBaseUrl ?? DEFAULT_GRAPHQL_BASE_URL;
  const capabilityAdapterFactories = createCapabilityAdapterFactories({
    auth: resolved.auth,
    createError,
    createValidationError,
    ensureRequired,
  });

  function createCapabilityAuthMissingError(
    capability: CapabilityDescriptor,
    planning: CapabilityPlanningDefinition,
  ): XGatewayError {
    const remediations =
      planning.missingAuthRequirement === "oauth1"
        ? [
            "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET for OAuth1 usage.",
          ]
        : planning.missingAuthRequirement === "bearer"
          ? ["Set X_GW_TOKEN for bearer-token usage."]
          : planning.missingAuthRequirement === "user-context-bearer"
            ? [
                "Set X_GW_TOKEN with a reviewed user-context bearer token for this capability.",
              ]
            : [
                "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET for OAuth1 usage.",
                "Or set X_GW_TOKEN for bearer-token usage where supported.",
              ];

    return createError({
      code: "AUTH_MISSING",
      summary: "Authentication configuration missing",
      details: `${capability.operation} is unavailable. ${planning.missingAuthReason}`,
      likelyCauses: [
        "No supported credentials were configured",
        "Credential values were empty after environment resolution",
      ],
      remediations,
      classification: "auth",
      retryable: false,
    });
  }

  function normalizeCapabilityError(
    error: unknown,
    context: CapabilityExecutionContext,
  ): XGatewayError {
    const normalized = normalizeError(error, context.traceId);
    const capabilityPrefix = `${context.capabilityLabel} via ${context.transportLabel}`;
    const extraCause = `Capability '${context.capabilityId}' failed on the ${context.transportLabel} adapter.`;
    const extraRemediations =
      normalized.payload.code === "AUTH_MISSING"
        ? [
            "Configure credentials supported by this capability before retrying.",
            "Use 'auth verify' to inspect the resolved auth mode and transport readiness.",
          ]
        : normalized.payload.code === "PERMISSION_DENIED"
          ? [
              "Confirm the configured app/user credential has permission for this capability.",
            ]
          : normalized.payload.code === "AUTH_INVALID" ||
              normalized.payload.code === "AUTH_EXPIRED" ||
              normalized.payload.code === "AUTH_REVOKED"
            ? [
                "Refresh or replace the configured credential, then retry the same capability.",
              ]
            : normalized.payload.code === "RATE_LIMITED"
              ? [
                  "Delay retries for this capability until the rate-limit window resets.",
                ]
              : normalized.payload.code === "NETWORK_FAILURE"
                ? [
                    "Retry the same capability after confirming connectivity to the selected upstream transport.",
                  ]
                : normalized.payload.code === "UPSTREAM_FAILURE"
                  ? [
                      "Inspect the selected transport and adapter mapping for this capability before retrying.",
                    ]
                  : [];

    return createError({
      ...normalized.payload,
      summary: `${context.capabilityLabel} failed`,
      details: `${capabilityPrefix} failed. ${normalized.payload.details}`,
      likelyCauses: dedupeStrings([
        extraCause,
        ...normalized.payload.likelyCauses,
      ]),
      remediations: dedupeStrings([
        ...normalized.payload.remediations,
        ...extraRemediations,
      ]),
    });
  }

  async function executeCapabilityOperation<T>(
    context: CapabilityExecutionContext,
    operation: () => Promise<T>,
  ): Promise<T> {
    return executeWithRetry(async () => {
      try {
        return await operation();
      } catch (error) {
        throw normalizeCapabilityError(error, context);
      }
    }, context.traceId);
  }

  function getCapabilityDescriptorById(
    capabilityId: string,
  ): CapabilityDescriptor {
    const capability = CAPABILITY_REGISTRY.find(
      (entry) => entry.id === capabilityId,
    );
    if (!capability) {
      throw createError({
        code: "INTERNAL_ERROR",
        summary: "Capability registry entry missing",
        details: `Capability '${capabilityId}' was requested internally, but no registry entry exists for it.`,
        likelyCauses: [
          "The execution planner references an unregistered capability id",
        ],
        remediations: [
          "Add the missing capability registry row before routing requests to this capability.",
        ],
        classification: "internal",
        retryable: false,
      });
    }
    return capability;
  }

  function createConfiguredAuthUnsupportedError(
    capabilityLabel: string,
    planning: CapabilityPlanningDefinition,
  ): XGatewayError {
    return createUnsupportedError(
      capabilityLabel,
      planning.unsupportedConfiguredAuthReason ??
        `${capabilityLabel} does not support the configured credential family in the current reviewed adapter set.`,
      planning.unsupportedConfiguredAuthRemediations ?? [
        "Configure credentials supported by this capability before retrying.",
      ],
    );
  }

  const stableCapabilityExecutor = createStableCapabilityExecutor({
    auth: resolvedCapabilityAuth,
    withOptionalTrace,
    executeCapabilityOperation,
    adapters: capabilityAdapterFactories,
    errors: {
      createCapabilityRegistryMissingError: (missingCapabilityId: string) =>
        createError({
          code: "INTERNAL_ERROR",
          summary: "Capability registry entry missing",
          details: `Capability '${missingCapabilityId}' was requested internally, but no registry entry exists for it.`,
          likelyCauses: [
            "The execution planner references an unregistered capability id",
          ],
          remediations: [
            "Add the missing capability registry row before routing requests to this capability.",
          ],
          classification: "internal",
          retryable: false,
        }),
      createCapabilityPlanningMissingError: (missingCapabilityId: string) =>
        createError({
          code: "INTERNAL_ERROR",
          summary: "Capability planning registry entry missing",
          details: `Capability '${missingCapabilityId}' was requested internally, but no planning metadata exists for it.`,
          likelyCauses: [
            "The execution planner references an unregistered planning definition",
          ],
          remediations: [
            "Add the missing capability planning row before routing requests to this capability.",
          ],
          classification: "internal",
          retryable: false,
        }),
      createConfiguredAuthUnsupportedError,
      createCapabilityAuthMissingError,
      createHandlerMissingError: (
        missingCapabilityId: StableCapabilityId,
        adapterKind: "read-capability" | "stable-posting",
      ) =>
        createError({
          code: "INTERNAL_ERROR",
          summary:
            adapterKind === "read-capability"
              ? "Read capability handler missing"
              : "Stable posting handler missing",
          details:
            adapterKind === "read-capability"
              ? `Capability '${missingCapabilityId}' selected a read adapter route, but no read handler was provided.`
              : `Capability '${missingCapabilityId}' selected a stable-posting route, but no posting handler was provided.`,
          likelyCauses: [
            "The planner routing metadata and execution callback are out of sync",
          ],
          remediations: [
            adapterKind === "read-capability"
              ? "Provide a read handler for this capability before advertising the route."
              : "Provide a stable posting handler for this capability before advertising the route.",
          ],
          classification: "internal",
          retryable: false,
        }),
      createUnsupportedAdapterKindError: (
        invalidCapabilityId: StableCapabilityId,
        adapterKind: "graphql-request" | "read-capability" | "stable-posting",
      ) =>
        createError({
          code: "INTERNAL_ERROR",
          summary: "Unsupported capability route adapter kind",
          details: `Capability '${invalidCapabilityId}' selected adapter kind '${adapterKind}', which is not valid for the stable capability planner.`,
          likelyCauses: [
            "A raw GraphQL-only route was incorrectly wired into the stable capability planner",
          ],
          remediations: [
            "Restrict the stable capability planner to reviewed read/stable-posting adapter kinds.",
          ],
          classification: "internal",
          retryable: false,
        }),
    },
  });

  async function executeStableCapability<K extends StableCapabilityId>(
    capabilityId: K,
    input: StableCapabilityInputById[K],
    traceId?: string,
  ) {
    return stableCapabilityExecutor.executeStableCapability(
      capabilityId,
      input,
      traceId,
    );
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

  const rawGraphqlRequester = createRawGraphqlRequester({
    auth: resolved.auth,
    configuredAuthMode: getConfiguredAuthMode(resolved.auth),
    graphqlBaseUrl: graphQlBaseUrl,
    executeWithRetry,
    createError,
    createValidationError,
    createUnsupportedError: (subject, details, remediations) =>
      createUnsupportedError(subject, details, remediations ?? []),
    withOptionalTrace,
  });

  async function apiRequest(
    options: XGatewayApiRequestOptions,
  ): Promise<Readonly<{ data: Readonly<Record<string, unknown>> }>> {
    const publicRequest = createPublicApiRequestPlan(
      options,
      createValidationError,
      createStablePayloadShapeError,
    );
    const capability = getCapabilityDescriptorById(publicRequest.capabilityId);

    if (capability.status !== "implemented") {
      throw createUnsupportedError(
        `Public GraphQL field '${publicRequest.fieldName}'`,
        `Field '${publicRequest.fieldName}' maps to capability '${capability.id}', but that capability is currently ${capability.status}.`,
        [
          "Keep using 'api request' only for reviewed project-owned GraphQL fields in the stable contract.",
          "Use a reviewed stable convenience command only if you need a temporary transition wrapper for the same capability.",
          "Use 'graphql request' only as a low-level escape hatch for explicit upstream GraphQL workflows until the capability adapter is implemented.",
        ],
      );
    }

    if (!isStableCapabilityId(capability.id)) {
      throw createUnsupportedError(
        `Public GraphQL field '${publicRequest.fieldName}'`,
        `Capability '${capability.id}' is not part of the stable capability executor registry.`,
        [
          "Use a reviewed stable CLI/SDK capability if one already exists.",
          "Or implement the missing stable capability executor before advertising this field.",
        ],
      );
    }

    const normalizedResult = publicRequest.normalizeResult(
      await executeStableCapability(
        capability.id,
        publicRequest.buildCapabilityInput(
          publicRequest.arguments,
        ) as StableCapabilityInputById[typeof capability.id],
        publicRequest.traceId,
      ),
      publicRequest.fieldName,
    );
    return {
      data: {
        [publicRequest.fieldName]: projectPublicSelection(
          normalizedResult,
          publicRequest.selections,
          publicRequest.fieldName,
          publicRequest.selectionSchema,
          createStablePayloadShapeError,
        ),
      },
    };
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

  async function authVerify(): Promise<XGatewayAuthVerifyResult> {
    const availableAuthModes = resolvedCapabilityAuth.availableAuthModes;
    const configuredAuthMode = getConfiguredAuthMode(resolved.auth);
    const capabilities = buildAuthCapabilityReadiness(
      CAPABILITY_PLANNING_REGISTRY,
      resolvedCapabilityAuth,
    );
    return {
      ready: configuredAuthMode !== undefined,
      verifiedAt: new Date().toISOString(),
      authMode: configuredAuthMode ?? "unconfigured",
      availableAuthModes,
      transport: "hybrid",
      capabilities,
      message:
        availableAuthModes.length === 2
          ? "Bearer and OAuth1 credentials are both configured. Raw GraphQL requests use bearer auth, while stable posting helpers prefer OAuth1 and stable read helpers can use either reviewed path."
          : configuredAuthMode === "bearer"
            ? "Bearer token is configured. GraphQL requests can run directly, stable post lookup can use the public read API, and account/profile reads may work if the token has user context. Stable posting mutations currently require OAuth1 credentials."
            : configuredAuthMode === "oauth1"
              ? "OAuth1 credentials are configured. REST compatibility commands such as account/profile reads, post lookup, and stable posting mutations can run, but raw GraphQL requests still require bearer auth."
              : "No supported credentials are configured.",
    };
  }

  async function authScopes(): Promise<
    Readonly<{ authMode: string; notes: readonly string[] }>
  > {
    const authMode = getConfiguredAuthMode(resolved.auth) ?? "unconfigured";
    const availableAuthModes = resolvedCapabilityAuth.availableAuthModes;
    return {
      authMode,
      notes: [
        "Scope introspection endpoint availability differs by auth mode and X plan.",
        "Use permission-denied errors from concrete operations as authoritative diagnostics.",
        `Configured auth resolution mode: ${resolved.configMode}.`,
        `Available credential families: ${availableAuthModes.length > 0 ? availableAuthModes.join(", ") : "none"}.`,
        "Raw GraphQL requests currently require bearer auth for live requests.",
        "Account/profile reads can use OAuth1 or a user-context bearer token where the upstream endpoint supports them.",
        "Stable post lookup prefers OAuth1 when both OAuth1 and bearer credentials are present, and otherwise falls back to bearer-token reads through the public REST API.",
        "Liked-post lookup is currently deferred from the stable CLI, SDK, and project-owned GraphQL contract because the previously attempted live adapter route is not yet verified.",
        "Stable posting helpers (create/delete/reply/quote/repost/unrepost) prefer OAuth1 whenever it is configured and otherwise remain unavailable to bearer-only environments.",
      ],
    };
  }

  async function accountMe(): Promise<XGatewayAccountProfile> {
    return executeStableCapability("account.me", undefined);
  }

  async function postGet(
    options: XGatewayPostGetOptions,
  ): Promise<XGatewayPostLookupResult> {
    return executeStableCapability("post.get", options);
  }

  async function timelineSearch(
    options: XGatewayTimelineSearchOptions,
  ): Promise<XGatewayPostPage> {
    return executeStableCapability("timeline.search", options);
  }

  async function timelineHome(
    options: XGatewayTimelinePageOptions = {},
  ): Promise<XGatewayPostPage> {
    return executeStableCapability("timeline.home", options);
  }

  async function timelineUser(
    options: XGatewayTimelineUserOptions,
  ): Promise<XGatewayPostPage> {
    return executeStableCapability("timeline.user", options);
  }

  async function timelineMentions(
    options: XGatewayTimelineUserOptions,
  ): Promise<XGatewayPostPage> {
    return executeStableCapability("timeline.mentions", options);
  }

  async function postCreate(
    options: XGatewayPostCreateOptions,
  ): Promise<unknown> {
    return executeStableCapability("post.create", options);
  }

  async function postDelete(
    options: XGatewayPostDeleteOptions,
  ): Promise<unknown> {
    return executeStableCapability("post.delete", options);
  }

  async function postReply(
    options: XGatewayPostReplyOptions,
  ): Promise<unknown> {
    return executeStableCapability("post.reply", options);
  }

  async function postQuote(
    options: XGatewayPostQuoteOptions,
  ): Promise<unknown> {
    return executeStableCapability("post.quote", options);
  }

  async function postRepost(
    options: XGatewayPostRepostOptions,
  ): Promise<unknown> {
    return executeStableCapability("post.repost", options);
  }

  async function postUndoRepost(
    options: XGatewayPostRepostOptions,
  ): Promise<unknown> {
    return executeStableCapability("post.unrepost", options);
  }

  return {
    getResolvedConfig: () => resolved,
    request: rawGraphqlRequester.request,
    apiRequest,
    authVerify,
    authScopes,
    accountMe,
    postGet,
    timelineSearch,
    timelineHome,
    timelineUser,
    timelineMentions,
    postCreate,
    postDelete,
    postReply,
    postQuote,
    postRepost,
    postUndoRepost,
    capabilitiesList,
    capabilitiesGet,
  };
}
