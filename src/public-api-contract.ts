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
import { validatePostAttachments } from "./post-attachments";

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

function readTrimmedStringLiteral(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  name: string,
  createValidationError: ValidationErrorFactory,
): string {
  return readStringLiteral(args, name, createValidationError).trim();
}

function readOptionalIntegerLiteral(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  name: string,
  createValidationError: ValidationErrorFactory,
): number | undefined {
  const value = args[name];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw createValidationError(
      `Public GraphQL argument '${name}' must be an integer when provided.`,
    );
  }
  return value;
}

function readOptionalBooleanLiteral(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  name: string,
  createValidationError: ValidationErrorFactory,
): boolean | undefined {
  const value = args[name];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "boolean") {
    throw createValidationError(
      `Public GraphQL argument '${name}' must be a boolean when provided.`,
    );
  }
  return value;
}

function readOptionalTrimmedStringLiteral(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  name: string,
  createValidationError: ValidationErrorFactory,
): string | undefined {
  return args[name] === undefined
    ? undefined
    : readTrimmedStringLiteral(args, name, createValidationError);
}

function readOptionalPostReadArguments(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  createValidationError: ValidationErrorFactory,
): Readonly<{
  mediaRootDir?: string;
  downloadMedia?: boolean;
  forceDownload?: boolean;
  includePromoted?: boolean;
}> {
  const mediaRootDir =
    args["mediaRootDir"] === undefined
      ? undefined
      : readTrimmedStringLiteral(args, "mediaRootDir", createValidationError);
  const downloadMedia = readOptionalBooleanLiteral(
    args,
    "downloadMedia",
    createValidationError,
  );
  const forceDownload = readOptionalBooleanLiteral(
    args,
    "forceDownload",
    createValidationError,
  );
  const includePromoted = readOptionalBooleanLiteral(
    args,
    "includePromoted",
    createValidationError,
  );
  return {
    ...(mediaRootDir === undefined ? {} : { mediaRootDir }),
    ...(downloadMedia === undefined ? {} : { downloadMedia }),
    ...(forceDownload === undefined ? {} : { forceDownload }),
    ...(includePromoted === undefined ? {} : { includePromoted }),
  };
}

function readOptionalPostPageArguments(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  createValidationError: ValidationErrorFactory,
): Readonly<{
  maxResults?: number;
  paginationToken?: string;
  mediaRootDir?: string;
  downloadMedia?: boolean;
  forceDownload?: boolean;
  includePromoted?: boolean;
}> {
  const maxResults = readOptionalIntegerLiteral(
    args,
    "maxResults",
    createValidationError,
  );
  const paginationToken = readOptionalTrimmedStringLiteral(
    args,
    "paginationToken",
    createValidationError,
  );
  return {
    ...readOptionalPostReadArguments(args, createValidationError),
    ...(maxResults === undefined ? {} : { maxResults }),
    ...(paginationToken === undefined ? {} : { paginationToken }),
  };
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

function readOptionalAttachments(
  args: Readonly<Record<string, PublicGraphqlValue>>,
  name: string,
  createValidationError: ValidationErrorFactory,
): readonly XGatewayPostAttachmentInput[] | undefined {
  return validatePostAttachments(args[name], {
    createValidationError,
    allowNull: true,
    messages: {
      invalidCollection: `Public GraphQL argument '${name}' must be a list containing between 1 and 4 attachment objects.`,
      invalidItem: (index) =>
        `Public GraphQL argument '${name}[${index}]' must be an object literal with kind, filePath, and optional altText.`,
      unexpectedField: (index, key) =>
        `Public GraphQL argument '${name}[${index}]' does not accept field '${key}'. Supported fields: kind, filePath, altText.`,
      invalidKind: (index) =>
        `Public GraphQL argument '${name}[${index}].kind' must be 'image' in the current reviewed posting slice.`,
      invalidFilePath: (index) =>
        `Public GraphQL argument '${name}[${index}].filePath' must be a non-empty string.`,
      invalidAltText: {
        empty: (index) =>
          `Public GraphQL argument '${name}[${index}].altText' must be a non-empty string when provided.`,
        tooLong: (index) =>
          `Public GraphQL argument '${name}[${index}].altText' must be between 1 and 1000 characters when provided.`,
      },
    },
  });
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

function normalizePostSummary(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  return readObjectRecord(
    value,
    fieldName,
    "The paginated post adapter returned a non-object post payload.",
    createPayloadError,
  );
}

function normalizePostPageResult(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  const result = readObjectRecord(
    value,
    fieldName,
    "The paginated post adapter did not return the expected { posts, pageInfo } shape.",
    createPayloadError,
  );
  const posts = readArrayValue(
    result["posts"],
    fieldName,
    "The paginated post adapter returned a non-array 'posts' payload.",
    createPayloadError,
  ).map((entry) => normalizePostSummary(entry, fieldName, createPayloadError));
  const pageInfo = readObjectRecord(
    result["pageInfo"],
    fieldName,
    "The paginated post adapter returned a non-object 'pageInfo' payload.",
    createPayloadError,
  );
  return {
    posts,
    pageInfo,
  };
}

function normalizeUsageDay(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  return readObjectRecord(
    value,
    fieldName,
    "The usage adapter returned a non-object usage-day payload.",
    createPayloadError,
  );
}

function normalizeUsageClientAppResult(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  const result = readObjectRecord(
    value,
    fieldName,
    "The usage adapter returned a non-object client-app usage payload.",
    createPayloadError,
  );
  const usage = readArrayValue(
    result["usage"],
    fieldName,
    "The usage adapter returned a non-array client-app 'usage' payload.",
    createPayloadError,
  ).map((entry) => normalizeUsageDay(entry, fieldName, createPayloadError));
  return {
    ...result,
    usage,
  };
}

function normalizeUsageProjectTimelineResult(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  const result = readObjectRecord(
    value,
    fieldName,
    "The usage adapter returned a non-object project usage payload.",
    createPayloadError,
  );
  const usage = readArrayValue(
    result["usage"],
    fieldName,
    "The usage adapter returned a non-array project 'usage' payload.",
    createPayloadError,
  ).map((entry) => normalizeUsageDay(entry, fieldName, createPayloadError));
  return {
    ...result,
    usage,
  };
}

function normalizePostUsageResult(
  value: unknown,
  fieldName: string,
  createPayloadError: PayloadErrorFactory,
): Readonly<Record<string, unknown>> {
  const result = readObjectRecord(
    value,
    fieldName,
    "The usage adapter did not return the expected usage payload shape.",
    createPayloadError,
  );
  const dailyClientAppUsage = readArrayValue(
    result["dailyClientAppUsage"],
    fieldName,
    "The usage adapter returned a non-array 'dailyClientAppUsage' payload.",
    createPayloadError,
  ).map((entry) =>
    normalizeUsageClientAppResult(entry, fieldName, createPayloadError),
  );
  const dailyProjectUsage = normalizeUsageProjectTimelineResult(
    result["dailyProjectUsage"],
    fieldName,
    createPayloadError,
  );
  return {
    ...result,
    dailyClientAppUsage,
    dailyProjectUsage,
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
  const postUsageAllowedArgumentNames = readSchemaFieldArgumentNames(
    "postUsage",
    "query",
  );
  const postUsageSelectionSchema = readSchemaFieldSelectionSchema(
    "postUsage",
    "query",
  );
  const postAllowedArgumentNames = readSchemaFieldArgumentNames(
    "post",
    "query",
  );
  const postSelectionSchema = readSchemaFieldSelectionSchema("post", "query");
  const searchPostsAllowedArgumentNames = readSchemaFieldArgumentNames(
    "searchPosts",
    "query",
  );
  const searchPostsSelectionSchema = readSchemaFieldSelectionSchema(
    "searchPosts",
    "query",
  );
  const homeTimelineAllowedArgumentNames = readSchemaFieldArgumentNames(
    "homeTimeline",
    "query",
  );
  const homeTimelineSelectionSchema = readSchemaFieldSelectionSchema(
    "homeTimeline",
    "query",
  );
  const userTimelineAllowedArgumentNames = readSchemaFieldArgumentNames(
    "userTimeline",
    "query",
  );
  const userTimelineSelectionSchema = readSchemaFieldSelectionSchema(
    "userTimeline",
    "query",
  );
  const mentionsTimelineAllowedArgumentNames = readSchemaFieldArgumentNames(
    "mentionsTimeline",
    "query",
  );
  const mentionsTimelineSelectionSchema = readSchemaFieldSelectionSchema(
    "mentionsTimeline",
    "query",
  );
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
      fieldName: "postUsage",
      capabilityId: "usage.tweets",
      operationType: "query",
      allowedArgumentNames: postUsageAllowedArgumentNames,
      selectionSchema: postUsageSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "postUsage",
          args,
          postUsageAllowedArgumentNames,
          createValidationError,
        );
        const days = readOptionalIntegerLiteral(
          args,
          "days",
          createValidationError,
        );
        return {
          ...(days === undefined ? {} : { days }),
        };
      },
      normalizeResult: (value, fieldName) =>
        normalizePostUsageResult(value, fieldName, createPayloadError),
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
          postId: readTrimmedStringLiteral(args, "id", createValidationError),
          ...readOptionalPostReadArguments(args, createValidationError),
        };
      },
      normalizeResult: (value, fieldName) =>
        normalizePostLookupResult(value, fieldName, createPayloadError),
    },
    {
      fieldName: "searchPosts",
      capabilityId: "timeline.search",
      operationType: "query",
      allowedArgumentNames: searchPostsAllowedArgumentNames,
      selectionSchema: searchPostsSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "searchPosts",
          args,
          searchPostsAllowedArgumentNames,
          createValidationError,
        );
        return {
          query: readTrimmedStringLiteral(args, "query", createValidationError),
          ...readOptionalPostPageArguments(args, createValidationError),
        };
      },
      normalizeResult: (value, fieldName) =>
        normalizePostPageResult(value, fieldName, createPayloadError),
    },
    {
      fieldName: "homeTimeline",
      capabilityId: "timeline.home",
      operationType: "query",
      allowedArgumentNames: homeTimelineAllowedArgumentNames,
      selectionSchema: homeTimelineSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "homeTimeline",
          args,
          homeTimelineAllowedArgumentNames,
          createValidationError,
        );
        return {
          ...readOptionalPostPageArguments(args, createValidationError),
        };
      },
      normalizeResult: (value, fieldName) =>
        normalizePostPageResult(value, fieldName, createPayloadError),
    },
    {
      fieldName: "userTimeline",
      capabilityId: "timeline.user",
      operationType: "query",
      allowedArgumentNames: userTimelineAllowedArgumentNames,
      selectionSchema: userTimelineSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "userTimeline",
          args,
          userTimelineAllowedArgumentNames,
          createValidationError,
        );
        return {
          userId: readTrimmedStringLiteral(
            args,
            "userId",
            createValidationError,
          ),
          ...readOptionalPostPageArguments(args, createValidationError),
        };
      },
      normalizeResult: (value, fieldName) =>
        normalizePostPageResult(value, fieldName, createPayloadError),
    },
    {
      fieldName: "mentionsTimeline",
      capabilityId: "timeline.mentions",
      operationType: "query",
      allowedArgumentNames: mentionsTimelineAllowedArgumentNames,
      selectionSchema: mentionsTimelineSelectionSchema,
      buildCapabilityInput: (args) => {
        rejectUnexpectedArguments(
          "mentionsTimeline",
          args,
          mentionsTimelineAllowedArgumentNames,
          createValidationError,
        );
        return {
          userId: readTrimmedStringLiteral(
            args,
            "userId",
            createValidationError,
          ),
          ...readOptionalPostPageArguments(args, createValidationError),
        };
      },
      normalizeResult: (value, fieldName) =>
        normalizePostPageResult(value, fieldName, createPayloadError),
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
