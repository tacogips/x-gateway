import packageJson from "../package.json";
import { printSchema } from "graphql";
import {
  XGatewayError,
  createXGatewayClient,
  inferGraphqlQueryOperationType,
  toCommandError,
  type XGatewayConfigMode,
  type XGatewayConfig,
  type XGatewayOperationType,
} from "./lib";
import { PUBLIC_GRAPHQL_SCHEMA } from "./public-graphql-schema";

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

type ParsedGlobalFlags = Readonly<{
  asJson: boolean;
  pretty: boolean;
  traceId?: string;
  config: XGatewayConfig;
}>;

const GLOBAL_FLAG_NAMES = new Set([
  "json",
  "pretty",
  "trace-id",
  "config-mode",
  "auth-mode",
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

const DEPRECATED_FLAG_NAMES = new Map<string, string>();

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

function getOptionalStringFlag(
  args: ParsedArgs,
  key: string,
): string | undefined {
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

function readGraphqlQueryDocument(parsed: ParsedArgs): string {
  const queryPositionals = parsed.positionals.slice(2);
  if (queryPositionals.length === 0) {
    throw createFlagValidationError(
      "graphql query requires a single shell-quoted GraphQL document positional argument.",
    );
  }
  if (queryPositionals.length > 1) {
    throw createFlagValidationError(
      "graphql query accepts exactly one shell-quoted GraphQL document positional argument.",
    );
  }
  const query = queryPositionals[0]?.trim();
  if (!query) {
    throw createFlagValidationError(
      "graphql query requires a non-empty GraphQL document positional argument.",
    );
  }
  return query;
}

function assertNoExtraPositionals(
  parsed: ParsedArgs,
  expectedCount: number,
  commandLabel: string,
): void {
  if (parsed.positionals.length > expectedCount) {
    throw createFlagValidationError(
      `${commandLabel} does not accept additional positional arguments.`,
    );
  }
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
  const configModeFlag = getOptionalStringFlag(args, "config-mode");
  const authModeFlag = getOptionalStringFlag(args, "auth-mode");
  if (
    configModeFlag !== undefined &&
    authModeFlag !== undefined &&
    configModeFlag !== authModeFlag
  ) {
    throw createFlagValidationError(
      "Flags --config-mode and --auth-mode must match when both are provided.",
    );
  }
  const configModeRaw = configModeFlag ?? authModeFlag;
  const configMode: XGatewayConfigMode | undefined =
    configModeRaw === "env" ||
    configModeRaw === "params" ||
    configModeRaw === "mixed"
      ? configModeRaw
      : configModeRaw === undefined
        ? undefined
        : (() => {
            throw createFlagValidationError(
              "Flag --config-mode must be one of 'env', 'params', or 'mixed'. --auth-mode is accepted as a deprecated alias.",
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
    ...(configMode === undefined ? {} : { configMode }),
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
  };
}

function readParsedGlobalFlags(args: ParsedArgs): ParsedGlobalFlags {
  const asJson = getBooleanFlag(args, "json");
  const pretty = getBooleanFlag(args, "pretty");
  const traceId = getOptionalStringFlag(args, "trace-id");
  const config = buildConfigFromFlags(args);

  return {
    asJson,
    pretty,
    ...(traceId === undefined ? {} : { traceId }),
    config,
  };
}

function usage(commandName: string): string {
  return [
    `${commandName} command usage:`,
    `  ${commandName} auth verify|scopes`,
    `  ${commandName} graphql query '<query>'`,
    `  ${commandName} graphql schema`,
    `  ${commandName} capabilities list`,
    `  ${commandName} capabilities get --id <capabilityId>`,
    `  ${commandName} health`,
    `  ${commandName} version`,
    "",
    "Notes:",
    "  - 'graphql query' is the primary public interface for reviewed capabilities.",
    "  - 'graphql' refers to the owned x-gateway contract, not direct upstream X GraphQL.",
    "  - Legacy convenience command groups were removed from the public CLI surface.",
    "  - Unimplemented high-level workflows must be added as reviewed project-owned GraphQL fields first.",
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
      "Re-run with a read-only project-owned GraphQL query if the workflow should remain read-only.",
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

  if (
    group === "graphql" &&
    action === "query" &&
    operationType === "mutation"
  ) {
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
    details: `The command '${attempted}' does not have a reviewed capability adapter in this repository state.`,
    likelyCauses: [
      "The capability has not been restored on the stable CLI/SDK surface yet",
      "A previous placeholder command surface remained in documentation or memory",
    ],
    remediations: [
      `Use '${commandName} graphql query '<query>'' for reviewed project-owned GraphQL operations.`,
      "Add a reviewed project-owned GraphQL field before reintroducing this workflow.",
    ],
    classification: "unsupported",
    retryable: false,
  });
}

function createRemovedLegacyCommandError(
  commandName: string,
  attempted: string,
  replacement: string,
): XGatewayError {
  return new XGatewayError({
    code: "UNSUPPORTED",
    summary: `${attempted} was removed from the public ${commandName} surface`,
    details: `The legacy command '${attempted}' is no longer part of the supported CLI surface. Use the canonical project-owned GraphQL interface instead.`,
    likelyCauses: [
      "A transitional convenience command remained in prior workflow documentation or shell history",
      "The repository now treats GraphQL as the only reviewed public data interface",
    ],
    remediations: [
      `Use '${commandName} ${replacement}' instead.`,
      `Run '${commandName}' with no arguments to view the current supported command list.`,
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
      `Use '${commandName} graphql query '<query>'' for the canonical public interface.`,
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
  const supported = new Set([
    "health",
    "version",
    "graphql",
    "auth",
    "capabilities",
  ]);
  if (supported.has(group)) {
    return;
  }
  if (group === "api" && action === "request") {
    throw createRemovedLegacyCommandError(
      commandName,
      "api request",
      "graphql query '<query>'",
    );
  }
  if (group === "schema" && action === "print") {
    throw createRemovedLegacyCommandError(
      commandName,
      "schema print",
      "graphql schema",
    );
  }
  const removedLegacy = new Set(["account", "usage", "post", "timeline"]);
  if (removedLegacy.has(group)) {
    const attempted = action ? `${group} ${action}` : group;
    throw createRemovedLegacyCommandError(
      commandName,
      attempted,
      "graphql query '<query>'",
    );
  }
  const deferred = new Set([
    "media",
    "tweet",
    "users",
    "likes",
    "bookmarks",
    "follows",
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
  return executeParsedCli(parseArgs(argv), options);
}

async function executeParsedCli(
  parsed: ParsedArgs,
  options: CliOptions,
  parsedGlobalFlags?: ParsedGlobalFlags,
): Promise<unknown> {
  const [group, action] = parsed.positionals;

  if (!group) {
    assertAllowedFlags(parsed, group, action);
    readParsedGlobalFlags(parsed);
    return usage(options.commandName);
  }

  assertSupportedCommandSurface(options.commandName, group, action);
  assertAllowedFlags(parsed, group, action);
  const globalFlags = parsedGlobalFlags ?? readParsedGlobalFlags(parsed);

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

  const operationType =
    group === "graphql" && action === "query"
      ? inferGraphqlQueryOperationType(readGraphqlQueryDocument(parsed))
      : ("query" as XGatewayOperationType);
  ensureMutableCommand(
    options.surface,
    options.commandName,
    group,
    action,
    operationType,
  );

  if (group === "graphql") {
    if (action === "schema") {
      assertNoExtraPositionals(parsed, 2, "graphql schema");
      return printSchema(PUBLIC_GRAPHQL_SCHEMA);
    }
    if (action === "query") {
      const query = readGraphqlQueryDocument(parsed);
      const { traceId } = globalFlags;
      const client = createXGatewayClient(globalFlags.config);
      return client.graphqlQuery({
        query,
        ...(traceId === undefined ? {} : { traceId }),
      });
    }
    throw createUnknownCommandError(
      options.commandName,
      `${group} ${action ?? ""}`.trim(),
    );
  }

  const client = createXGatewayClient(globalFlags.config);

  if (group === "auth") {
    if (action === "verify") {
      return client.authVerify();
    }
    if (action === "scopes") {
      return client.authScopes();
    }
    throw createUnknownCommandError(
      options.commandName,
      `${group} ${action ?? ""}`.trim(),
    );
  }

  if (group === "capabilities") {
    if (action === "list") {
      return client.capabilitiesList();
    }
    if (action === "get") {
      return client.capabilitiesGet(getRequiredFlag(parsed, "id"));
    }
    throw createUnknownCommandError(
      options.commandName,
      `${group} ${action ?? ""}`.trim(),
    );
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
    const parsedGlobalFlags = readParsedGlobalFlags(parsed);
    asJson = parsedGlobalFlags.asJson || process.env["X_GW_OUTPUT"] === "json";
    pretty = parsedGlobalFlags.pretty;
    traceId = parsedGlobalFlags.traceId;
    const result = await executeParsedCli(parsed, options, parsedGlobalFlags);
    printSuccess(result, asJson, pretty);
  } catch (error) {
    const commandError = toCommandError(error, traceId);
    printError(commandError.error, asJson, pretty);
    process.exit(commandError.exitCode);
  }
}
