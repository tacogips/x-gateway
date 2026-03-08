import type { XGatewayOperationType } from "./lib";

export type PublicGraphqlLiteral = string | number | boolean | null;

export type PublicGraphqlSelection = Readonly<{
  name: string;
  selections: readonly PublicGraphqlSelection[];
}>;

export type PublicGraphqlField = Readonly<{
  name: string;
  arguments: Readonly<Record<string, PublicGraphqlLiteral>>;
  selections: readonly PublicGraphqlSelection[];
}>;

export type PublicGraphqlDocument = Readonly<{
  operationType: XGatewayOperationType;
  field: PublicGraphqlField;
}>;

type PublicGraphqlToken = Readonly<{
  type: "name" | "string" | "int" | "punct";
  value: string;
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

function tokenizePublicGraphqlDocument(
  input: string,
  createValidationError: ValidationErrorFactory,
): readonly PublicGraphqlToken[] {
  const tokens: PublicGraphqlToken[] = [];
  let index = 0;

  while (index < input.length) {
    const current = input[index];
    if (!current) {
      break;
    }
    if (/\s/.test(current)) {
      index += 1;
      continue;
    }
    if (current === "#") {
      while (index < input.length && input[index] !== "\n") {
        index += 1;
      }
      continue;
    }
    if ("{}():,".includes(current)) {
      tokens.push({ type: "punct", value: current });
      index += 1;
      continue;
    }
    if (current === '"') {
      let value = "";
      let terminated = false;
      index += 1;
      while (index < input.length) {
        const character = input[index];
        if (character === undefined) {
          break;
        }
        if (character === "\\") {
          const escaped = input[index + 1];
          if (escaped === undefined) {
            throw createValidationError(
              "Public GraphQL string literal ends with an incomplete escape sequence.",
            );
          }
          value += escaped === "n" ? "\n" : escaped === "t" ? "\t" : escaped;
          index += 2;
          continue;
        }
        if (character === '"') {
          terminated = true;
          index += 1;
          break;
        }
        value += character;
        index += 1;
      }
      if (!terminated) {
        throw createValidationError(
          "Public GraphQL string literal is unterminated.",
        );
      }
      tokens.push({ type: "string", value });
      continue;
    }
    if (/[0-9]/.test(current)) {
      let value = current;
      index += 1;
      while (index < input.length && /[0-9]/.test(input[index] ?? "")) {
        value += input[index];
        index += 1;
      }
      tokens.push({ type: "int", value });
      continue;
    }
    if (/[A-Za-z_]/.test(current)) {
      let value = current;
      index += 1;
      while (index < input.length && /[A-Za-z0-9_]/.test(input[index] ?? "")) {
        value += input[index];
        index += 1;
      }
      tokens.push({ type: "name", value });
      continue;
    }
    throw createValidationError(
      `Public GraphQL request contains unsupported character '${current}'.`,
    );
  }

  return tokens;
}

export function parsePublicGraphqlDocument(
  input: string,
  createValidationError: ValidationErrorFactory,
): PublicGraphqlDocument {
  const tokens = tokenizePublicGraphqlDocument(
    ensureRequired(input, "query", createValidationError),
    createValidationError,
  );
  let index = 0;

  function currentToken(): PublicGraphqlToken | undefined {
    return tokens[index];
  }

  function consumeToken(): PublicGraphqlToken {
    const token = currentToken();
    if (!token) {
      throw createValidationError("Unexpected end of public GraphQL request.");
    }
    index += 1;
    return token;
  }

  function consumePunct(expected: string): void {
    const token = consumeToken();
    if (token.type !== "punct" || token.value !== expected) {
      throw createValidationError(
        `Expected '${expected}' in public GraphQL request.`,
      );
    }
  }

  function consumeName(label: string): string {
    const token = consumeToken();
    if (token.type !== "name") {
      throw createValidationError(
        `Expected ${label} in public GraphQL request.`,
      );
    }
    return token.value;
  }

  function parseLiteral(): PublicGraphqlLiteral {
    const token = consumeToken();
    if (token.type === "string") {
      return token.value;
    }
    if (token.type === "int") {
      return Number.parseInt(token.value, 10);
    }
    if (token.type === "name") {
      if (token.value === "true") {
        return true;
      }
      if (token.value === "false") {
        return false;
      }
      if (token.value === "null") {
        return null;
      }
    }
    throw createValidationError(
      "Public GraphQL arguments currently support only string, integer, boolean, and null literals.",
    );
  }

  function parseArguments(): Readonly<Record<string, PublicGraphqlLiteral>> {
    if (currentToken()?.type !== "punct" || currentToken()?.value !== "(") {
      return {};
    }
    consumePunct("(");
    const args: Record<string, PublicGraphqlLiteral> = {};
    while (true) {
      const token = currentToken();
      if (!token) {
        throw createValidationError(
          "Unterminated argument list in public GraphQL request.",
        );
      }
      if (token.type === "punct" && token.value === ")") {
        consumePunct(")");
        return args;
      }
      const name = consumeName("argument name");
      consumePunct(":");
      args[name] = parseLiteral();
      if (currentToken()?.type === "punct" && currentToken()?.value === ",") {
        consumePunct(",");
      }
    }
  }

  function parseSelections(): readonly PublicGraphqlSelection[] {
    consumePunct("{");
    const selections: PublicGraphqlSelection[] = [];
    while (true) {
      const token = currentToken();
      if (!token) {
        throw createValidationError(
          "Unterminated selection set in public GraphQL request.",
        );
      }
      if (token.type === "punct" && token.value === "}") {
        consumePunct("}");
        return selections;
      }
      const name = consumeName("field name");
      const nestedSelections =
        currentToken()?.type === "punct" && currentToken()?.value === "{"
          ? parseSelections()
          : [];
      selections.push({
        name,
        selections: nestedSelections,
      });
    }
  }

  const firstToken = currentToken();
  const operationType =
    firstToken?.type === "name" &&
    (firstToken.value === "query" || firstToken.value === "mutation")
      ? (consumeToken().value as XGatewayOperationType)
      : "query";

  if (currentToken()?.type === "name" && tokens[index + 1]?.value === "{") {
    consumeToken();
  }

  consumePunct("{");
  const fieldName = consumeName("top-level field name");
  const fieldArguments = parseArguments();
  const fieldSelections =
    currentToken()?.type === "punct" && currentToken()?.value === "{"
      ? parseSelections()
      : [];
  consumePunct("}");

  if (currentToken() !== undefined) {
    throw createValidationError(
      "Public GraphQL requests currently support exactly one top-level field.",
    );
  }

  if (fieldSelections.length === 0) {
    throw createValidationError(
      `Public GraphQL field '${fieldName}' must include a selection set in this implementation slice.`,
    );
  }

  return {
    operationType,
    field: {
      name: fieldName,
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
