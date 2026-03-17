import type { XGatewayPostAttachmentInput } from "./lib";

const POST_ATTACHMENT_KEYS = new Set(["kind", "filePath", "altText"]);
const MAX_POST_ATTACHMENTS = 4;

type PostAttachmentValidationMessages = Readonly<{
  invalidCollection: string;
  invalidItem: (index: number) => string;
  unexpectedField: (index: number, key: string) => string;
  invalidKind: (index: number) => string;
  invalidFilePath: (index: number) => string;
  invalidAltText: Readonly<{
    empty: (index: number) => string;
    tooLong: (index: number) => string;
  }>;
}>;

type PostAttachmentValidationOptions<TError> = Readonly<{
  createValidationError: (message: string) => TError;
  messages: PostAttachmentValidationMessages;
  allowNull?: boolean;
}>;

function isAttachmentRecord(
  value: unknown,
): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readValidatedPostAttachment<TError>(
  value: unknown,
  index: number,
  options: PostAttachmentValidationOptions<TError>,
): XGatewayPostAttachmentInput {
  if (!isAttachmentRecord(value)) {
    throw options.createValidationError(options.messages.invalidItem(index));
  }

  for (const key of Object.keys(value)) {
    if (!POST_ATTACHMENT_KEYS.has(key)) {
      throw options.createValidationError(
        options.messages.unexpectedField(index, key),
      );
    }
  }

  if (value["kind"] !== "image") {
    throw options.createValidationError(options.messages.invalidKind(index));
  }

  const filePath = value["filePath"];
  if (typeof filePath !== "string" || filePath.trim().length === 0) {
    throw options.createValidationError(
      options.messages.invalidFilePath(index),
    );
  }

  const altText = value["altText"];
  if (
    altText !== undefined &&
    (typeof altText !== "string" || altText.trim().length === 0)
  ) {
    throw options.createValidationError(
      options.messages.invalidAltText.empty(index),
    );
  }
  if (typeof altText === "string" && altText.length > 1000) {
    throw options.createValidationError(
      options.messages.invalidAltText.tooLong(index),
    );
  }

  return {
    kind: "image",
    filePath,
    ...(typeof altText === "string" ? { altText } : {}),
  };
}

export function validatePostAttachments<TError>(
  value: unknown,
  options: PostAttachmentValidationOptions<TError>,
): readonly XGatewayPostAttachmentInput[] | undefined {
  if (value === undefined || (options.allowNull === true && value === null)) {
    return undefined;
  }
  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    value.length > MAX_POST_ATTACHMENTS
  ) {
    throw options.createValidationError(options.messages.invalidCollection);
  }

  return value.map((attachment, index) =>
    readValidatedPostAttachment(attachment, index, options),
  );
}
