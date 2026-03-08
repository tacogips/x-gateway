import {
  CAPABILITY_REGISTRY,
  isStableCapabilityId,
  type StableCapabilityId,
} from "./capability-metadata";
import {
  parsePublicGraphqlDocument,
  type PublicGraphqlLiteral,
  type PublicGraphqlSelection,
} from "./public-graphql-parser";

type ValidationErrorFactory = (message: string) => Error;
type PayloadErrorFactory = (fieldName: string, detail: string) => Error;

type PublicApiOperationType = "query" | "mutation";

type PublicApiRequestInput = Readonly<{
  query: string;
  traceId?: string;
}>;

export type PlannedPublicApiRequest = Readonly<{
  capabilityId: StableCapabilityId;
  operationType: PublicApiOperationType;
  fieldName: string;
  arguments: Readonly<Record<string, PublicGraphqlLiteral>>;
  selections: readonly PublicGraphqlSelection[];
  buildCapabilityInput: (
    args: Readonly<Record<string, PublicGraphqlLiteral>>,
  ) => unknown;
  normalizeResult: (value: unknown, fieldName: string) => unknown;
  traceId?: string;
}>;

type PublicApiFieldDefinition = Readonly<{
  fieldName: string;
  capabilityId: StableCapabilityId;
  operationType: PublicApiOperationType;
  buildCapabilityInput: (
    args: Readonly<Record<string, PublicGraphqlLiteral>>,
  ) => unknown;
  normalizeResult: (value: unknown, fieldName: string) => unknown;
}>;

let publicApiFieldRegistryValidated = false;

function readStringLiteral(
  args: Readonly<Record<string, PublicGraphqlLiteral>>,
  name: string,
  createValidationError: ValidationErrorFactory,
): string {
  const value = args[name];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw createValidationError(
      `Public GraphQL argument '${name}' must be a non-empty string.`,
    );
  }
  return value;
}

function readOptionalPositiveIntegerLiteral(
  args: Readonly<Record<string, PublicGraphqlLiteral>>,
  name: string,
  maximum: number,
  createValidationError: ValidationErrorFactory,
): number | undefined {
  const value = args[name];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 1 ||
    value > maximum
  ) {
    throw createValidationError(
      `Public GraphQL argument '${name}' must be an integer between 1 and ${maximum}.`,
    );
  }
  return value;
}

function readObjectRecord(
  value: unknown,
  fieldName: string,
  detail: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw createPayloadError(fieldName, detail);
  }
  return value as Readonly<Record<string, unknown>>;
}

function readArrayValue(
  value: unknown,
  fieldName: string,
  detail: string,
  createPayloadError: PayloadErrorFactory,
): readonly unknown[] {
  if (!Array.isArray(value)) {
    throw createPayloadError(fieldName, detail);
  }
  return value;
}

function readTransportDataRecord(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  const record = readObjectRecord(
    value,
    fieldName,
    "The reviewed adapter did not return the expected { data: ... } shape.",
    createPayloadError,
  );
  return readObjectRecord(
    record["data"],
    fieldName,
    "The reviewed adapter returned a non-object data payload.",
    createPayloadError,
  );
}

function normalizePostLookupResult(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  const result = readObjectRecord(
    value,
    fieldName,
    "The post lookup adapter did not return the expected { post, referencedPosts } shape.",
    createPayloadError,
  );
  const post = readObjectRecord(
    result["post"],
    fieldName,
    "The post lookup adapter returned a non-object 'post' payload.",
    createPayloadError,
  );
  const referencedPosts = readArrayValue(
    result["referencedPosts"],
    fieldName,
    "The post lookup adapter returned a non-array 'referencedPosts' payload.",
    createPayloadError,
  );
  return {
    ...post,
    referencedPosts,
  };
}

function normalizeLikesListResult(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): readonly unknown[] {
  const result = readObjectRecord(
    value,
    fieldName,
    "The liked-posts adapter did not return the expected { posts: ... } shape.",
    createPayloadError,
  );
  return readArrayValue(
    result["posts"],
    fieldName,
    "The liked-posts adapter returned a non-array 'posts' payload.",
    createPayloadError,
  );
}

function createPublicApiFieldRegistry(
  createValidationError: ValidationErrorFactory,
  createPayloadError: PayloadErrorFactory,
): readonly PublicApiFieldDefinition[] {
  return [
    {
      fieldName: "accountMe",
      capabilityId: "account.me",
      operationType: "query",
      buildCapabilityInput: () => undefined,
      normalizeResult: (value) => value,
    },
    {
      fieldName: "post",
      capabilityId: "post.get",
      operationType: "query",
      buildCapabilityInput: (args) => ({
        postId: readStringLiteral(args, "id", createValidationError),
      }),
      normalizeResult: (value, fieldName) =>
        normalizePostLookupResult(value, fieldName, createPayloadError),
    },
    {
      fieldName: "likedPosts",
      capabilityId: "likes.list",
      operationType: "query",
      buildCapabilityInput: (args) => ({
        userId: readStringLiteral(args, "userId", createValidationError),
        limit: readOptionalPositiveIntegerLiteral(
          args,
          "limit",
          100,
          createValidationError,
        ),
      }),
      normalizeResult: (value, fieldName) =>
        normalizeLikesListResult(value, fieldName, createPayloadError),
    },
    {
      fieldName: "createPost",
      capabilityId: "post.create",
      operationType: "mutation",
      buildCapabilityInput: (args) => ({
        text: readStringLiteral(args, "text", createValidationError),
      }),
      normalizeResult: (value, fieldName) => {
        const data = readTransportDataRecord(
          value,
          fieldName,
          createPayloadError,
        );
        return {
          id: data["id"],
          text: data["text"],
        };
      },
    },
    {
      fieldName: "deletePost",
      capabilityId: "post.delete",
      operationType: "mutation",
      buildCapabilityInput: (args) => ({
        postId: readStringLiteral(args, "id", createValidationError),
      }),
      normalizeResult: (value, fieldName) => {
        const data = readTransportDataRecord(
          value,
          fieldName,
          createPayloadError,
        );
        return {
          id: data["postId"],
          deleted: data["deleted"],
        };
      },
    },
    {
      fieldName: "replyToPost",
      capabilityId: "post.reply",
      operationType: "mutation",
      buildCapabilityInput: (args) => ({
        text: readStringLiteral(args, "text", createValidationError),
        replyToPostId: readStringLiteral(
          args,
          "replyToPostId",
          createValidationError,
        ),
      }),
      normalizeResult: (value, fieldName) => {
        const data = readTransportDataRecord(
          value,
          fieldName,
          createPayloadError,
        );
        return {
          id: data["id"],
          text: data["text"],
        };
      },
    },
    {
      fieldName: "quotePost",
      capabilityId: "post.quote",
      operationType: "mutation",
      buildCapabilityInput: (args) => ({
        text: readStringLiteral(args, "text", createValidationError),
        quotedPostId: readStringLiteral(
          args,
          "quotedPostId",
          createValidationError,
        ),
      }),
      normalizeResult: (value, fieldName) => {
        const data = readTransportDataRecord(
          value,
          fieldName,
          createPayloadError,
        );
        return {
          id: data["id"],
          text: data["text"],
        };
      },
    },
    {
      fieldName: "repostPost",
      capabilityId: "post.repost",
      operationType: "mutation",
      buildCapabilityInput: (args) => ({
        postId: readStringLiteral(args, "id", createValidationError),
      }),
      normalizeResult: (value, fieldName) => {
        const data = readTransportDataRecord(
          value,
          fieldName,
          createPayloadError,
        );
        return {
          id: data["postId"],
          reposted: data["retweeted"],
        };
      },
    },
    {
      fieldName: "unrepostPost",
      capabilityId: "post.unrepost",
      operationType: "mutation",
      buildCapabilityInput: (args) => ({
        postId: readStringLiteral(args, "id", createValidationError),
      }),
      normalizeResult: (value, fieldName) => {
        const data = readTransportDataRecord(
          value,
          fieldName,
          createPayloadError,
        );
        return {
          id: data["postId"],
          reposted: data["retweeted"],
        };
      },
    },
  ];
}

function ensurePublicApiFieldRegistryCoherent(
  fieldRegistry: readonly PublicApiFieldDefinition[],
): void {
  if (publicApiFieldRegistryValidated) {
    return;
  }

  const seenFieldNames = new Set<string>();
  const referencedCapabilityIds = new Set<StableCapabilityId>();
  for (const fieldDefinition of fieldRegistry) {
    if (seenFieldNames.has(fieldDefinition.fieldName)) {
      throw new Error(
        `Public GraphQL field registry contains duplicate field '${fieldDefinition.fieldName}'.`,
      );
    }
    seenFieldNames.add(fieldDefinition.fieldName);

    const capability = CAPABILITY_REGISTRY.find(
      (entry) => entry.id === fieldDefinition.capabilityId,
    );
    if (!capability) {
      throw new Error(
        `Public GraphQL field '${fieldDefinition.fieldName}' references missing capability '${fieldDefinition.capabilityId}'.`,
      );
    }
    if (!isStableCapabilityId(capability.id)) {
      throw new Error(
        `Public GraphQL field '${fieldDefinition.fieldName}' references non-stable capability '${capability.id}'.`,
      );
    }
    if (capability.status !== "implemented") {
      throw new Error(
        `Public GraphQL field '${fieldDefinition.fieldName}' references capability '${capability.id}', but that capability is not implemented.`,
      );
    }
    if (capability.publicOperationName !== fieldDefinition.fieldName) {
      throw new Error(
        `Public GraphQL field '${fieldDefinition.fieldName}' is out of sync with capability '${capability.id}' publicOperationName '${capability.publicOperationName ?? "undefined"}'.`,
      );
    }

    referencedCapabilityIds.add(capability.id);
  }

  const stablePublicCapabilities = CAPABILITY_REGISTRY.filter(
    (
      capability,
    ): capability is (typeof CAPABILITY_REGISTRY)[number] & {
      id: StableCapabilityId;
      publicOperationName: string;
    } =>
      capability.status === "implemented" &&
      isStableCapabilityId(capability.id) &&
      typeof capability.publicOperationName === "string",
  );

  for (const capability of stablePublicCapabilities) {
    if (!referencedCapabilityIds.has(capability.id)) {
      throw new Error(
        `Stable capability '${capability.id}' declares publicOperationName '${capability.publicOperationName}', but no public GraphQL field is registered for it.`,
      );
    }
  }

  publicApiFieldRegistryValidated = true;
}

export function createPublicApiRequestPlan(
  input: PublicApiRequestInput,
  createValidationError: ValidationErrorFactory,
  createPayloadError: PayloadErrorFactory,
): PlannedPublicApiRequest {
  const fieldRegistry = createPublicApiFieldRegistry(
    createValidationError,
    createPayloadError,
  );
  ensurePublicApiFieldRegistryCoherent(fieldRegistry);
  const document = parsePublicGraphqlDocument(
    input.query,
    createValidationError,
  );
  const fieldDefinition = fieldRegistry.find(
    (entry) => entry.fieldName === document.field.name,
  );

  if (!fieldDefinition) {
    throw createValidationError(
      `Public GraphQL field '${document.field.name}' is not part of the stable x-gateway contract.`,
    );
  }

  if (document.operationType !== fieldDefinition.operationType) {
    throw createValidationError(
      `Public GraphQL field '${document.field.name}' is not valid for ${document.operationType}.`,
    );
  }

  return {
    capabilityId: fieldDefinition.capabilityId,
    operationType: document.operationType,
    fieldName: document.field.name,
    arguments: document.field.arguments,
    selections: document.field.selections,
    buildCapabilityInput: fieldDefinition.buildCapabilityInput,
    normalizeResult: fieldDefinition.normalizeResult,
    ...(input.traceId === undefined ? {} : { traceId: input.traceId }),
  };
}

export function projectPublicSelection(
  value: unknown,
  selections: readonly PublicGraphqlSelection[],
): unknown {
  if (selections.length === 0 || value === null || value === undefined) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => projectPublicSelection(item, selections));
  }
  if (typeof value !== "object") {
    return value;
  }

  const record = value as Record<string, unknown>;
  const projected: Record<string, unknown> = {};
  for (const selection of selections) {
    if (!(selection.name in record)) {
      continue;
    }
    const selectedValue = record[selection.name];
    projected[selection.name] =
      selection.selections.length > 0
        ? projectPublicSelection(selectedValue, selection.selections)
        : selectedValue;
  }
  return projected;
}
