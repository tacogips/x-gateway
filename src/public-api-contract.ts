import {
  getNamedType,
  isEnumType,
  isListType,
  isNonNullType,
  isObjectType,
  isScalarType,
  type GraphQLOutputType,
} from "graphql";
import {
  CAPABILITY_REGISTRY,
  isStableCapabilityId,
  type StableCapabilityId,
} from "./capability-metadata";
import {
  parsePublicGraphqlDocument,
  type PublicGraphqlValue,
  type PublicGraphqlSelection,
} from "./public-graphql-parser";
import { PUBLIC_GRAPHQL_SCHEMA } from "./public-graphql-schema";
import type { XGatewayPostAttachmentInput } from "./lib";

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
  arguments: Readonly<Record<string, PublicGraphqlValue>>;
  selections: readonly PublicGraphqlSelection[];
  selectionSchema: PublicSelectionSchema;
  buildCapabilityInput: (
    args: Readonly<Record<string, PublicGraphqlValue>>,
  ) => unknown;
  normalizeResult: (value: unknown, fieldName: string) => unknown;
  traceId?: string;
}>;

type PublicApiFieldDefinition = Readonly<{
  fieldName: string;
  capabilityId: StableCapabilityId;
  operationType: PublicApiOperationType;
  allowedArgumentNames: readonly string[];
  selectionSchema: PublicSelectionSchema;
  buildCapabilityInput: (
    args: Readonly<Record<string, PublicGraphqlValue>>,
  ) => unknown;
  normalizeResult: (value: unknown, fieldName: string) => unknown;
}>;

let publicApiFieldRegistryValidated = false;

type PublicSelectionSchema =
  | Readonly<{ kind: "scalar"; optional?: boolean }>
  | Readonly<{
      kind: "object";
      fields: Readonly<Record<string, PublicSelectionSchema>>;
      optional?: boolean;
    }>
  | Readonly<{
      kind: "list";
      item: PublicSelectionSchema;
      optional?: boolean;
    }>;

function buildSelectionSchemaFromOutputType(
  outputType: GraphQLOutputType,
  optional = true,
): PublicSelectionSchema {
  if (isNonNullType(outputType)) {
    return buildSelectionSchemaFromOutputType(outputType.ofType, false);
  }

  if (isListType(outputType)) {
    return {
      kind: "list",
      item: buildSelectionSchemaFromOutputType(outputType.ofType),
      ...(optional ? { optional: true } : {}),
    };
  }

  const namedType = getNamedType(outputType);
  if (isScalarType(namedType) || isEnumType(namedType)) {
    return optional ? { kind: "scalar", optional: true } : { kind: "scalar" };
  }

  if (isObjectType(namedType)) {
    const fields = Object.fromEntries(
      Object.entries(namedType.getFields()).map(
        ([fieldName, fieldDefinition]) => [
          fieldName,
          buildSelectionSchemaFromOutputType(fieldDefinition.type),
        ],
      ),
    );
    return {
      kind: "object",
      fields,
      ...(optional ? { optional: true } : {}),
    };
  }

  throw new Error(
    `Public GraphQL schema contains unsupported output type '${namedType.toString()}'.`,
  );
}

function getPublicRootType(operationType: PublicApiOperationType) {
  const rootType =
    operationType === "query"
      ? PUBLIC_GRAPHQL_SCHEMA.getQueryType()
      : PUBLIC_GRAPHQL_SCHEMA.getMutationType();
  if (!rootType) {
    throw new Error(
      `Public GraphQL schema is missing a ${operationType} root type.`,
    );
  }
  return rootType;
}

function readSchemaFieldArgumentNames(
  fieldName: string,
  operationType: PublicApiOperationType,
): readonly string[] {
  const fieldDefinition =
    getPublicRootType(operationType).getFields()[fieldName];
  if (!fieldDefinition) {
    throw new Error(
      `Public GraphQL schema is missing ${operationType} field '${fieldName}'.`,
    );
  }
  return fieldDefinition.args.map((argument) => argument.name);
}

function readSchemaFieldSelectionSchema(
  fieldName: string,
  operationType: PublicApiOperationType,
): PublicSelectionSchema {
  const fieldDefinition =
    getPublicRootType(operationType).getFields()[fieldName];
  if (!fieldDefinition) {
    throw new Error(
      `Public GraphQL schema is missing ${operationType} field '${fieldName}'.`,
    );
  }
  return buildSelectionSchemaFromOutputType(fieldDefinition.type);
}

function rejectDeprecatedPublicFieldName(
  fieldName: string,
  createValidationError: ValidationErrorFactory,
): never {
  if (fieldName === "likedPosts") {
    throw createValidationError(
      "Public GraphQL field 'likedPosts' is not part of the current stable x-gateway contract. Stable liked-post lookup is deferred until a reviewed live adapter route is verified.",
    );
  }
  if (fieldName === "likes") {
    throw createValidationError(
      "Public GraphQL field 'likes' is not part of the current stable x-gateway contract. Stable liked-post lookup is deferred until a reviewed live adapter route is verified.",
    );
  }

  throw createValidationError(
    `Public GraphQL field '${fieldName}' is not part of the stable x-gateway contract.`,
  );
}

function readStringLiteral(
  args: Readonly<Record<string, PublicGraphqlValue>>,
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

function rejectUnexpectedArguments(
  fieldName: string,
  args: Readonly<Record<string, PublicGraphqlValue>>,
  allowedArgumentNames: readonly string[],
  createValidationError: ValidationErrorFactory,
): void {
  const allowed = new Set(allowedArgumentNames);
  const unexpectedArgumentName = Object.keys(args).find(
    (name) => !allowed.has(name),
  );
  if (unexpectedArgumentName) {
    throw createValidationError(
      `Public GraphQL field '${fieldName}' does not accept argument '${unexpectedArgumentName}'. Supported arguments: ${allowedArgumentNames.join(", ") || "(none)"}.`,
    );
  }
}

function rejectDeprecatedMutationArgumentName(
  fieldName: string,
  args: Readonly<Record<string, PublicGraphqlValue>>,
  expectedName: string,
  createValidationError: ValidationErrorFactory,
): void {
  if ("id" in args && expectedName !== "id") {
    throw createValidationError(
      `Public GraphQL field '${fieldName}' uses '${expectedName}' instead of 'id'. Update the request to ${fieldName}(${expectedName}: "...").`,
    );
  }
}

function readAttachmentObject(
  value: PublicGraphqlValue,
  argumentName: string,
  index: number,
  createValidationError: ValidationErrorFactory,
): XGatewayPostAttachmentInput {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw createValidationError(
      `Public GraphQL argument '${argumentName}[${index}]' must be an object literal with kind, filePath, and optional altText.`,
    );
  }
  const objectValue = value as Record<string, PublicGraphqlValue>;
  const allowedKeys = new Set(["kind", "filePath", "altText"]);
  for (const key of Object.keys(objectValue)) {
    if (!allowedKeys.has(key)) {
      throw createValidationError(
        `Public GraphQL argument '${argumentName}[${index}]' does not accept field '${key}'. Supported fields: kind, filePath, altText.`,
      );
    }
  }
  const kind = objectValue["kind"];
  if (kind !== "image") {
    throw createValidationError(
      `Public GraphQL argument '${argumentName}[${index}].kind' must be 'image' in the current reviewed posting slice.`,
    );
  }
  const filePath = objectValue["filePath"];
  if (typeof filePath !== "string" || filePath.trim().length === 0) {
    throw createValidationError(
      `Public GraphQL argument '${argumentName}[${index}].filePath' must be a non-empty string.`,
    );
  }
  const altText = objectValue["altText"];
  if (
    altText !== undefined &&
    (typeof altText !== "string" || altText.trim().length === 0)
  ) {
    throw createValidationError(
      `Public GraphQL argument '${argumentName}[${index}].altText' must be a non-empty string when provided.`,
    );
  }
  if (typeof altText === "string" && altText.length > 1000) {
    throw createValidationError(
      `Public GraphQL argument '${argumentName}[${index}].altText' must be between 1 and 1000 characters when provided.`,
    );
  }
  return {
    kind,
    filePath,
    ...(typeof altText === "string" ? { altText } : {}),
  };
}

function readOptionalAttachments(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  name: string,
  createValidationError: ValidationErrorFactory,
): readonly XGatewayPostAttachmentInput[] | undefined {
  const value = args[name];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (!Array.isArray(value) || value.length === 0 || value.length > 4) {
    throw createValidationError(
      `Public GraphQL argument '${name}' must be a list containing between 1 and 4 attachment objects.`,
    );
  }
  return value.map((item, index) =>
    readAttachmentObject(item, name, index, createValidationError),
  );
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

function validateSelectionsAgainstSchema(
  topLevelFieldName: string,
  selections: readonly PublicGraphqlSelection[],
  schema: PublicSelectionSchema,
  createValidationError: ValidationErrorFactory,
  selectionPath = topLevelFieldName,
): void {
  if (schema.kind === "scalar") {
    if (selections.length > 0) {
      throw createValidationError(
        `Public GraphQL selection '${selectionPath}' is scalar and cannot include nested fields.`,
      );
    }
    return;
  }

  if (selections.length === 0) {
    throw createValidationError(
      `Public GraphQL selection '${selectionPath}' must include a nested selection set.`,
    );
  }

  const objectSchema = schema.kind === "list" ? schema.item : schema;
  if (objectSchema.kind !== "object") {
    throw createValidationError(
      `Public GraphQL selection '${selectionPath}' resolved to an unsupported schema shape.`,
    );
  }

  for (const selection of selections) {
    const childSchema = objectSchema.fields[selection.name];
    const childPath = `${selectionPath}.${selection.name}`;
    if (!childSchema) {
      throw createValidationError(
        `Public GraphQL selection '${childPath}' is not part of the stable x-gateway contract.`,
      );
    }
    validateSelectionsAgainstSchema(
      topLevelFieldName,
      selection.selections,
      childSchema,
      createValidationError,
      childPath,
    );
  }
}

function createPublicApiFieldRegistry(
  createValidationError: ValidationErrorFactory,
  createPayloadError: PayloadErrorFactory,
): readonly PublicApiFieldDefinition[] {
  const accountMeAllowedArgumentNames = readSchemaFieldArgumentNames(
    "accountMe",
    "query",
  );
  const accountMeSelectionSchema = readSchemaFieldSelectionSchema(
    "accountMe",
    "query",
  );
  const postAllowedArgumentNames = readSchemaFieldArgumentNames(
    "post",
    "query",
  );
  const postSelectionSchema = readSchemaFieldSelectionSchema("post", "query");
  const createPostAllowedArgumentNames = readSchemaFieldArgumentNames(
    "createPost",
    "mutation",
  );
  const createPostSelectionSchema = readSchemaFieldSelectionSchema(
    "createPost",
    "mutation",
  );
  const deletePostAllowedArgumentNames = readSchemaFieldArgumentNames(
    "deletePost",
    "mutation",
  );
  const deletePostSelectionSchema = readSchemaFieldSelectionSchema(
    "deletePost",
    "mutation",
  );
  const replyToPostAllowedArgumentNames = readSchemaFieldArgumentNames(
    "replyToPost",
    "mutation",
  );
  const replyToPostSelectionSchema = readSchemaFieldSelectionSchema(
    "replyToPost",
    "mutation",
  );
  const quotePostAllowedArgumentNames = readSchemaFieldArgumentNames(
    "quotePost",
    "mutation",
  );
  const quotePostSelectionSchema = readSchemaFieldSelectionSchema(
    "quotePost",
    "mutation",
  );
  const repostPostAllowedArgumentNames = readSchemaFieldArgumentNames(
    "repostPost",
    "mutation",
  );
  const repostPostSelectionSchema = readSchemaFieldSelectionSchema(
    "repostPost",
    "mutation",
  );
  const unrepostPostAllowedArgumentNames = readSchemaFieldArgumentNames(
    "unrepostPost",
    "mutation",
  );
  const unrepostPostSelectionSchema = readSchemaFieldSelectionSchema(
    "unrepostPost",
    "mutation",
  );

  return [
    {
      fieldName: "accountMe",
      capabilityId: "account.me",
      operationType: "query",
      allowedArgumentNames: accountMeAllowedArgumentNames,
      selectionSchema: accountMeSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "accountMe",
          args,
          accountMeAllowedArgumentNames,
          createValidationError,
        );
        return undefined;
      },
      normalizeResult: (value) => value,
    },
    {
      fieldName: "post",
      capabilityId: "post.get",
      operationType: "query",
      allowedArgumentNames: postAllowedArgumentNames,
      selectionSchema: postSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "post",
          args,
          postAllowedArgumentNames,
          createValidationError,
        );
        return {
          postId: readStringLiteral(args, "id", createValidationError),
        };
      },
      normalizeResult: (value, fieldName) =>
        normalizePostLookupResult(value, fieldName, createPayloadError),
    },
    {
      fieldName: "createPost",
      capabilityId: "post.create",
      operationType: "mutation",
      allowedArgumentNames: createPostAllowedArgumentNames,
      selectionSchema: createPostSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "createPost",
          args,
          createPostAllowedArgumentNames,
          createValidationError,
        );
        return {
          text: readStringLiteral(args, "text", createValidationError),
          attachments: readOptionalAttachments(
            args,
            "attachments",
            createValidationError,
          ),
        };
      },
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
      allowedArgumentNames: deletePostAllowedArgumentNames,
      selectionSchema: deletePostSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectDeprecatedMutationArgumentName(
          "deletePost",
          args,
          "postId",
          createValidationError,
        );
        rejectUnexpectedArguments(
          "deletePost",
          args,
          deletePostAllowedArgumentNames,
          createValidationError,
        );
        return {
          postId: readStringLiteral(args, "postId", createValidationError),
        };
      },
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
      allowedArgumentNames: replyToPostAllowedArgumentNames,
      selectionSchema: replyToPostSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "replyToPost",
          args,
          replyToPostAllowedArgumentNames,
          createValidationError,
        );
        return {
          text: readStringLiteral(args, "text", createValidationError),
          replyToPostId: readStringLiteral(
            args,
            "replyToPostId",
            createValidationError,
          ),
          attachments: readOptionalAttachments(
            args,
            "attachments",
            createValidationError,
          ),
        };
      },
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
      allowedArgumentNames: quotePostAllowedArgumentNames,
      selectionSchema: quotePostSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "quotePost",
          args,
          quotePostAllowedArgumentNames,
          createValidationError,
        );
        return {
          text: readStringLiteral(args, "text", createValidationError),
          quotedPostId: readStringLiteral(
            args,
            "quotedPostId",
            createValidationError,
          ),
          attachments: readOptionalAttachments(
            args,
            "attachments",
            createValidationError,
          ),
        };
      },
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
      allowedArgumentNames: repostPostAllowedArgumentNames,
      selectionSchema: repostPostSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectDeprecatedMutationArgumentName(
          "repostPost",
          args,
          "postId",
          createValidationError,
        );
        rejectUnexpectedArguments(
          "repostPost",
          args,
          repostPostAllowedArgumentNames,
          createValidationError,
        );
        return {
          postId: readStringLiteral(args, "postId", createValidationError),
        };
      },
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
      allowedArgumentNames: unrepostPostAllowedArgumentNames,
      selectionSchema: unrepostPostSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectDeprecatedMutationArgumentName(
          "unrepostPost",
          args,
          "postId",
          createValidationError,
        );
        rejectUnexpectedArguments(
          "unrepostPost",
          args,
          unrepostPostAllowedArgumentNames,
          createValidationError,
        );
        return {
          postId: readStringLiteral(args, "postId", createValidationError),
        };
      },
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

    const schemaField = getPublicRootType(
      fieldDefinition.operationType,
    ).getFields()[fieldDefinition.fieldName];
    if (!schemaField) {
      throw new Error(
        `Public GraphQL schema is missing ${fieldDefinition.operationType} field '${fieldDefinition.fieldName}'.`,
      );
    }

    const schemaArgumentNames = schemaField.args.map(
      (argument) => argument.name,
    );
    if (
      schemaArgumentNames.length !==
        fieldDefinition.allowedArgumentNames.length ||
      schemaArgumentNames.some(
        (argumentName, index) =>
          argumentName !== fieldDefinition.allowedArgumentNames[index],
      )
    ) {
      throw new Error(
        `Public GraphQL field '${fieldDefinition.fieldName}' argument metadata is out of sync with the Yoga schema.`,
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
    rejectDeprecatedPublicFieldName(document.field.name, createValidationError);
  }

  if (document.operationType !== fieldDefinition.operationType) {
    throw createValidationError(
      `Public GraphQL field '${document.field.name}' is not valid for ${document.operationType}.`,
    );
  }

  validateSelectionsAgainstSchema(
    fieldDefinition.fieldName,
    document.field.selections,
    fieldDefinition.selectionSchema,
    createValidationError,
  );

  return {
    capabilityId: fieldDefinition.capabilityId,
    operationType: document.operationType,
    fieldName: document.field.name,
    arguments: document.field.arguments,
    selections: document.field.selections,
    selectionSchema: fieldDefinition.selectionSchema,
    buildCapabilityInput: fieldDefinition.buildCapabilityInput,
    normalizeResult: fieldDefinition.normalizeResult,
    ...(input.traceId === undefined ? {} : { traceId: input.traceId }),
  };
}

export function projectPublicSelection(
  value: unknown,
  selections: readonly PublicGraphqlSelection[],
  selectionPath: string,
  schema: PublicSelectionSchema,
  createPayloadError: PayloadErrorFactory,
): unknown {
  if (value === null || value === undefined) {
    if (schema.optional) {
      return value;
    }
    throw createPayloadError(
      selectionPath,
      `Projected selection '${selectionPath}' is required by the stable payload schema, but received ${value === null ? "null" : "undefined"}.`,
    );
  }

  if (schema.kind === "scalar") {
    if (selections.length > 0) {
      throw createPayloadError(
        selectionPath,
        `Projected selection '${selectionPath}' is scalar and cannot include nested fields.`,
      );
    }
    if (typeof value === "object") {
      throw createPayloadError(
        selectionPath,
        `Projected selection '${selectionPath}' expected a scalar payload, but received an object or list value.`,
      );
    }
    return value;
  }

  if (schema.kind === "list") {
    if (!Array.isArray(value)) {
      throw createPayloadError(
        selectionPath,
        `Projected selection '${selectionPath}' expected a list payload.`,
      );
    }
    return value.map((item, index) =>
      projectPublicSelection(
        item,
        selections,
        `${selectionPath}[${index}]`,
        schema.item,
        createPayloadError,
      ),
    );
  }

  if (selections.length === 0) {
    throw createPayloadError(
      selectionPath,
      `Projected selection '${selectionPath}' expected nested fields for an object payload.`,
    );
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw createPayloadError(
      selectionPath,
      `Projected selection '${selectionPath}' expected an object payload.`,
    );
  }

  const record = value as Record<string, unknown>;
  const projected: Record<string, unknown> = {};
  for (const selection of selections) {
    const childPath = `${selectionPath}.${selection.name}`;
    const childSchema = schema.fields[selection.name];
    if (!childSchema) {
      throw createPayloadError(
        selectionPath,
        `Projected selection '${childPath}' is not part of the stable payload schema.`,
      );
    }
    if (!(selection.name in record)) {
      if (childSchema.optional) {
        continue;
      }
      throw createPayloadError(
        selectionPath,
        `Projected selection '${childPath}' is missing from the stable payload.`,
      );
    }
    const selectedValue = record[selection.name];
    if (selectedValue === undefined && childSchema.optional) {
      continue;
    }
    projected[selection.name] = projectPublicSelection(
      selectedValue,
      selection.selections,
      childPath,
      childSchema,
      createPayloadError,
    );
  }
  return projected;
}
