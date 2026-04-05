import {
  Kind,
  parse,
  type FieldNode,
  type OperationTypeNode,
  type ValueNode,
} from "graphql";
import type { XGatewayOperationType } from "./lib";

export type PublicGraphqlLiteral = string | number | boolean | null;
export interface PublicGraphqlObjectValue {
  readonly [key: string]: PublicGraphqlValue;
}
export type PublicGraphqlValue =
  | PublicGraphqlLiteral
  | readonly PublicGraphqlValue[]
  | PublicGraphqlObjectValue;

export type PublicGraphqlSelection = Readonly<{
  name: string;
  arguments: Readonly<Record<string, PublicGraphqlValue>>;
  selections: readonly PublicGraphqlSelection[];
}>;

export type PublicGraphqlField = Readonly<{
  name: string;
  arguments: Readonly<Record<string, PublicGraphqlValue>>;
  selections: readonly PublicGraphqlSelection[];
}>;

export type PublicGraphqlDocument = Readonly<{
  operationType: XGatewayOperationType;
  field: PublicGraphqlField;
}>;

type ValidationErrorFactory = (message: string) => Error;

function ensureRequired(
  input: string,
  fieldName: string,
  createValidationError: ValidationErrorFactory,
): string {
  if (input.trim().length === 0) {
    throw createValidationError(`${fieldName} is required.`);
  }
  return input;
}

function rejectUnsupportedOperationType(
  operationType: OperationTypeNode,
  createValidationError: ValidationErrorFactory,
): XGatewayOperationType {
  if (operationType === "query" || operationType === "mutation") {
    return operationType;
  }
  throw createValidationError(
    "Public GraphQL only supports query and mutation operations in this implementation slice.",
  );
}

function parseValueNode(
  valueNode: ValueNode,
  createValidationError: ValidationErrorFactory,
): PublicGraphqlValue {
  switch (valueNode.kind) {
    case Kind.STRING:
      return valueNode.value;
    case Kind.INT:
      return Number.parseInt(valueNode.value, 10);
    case Kind.BOOLEAN:
      return valueNode.value;
    case Kind.NULL:
      return null;
    case Kind.LIST:
      return valueNode.values.map((item) =>
        parseValueNode(item, createValidationError),
      );
    case Kind.OBJECT: {
      const objectValue: Record<string, PublicGraphqlValue> = {};
      for (const field of valueNode.fields) {
        objectValue[field.name.value] = parseValueNode(
          field.value,
          createValidationError,
        );
      }
      return objectValue;
    }
    case Kind.VARIABLE:
      throw createValidationError(
        "Public GraphQL variables are not supported in this implementation slice. Inline literal arguments instead.",
      );
    default:
      throw createValidationError(
        "Public GraphQL arguments currently support string, integer, boolean, null, list, and object literals.",
      );
  }
}

function parseFieldNode(
  fieldNode: FieldNode,
  createValidationError: ValidationErrorFactory,
): PublicGraphqlSelection {
  if (fieldNode.alias) {
    throw createValidationError(
      `Public GraphQL aliases are not supported in this implementation slice. Remove the alias before field '${fieldNode.name.value}'.`,
    );
  }
  if ((fieldNode.directives?.length ?? 0) > 0) {
    throw createValidationError(
      "Public GraphQL directives are not supported in this implementation slice.",
    );
  }
  const fieldArguments: Record<string, PublicGraphqlValue> = {};
  for (const argument of fieldNode.arguments ?? []) {
    fieldArguments[argument.name.value] = parseValueNode(
      argument.value,
      createValidationError,
    );
  }
  const selections =
    fieldNode.selectionSet?.selections.map((selectionNode) => {
      if (selectionNode.kind !== Kind.FIELD) {
        throw createValidationError(
          "Public GraphQL fragments are not supported in this implementation slice.",
        );
      }
      return parseFieldNode(selectionNode, createValidationError);
    }) ?? [];
  return {
    name: fieldNode.name.value,
    arguments: fieldArguments,
    selections,
  };
}

export function parsePublicGraphqlDocument(
  input: string,
  createValidationError: ValidationErrorFactory,
): PublicGraphqlDocument {
  const normalizedInput = ensureRequired(input, "query", createValidationError);
  let parsedDocument;

  try {
    parsedDocument = parse(normalizedInput);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes('Expected "$", found "@".')) {
      throw createValidationError(
        "Public GraphQL directives are not supported in this implementation slice.",
      );
    }
    if (message.includes('Expected Name, found "...".')) {
      throw createValidationError(
        "Public GraphQL fragments are not supported in this implementation slice.",
      );
    }
    throw createValidationError(message.replace(/^Syntax Error: /, ""));
  }

  for (const definition of parsedDocument.definitions) {
    if (definition.kind !== Kind.OPERATION_DEFINITION) {
      throw createValidationError(
        "Public GraphQL fragments are not supported in this implementation slice.",
      );
    }
  }

  if (parsedDocument.definitions.length !== 1) {
    throw createValidationError(
      "Public GraphQL requests currently support exactly one top-level field.",
    );
  }

  const operation = parsedDocument.definitions[0];
  if (!operation || operation.kind !== Kind.OPERATION_DEFINITION) {
    throw createValidationError("Unexpected end of public GraphQL request.");
  }

  if (operation.name) {
    throw createValidationError(
      "Public GraphQL operation names are not supported in this implementation slice.",
    );
  }
  if (operation.variableDefinitions?.length) {
    throw createValidationError(
      "Public GraphQL variables are not supported in this implementation slice. Inline literal arguments instead.",
    );
  }
  if ((operation.directives?.length ?? 0) > 0) {
    throw createValidationError(
      "Public GraphQL directives are not supported in this implementation slice.",
    );
  }

  if (operation.selectionSet.selections.length !== 1) {
    throw createValidationError(
      "Public GraphQL requests currently support exactly one top-level field.",
    );
  }

  const topLevelSelectionNode = operation.selectionSet.selections[0];
  if (!topLevelSelectionNode || topLevelSelectionNode.kind !== Kind.FIELD) {
    throw createValidationError(
      "Public GraphQL fragments are not supported in this implementation slice.",
    );
  }
  const topLevelSelection = topLevelSelectionNode;
  if (topLevelSelection.alias) {
    throw createValidationError(
      `Public GraphQL aliases are not supported in this implementation slice. Remove the alias before field '${topLevelSelection.name.value}'.`,
    );
  }
  if ((topLevelSelection.directives?.length ?? 0) > 0) {
    throw createValidationError(
      "Public GraphQL directives are not supported in this implementation slice.",
    );
  }

  const fieldArguments: Record<string, PublicGraphqlValue> = {};
  for (const argument of topLevelSelection.arguments ?? []) {
    fieldArguments[argument.name.value] = parseValueNode(
      argument.value,
      createValidationError,
    );
  }

  const fieldSelections =
    topLevelSelection.selectionSet?.selections.map((selectionNode) => {
      if (selectionNode.kind !== Kind.FIELD) {
        throw createValidationError(
          "Public GraphQL fragments are not supported in this implementation slice.",
        );
      }
      return parseFieldNode(selectionNode, createValidationError);
    }) ?? [];

  if (fieldSelections.length === 0) {
    throw createValidationError(
      `Public GraphQL field '${topLevelSelection.name.value}' must include a selection set in this implementation slice.`,
    );
  }

  return {
    operationType: rejectUnsupportedOperationType(
      operation.operation,
      createValidationError,
    ),
    field: {
      name: topLevelSelection.name.value,
      arguments: fieldArguments,
      selections: fieldSelections,
    },
  };
}

export function inferPublicGraphqlOperationType(
  input: string,
  createValidationError: ValidationErrorFactory,
): XGatewayOperationType {
  return parsePublicGraphqlDocument(input, createValidationError).operationType;
}
