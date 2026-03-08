import { beforeEach, describe, expect, test, vi } from "vitest";
import { createCapabilityAdapterFactories } from "./capability-adapters";
import type { XGatewayErrorPayload } from "./lib";

describe("createCapabilityAdapterFactories", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  test("rejects non-oauth1 stable-posting adapter selection", () => {
    const factories = createCapabilityAdapterFactories({
      auth: {},
      createError: (payload: XGatewayErrorPayload) => {
        const error = new Error(payload.summary) as Error & {
          payload: XGatewayErrorPayload;
        };
        error.payload = payload;
        return error as never;
      },
      createValidationError: (message: string) => {
        const error = new Error(message) as Error & {
          payload: XGatewayErrorPayload;
        };
        error.payload = {
          code: "VALIDATION_ERROR",
          summary: "validation",
          details: message,
          likelyCauses: [],
          remediations: [],
          classification: "validation",
          retryable: false,
        };
        return error as never;
      },
      ensureRequired: (value: string | undefined, fieldName: string) => {
        if (!value) {
          throw new Error(`${fieldName} is required`);
        }
        return value;
      },
    });

    expect(() => factories.createStablePostingAdapter("bearer")).toThrowError(
      /Stable posting adapter auth mismatch/,
    );
  });
});
