import packageJson from "../package.json";
import {
  XGatewayError,
  createXGatewayClient,
  toCommandError,
  type XGatewayAuthMode,
  type XGatewayConfig,
  type XGatewayOperationType,
} from "./lib";

export type CliSurface = "full" | "reader";

type CliOptions = Readonly<{
  commandName: string;
  surface: CliSurface;
}>;

type ParsedFlagValue = Readonly<{
  value: string;
  explicit: boolean;
}>;

type ParsedArgs = Readonly<{
  positionals: readonly string[];
  flags: Readonly<Record<string, readonly ParsedFlagValue[]>>;
}>;

const GLOBAL_FLAG_NAMES = new Set([
  "json",
  "pretty",
  "trace-id",
  "auth-mode",
  "graphql-base-url",
  "timeout-ms",
  "retry",
  "retry-backoff",
  "retry-base-ms",
  "retry-max-ms",
  "strict-capability-checks",
  "token",
  "consumer-key",
  "consumer-secret",
  "access-token",
  "access-token-secret",
  "client-id",
  "client-secret",
]);

const DEPRECATED_FLAG_NAMES = new Map<string, string>([
  ["api-base-url", "--graphql-base-url"],
]);

function parseArgs(argv: readonly string[]): ParsedArgs {
  const positionals: string[] = [];
  const flags = new Map<string, ParsedFlagValue[]>();

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    if (!current) {
      continue;
    }
    if (!current.startsWith("--")) {
      positionals.push(current);
      continue;
    }

    const trimmed = current.slice(2);
    const [rawKey, rawValue] = trimmed.split("=", 2);
    if (!rawKey) {
      continue;
    }
    const key = rawKey.trim();
    if (key.length === 0) {
      continue;
    }

    let value = rawValue;
    let explicit = rawValue !== undefined;
    if (value === undefined) {
      const next = argv[index + 1];
      if (next && !next.startsWith("--")) {
        value = next;
        explicit = true;
        index += 1;
      } else {
        value = "true";
      }
    }

    const existing = flags.get(key) ?? [];
    existing.push({ value, explicit });
    flags.set(key, existing);
  }

  return {
    positionals,
    flags: Object.fromEntries(flags),
  };
}

function getLastFlagValue(
  args: ParsedArgs,
  key: string,
  options?: Readonly<{ allowImplicitBoolean?: boolean }>,
): string | undefined {
  const lastValue = getLastParsedFlag(args, key);
  if (!lastValue) {
    return undefined;
  }
  if (!lastValue.explicit && options?.allowImplicitBoolean !== true) {
    return undefined;
  }
  return lastValue.value;
}

function getLastParsedFlag(
  args: ParsedArgs,
  key: string,
): ParsedFlagValue | undefined {
  const values = args.flags[key];
  if (!values || values.length === 0) {
    return undefined;
  }
  return values[values.length - 1];
}

function getOptionalStringFlag(args: ParsedArgs, key: string): string | undefined {
  const value = getLastParsedFlag(args, key);
  if (value === undefined) {
    return undefined;
  }
  if (!value.explicit) {
    throw createFlagValidationError(`Flag --${key} requires a value.`);
  }
  return value.value;
}

function parseBooleanFlagValue(key: string, value: string): boolean {
  const normalized = value.toLowerCase();
  if (normalized === "true" || normalized === "1" || normalized === "yes") {
    return true;
  }
  if (normalized === "false" || normalized === "0" || normalized === "no") {
    return false;
  }
  throw createFlagValidationError(
    `Flag --${key} must be a boolean value ('true' or 'false').`,
  );
}

function getBooleanFlag(args: ParsedArgs, key: string): boolean {
  const value = getLastFlagValue(args, key, { allowImplicitBoolean: true });
  if (!value) {
    return false;
  }
  return parseBooleanFlagValue(key, value);
}

function getOptionalBooleanFlag(
  args: ParsedArgs,
  key: string,
): boolean | undefined {
  const value = getLastFlagValue(args, key, { allowImplicitBoolean: true });
  if (value === undefined) {
    return undefined;
  }
  return parseBooleanFlagValue(key, value);
}

function getOptionalNumberFlag(
  args: ParsedArgs,
  key: string,
): number | undefined {
  const value = getOptionalStringFlag(args, key);
  if (value === undefined) {
    return undefined;
  }
  if (!/^(0|[1-9][0-9]*)$/.test(value)) {
    throw createFlagValidationError(`Flag --${key} must be an integer.`);
  }
  const parsed = Number.parseInt(value, 10);
  if (parsed < 0) {
    throw createFlagValidationError(`Flag --${key} must be zero or greater.`);
  }
  return parsed;
}

function getRequiredFlag(args: ParsedArgs, key: string): string {
  const value = getOptionalStringFlag(args, key);
  if (!value || value.trim().length === 0) {
    throw createFlagValidationError(`Missing required flag --${key}.`);
  }
  return value;
}

function createFlagValidationError(message: string): XGatewayError {
  return new XGatewayError({
    code: "VALIDATION_ERROR",
    summary: "CLI flag validation failed",
    details: message,
    likelyCauses: [
      "A required flag is missing",
      "A JSON-typed flag contains malformed input",
    ],
    remediations: [
      "Review the command usage and required flags.",
      "Pass valid JSON for structured GraphQL input flags.",
    ],
    classification: "validation",
    retryable: false,
  });
}

function allowedCommandFlagNames(
  group: string | undefined,
  action: string | undefined,
): ReadonlySet<string> {
  const allowed = new Set(GLOBAL_FLAG_NAMES);

  if (group === undefined) {
    return allowed;
  }

  if (group === "graphql" && action === "request") {
    allowed.add("operation-type");
    allowed.add("operation-name");
    allowed.add("document-id");
    allowed.add("query");
    allowed.add("variables-json");
    allowed.add("features-json");
    allowed.add("field-toggles-json");
    return allowed;
  }

  if (group === "capabilities" && action === "get") {
    allowed.add("id");
    return allowed;
  }

  return allowed;
}

function assertAllowedFlags(
  args: ParsedArgs,
  group: string | undefined,
  action: string | undefined,
): void {
  const allowed = allowedCommandFlagNames(group, action);

  for (const key of Object.keys(args.flags)) {
    const replacement = DEPRECATED_FLAG_NAMES.get(key);
    if (replacement !== undefined) {
      throw createFlagValidationError(
        `Flag --${key} is no longer supported. Use ${replacement} instead.`,
      );
    }

    if (!allowed.has(key)) {
      throw createFlagValidationError(`Unknown flag --${key}.`);
    }
  }
}

function parseJsonRecordFlag(
  args: ParsedArgs,
  key: string,
): Readonly<Record<string, unknown>> | undefined {
  const value = getOptionalStringFlag(args, key);
  if (value === undefined) {
    return undefined;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(value) as unknown;
  } catch (error: unknown) {
    const detail = error instanceof Error ? error.message : "Unknown JSON parse error";
    throw createFlagValidationError(`Flag --${key} must be valid JSON. ${detail}`);
  }

  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw createFlagValidationError(
      `Flag --${key} must be a JSON object, not an array or primitive value.`,
    );
  }

  return parsed as Readonly<Record<string, unknown>>;
}

function getOperationType(args: ParsedArgs): XGatewayOperationType {
  const value = getOptionalStringFlag(args, "operation-type");
  if (value === undefined || value === "query") {
    return "query";
  }
  if (value === "mutation") {
    return "mutation";
  }
  throw createFlagValidationError(
    "Flag --operation-type must be either 'query' or 'mutation'.",
  );
}

function printSuccess(
  payload: unknown,
  asJson: boolean,
  pretty: boolean,
): void {
  if (asJson) {
    const spacing = pretty ? 2 : 0;
    console.log(JSON.stringify({ ok: true, data: payload }, null, spacing));
    return;
  }
  if (typeof payload === "string") {
    console.log(payload);
    return;
  }
  console.log(JSON.stringify(payload, null, 2));
}

function printError(
  error: XGatewayError,
  asJson: boolean,
  pretty: boolean,
): void {
  if (asJson) {
    const spacing = pretty ? 2 : 0;
    console.error(JSON.stringify(error.toJSON(), null, spacing));
    return;
  }
  const p = error.payload;
  console.error(`ERROR [${p.code}] ${p.summary}`);
  console.error(`Details: ${p.details}`);
  if (p.httpStatus) {
    console.error(`HTTP Status: ${p.httpStatus}`);
  }
  if (p.traceId) {
    console.error(`Trace ID: ${p.traceId}`);
  }
  if (p.attempts !== undefined) {
    console.error(`Attempts: ${p.attempts}`);
  }
  if (p.elapsedMs !== undefined) {
    console.error(`Elapsed: ${p.elapsedMs}ms`);
  }
  console.error("Likely causes:");
  for (const cause of p.likelyCauses) {
    console.error(`- ${cause}`);
  }
  console.error("Remediations:");
  for (const remediation of p.remediations) {
    console.error(`- ${remediation}`);
  }
}

function buildConfigFromFlags(args: ParsedArgs): XGatewayConfig {
  const retryBackoffRaw = getOptionalStringFlag(args, "retry-backoff");
  const backoff =
    retryBackoffRaw === "fixed" ||
    retryBackoffRaw === "none" ||
    retryBackoffRaw === "exponential-jitter"
      ? retryBackoffRaw
      : retryBackoffRaw === undefined
        ? undefined
        : (() => {
            throw createFlagValidationError(
              "Flag --retry-backoff must be one of 'exponential-jitter', 'fixed', or 'none'.",
            );
          })();
  const authModeRaw = getOptionalStringFlag(args, "auth-mode");
  const authMode: XGatewayAuthMode | undefined =
    authModeRaw === "env" || authModeRaw === "params" || authModeRaw === "mixed"
      ? authModeRaw
      : authModeRaw === undefined
        ? undefined
        : (() => {
            throw createFlagValidationError(
              "Flag --auth-mode must be one of 'env', 'params', or 'mixed'.",
            );
          })();
  const timeoutMs = getOptionalNumberFlag(args, "timeout-ms");
  const strictCapabilityChecks = getOptionalBooleanFlag(
    args,
    "strict-capability-checks",
  );
  const retries = getOptionalNumberFlag(args, "retry");
  const baseDelayMs = getOptionalNumberFlag(args, "retry-base-ms");
  const maxDelayMs = getOptionalNumberFlag(args, "retry-max-ms");

  return {
    ...(authMode === undefined ? {} : { authMode }),
    ...(timeoutMs === undefined ? {} : { timeoutMs }),
    ...(strictCapabilityChecks === undefined ? {} : { strictCapabilityChecks }),
    retry: {
      ...(retries === undefined ? {} : { retries }),
      backoff,
      ...(baseDelayMs === undefined ? {} : { baseDelayMs }),
      ...(maxDelayMs === undefined ? {} : { maxDelayMs }),
    },
    auth: {
      token: getOptionalStringFlag(args, "token"),
      consumerKey: getOptionalStringFlag(args, "consumer-key"),
      consumerSecret: getOptionalStringFlag(args, "consumer-secret"),
      accessToken: getOptionalStringFlag(args, "access-token"),
      accessTokenSecret: getOptionalStringFlag(args, "access-token-secret"),
      clientId: getOptionalStringFlag(args, "client-id"),
      clientSecret: getOptionalStringFlag(args, "client-secret"),
    },
    graphqlBaseUrl: getOptionalStringFlag(args, "graphql-base-url"),
  };
}

function usage(commandName: string, surface: CliSurface): string {
  const graphqlCommand =
    surface === "reader"
      ? `  ${commandName} graphql request --operation-name <name> [--operation-type query] (--document-id <id> | --query <graphql>) [--variables-json <json>] [--features-json <json>] [--field-toggles-json <json>]`
      : `  ${commandName} graphql request --operation-name <name> [--operation-type query|mutation] (--document-id <id> | --query <graphql>) [--variables-json <json>] [--features-json <json>] [--field-toggles-json <json>]`;

  return [
    `${commandName} command usage:`,
    `  ${commandName} auth verify|scopes`,
    `${graphqlCommand} [--graphql-base-url <url>]`,
    `  ${commandName} capabilities list`,
    `  ${commandName} capabilities get --id <capabilityId>`,
    `  ${commandName} health`,
    `  ${commandName} version`,
    "",
    "Notes:",
    "  - 'graphql request' is the primary supported GraphQL-first interface.",
    "  - Unmapped high-level endpoint commands are intentionally rejected until reviewed GraphQL mappings exist.",
  ].join("\n");
}

function createReadOnlyCommandError(
  commandName: string,
  attempted: string,
): XGatewayError {
  return new XGatewayError({
    code: "UNSUPPORTED",
    summary: `${commandName} supports read-only commands only`,
    details: `The command '${attempted}' performs a write action and is disabled for ${commandName}.`,
    likelyCauses: [
      "Read-only binary was used for a mutation operation",
      "The workflow requires posting or engagement changes",
    ],
    remediations: [
      "Use x-gateway for mutation operations.",
      "Re-run with 'graphql request --operation-type query' if the workflow should remain read-only.",
      `Run ${commandName} with no arguments to view the read-only command list`,
    ],
    classification: "unsupported",
    retryable: false,
  });
}

function ensureMutableCommand(
  surface: CliSurface,
  commandName: string,
  group: string,
  action: string | undefined,
  operationType: XGatewayOperationType,
): void {
  if (surface !== "reader") {
    return;
  }

  const blocked =
    group === "post" ||
    (group === "media" && (action === "upload" || action === "alt-text")) ||
    (group === "follows" && (action === "add" || action === "remove")) ||
    (group === "likes" && (action === "add" || action === "remove")) ||
    (group === "bookmarks" && (action === "add" || action === "remove")) ||
    (group === "dm" && action === "send") ||
    (group === "graphql" && action === "request" && operationType === "mutation");

  if (blocked) {
    const attempted = action ? `${group} ${action}` : group;
    throw createReadOnlyCommandError(commandName, attempted);
  }
}

function createUnsupportedCommandSurfaceError(
  commandName: string,
  attempted: string,
): XGatewayError {
  return new XGatewayError({
    code: "UNSUPPORTED",
    summary: `${attempted} is not part of the stable ${commandName} contract`,
    details:
      `The command '${attempted}' depends on a high-level GraphQL mapping that is not implemented in this repository state.`,
    likelyCauses: [
      "The tool was intentionally reduced to GraphQL-request input only",
      "A previous placeholder command surface remained in documentation or memory",
    ],
    remediations: [
      `Use '${commandName} graphql request ...' with explicit GraphQL input.`,
      "Add a reviewed GraphQL mapping before reintroducing this command group.",
    ],
    classification: "unsupported",
    retryable: false,
  });
}

function createUnknownCommandError(
  commandName: string,
  attempted: string,
): XGatewayError {
  return new XGatewayError({
    code: "VALIDATION_ERROR",
    summary: "Unknown command",
    details: `The command '${attempted}' is not recognized by ${commandName}.`,
    likelyCauses: [
      "Command name is misspelled",
      "The command belongs to a deferred high-level surface",
    ],
    remediations: [
      `Run '${commandName}' with no arguments to view supported commands.`,
      `Use '${commandName} graphql request ...' for live X API access.`,
    ],
    classification: "validation",
    retryable: false,
  });
}

function assertSupportedCommandSurface(
  commandName: string,
  group: string,
  action: string | undefined,
): void {
  const supported = new Set(["health", "version", "graphql", "auth", "capabilities"]);
  if (supported.has(group)) {
    return;
  }
  const deferred = new Set([
    "post",
    "media",
    "tweet",
    "timeline",
    "users",
    "likes",
    "bookmarks",
    "follows",
    "account",
    "dm",
  ]);
  if (!deferred.has(group)) {
    const attempted = action ? `${group} ${action}` : group;
    throw createUnknownCommandError(commandName, attempted);
  }
  const attempted = action ? `${group} ${action}` : group;
  throw createUnsupportedCommandSurfaceError(commandName, attempted);
}

export async function executeCli(
  argv: readonly string[],
  options: CliOptions,
): Promise<unknown> {
  const parsed = parseArgs(argv);
  const [group, action] = parsed.positionals;

  if (!group) {
    assertAllowedFlags(parsed, group, action);
    getBooleanFlag(parsed, "json");
    getBooleanFlag(parsed, "pretty");
    getOptionalStringFlag(parsed, "trace-id");
    buildConfigFromFlags(parsed);
    return usage(options.commandName, options.surface);
  }

  assertSupportedCommandSurface(options.commandName, group, action);
  assertAllowedFlags(parsed, group, action);
  getBooleanFlag(parsed, "json");
  getBooleanFlag(parsed, "pretty");
  getOptionalStringFlag(parsed, "trace-id");
  buildConfigFromFlags(parsed);

  if (group === "health") {
    return {
      status: "ok",
      time: new Date().toISOString(),
    };
  }

  if (group === "version") {
    return {
      name: packageJson.name,
      version: packageJson.version,
    };
  }

  const operationType = getOperationType(parsed);
  ensureMutableCommand(
    options.surface,
    options.commandName,
    group,
    action,
    operationType,
  );

  const client = createXGatewayClient(buildConfigFromFlags(parsed));

  if (group === "auth") {
    if (action === "verify") {
      return client.authVerify();
    }
    if (action === "scopes") {
      return client.authScopes();
    }
    throw createUnknownCommandError(options.commandName, `${group} ${action ?? ""}`.trim());
  }

  if (group === "graphql" && action === "request") {
    const documentId = getOptionalStringFlag(parsed, "document-id");
    const query = getOptionalStringFlag(parsed, "query");
    const variables = parseJsonRecordFlag(parsed, "variables-json");
    const features = parseJsonRecordFlag(parsed, "features-json");
    const fieldToggles = parseJsonRecordFlag(parsed, "field-toggles-json");
    const traceId = getOptionalStringFlag(parsed, "trace-id");

    return client.request({
      operationName: getRequiredFlag(parsed, "operation-name"),
      operationType,
      ...(documentId === undefined ? {} : { documentId }),
      ...(query === undefined ? {} : { query }),
      ...(variables === undefined ? {} : { variables }),
      ...(features === undefined ? {} : { features }),
      ...(fieldToggles === undefined ? {} : { fieldToggles }),
      ...(traceId === undefined ? {} : { traceId }),
    });
  }

  if (group === "capabilities") {
    if (action === "list") {
      return client.capabilitiesList();
    }
    if (action === "get") {
      return client.capabilitiesGet(getRequiredFlag(parsed, "id"));
    }
    throw createUnknownCommandError(options.commandName, `${group} ${action ?? ""}`.trim());
  }

  throw createUnknownCommandError(
    options.commandName,
    action ? `${group} ${action}` : group,
  );
}

export async function runCli(options: CliOptions): Promise<void> {
  let asJson = false;
  let pretty = false;
  let traceId: string | undefined;
  try {
    const parsed = parseArgs(process.argv.slice(2));
    asJson =
      getBooleanFlag(parsed, "json") || process.env["X_GW_OUTPUT"] === "json";
    pretty = getBooleanFlag(parsed, "pretty");
    traceId = getOptionalStringFlag(parsed, "trace-id");
    const result = await executeCli(process.argv.slice(2), options);
    printSuccess(result, asJson, pretty);
  } catch (error) {
    const commandError = toCommandError(error, traceId);
    printError(commandError.error, asJson, pretty);
    process.exit(commandError.exitCode);
  }
}
