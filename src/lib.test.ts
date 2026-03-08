import { afterEach, describe, expect, test, vi } from "vitest";
import { executeCli } from "./cli";
import {
  computeBackoffDelayMs,
  createXGatewayClient,
  normalizeError,
  resolveConfig,
  XGatewayError,
} from "./lib";

const ENV_KEYS = [
  "X_GW_TOKEN",
  "X_GW_CONSUMER_KEY",
  "X_GW_CONSUMER_SECRET",
  "X_GW_ACCESS_TOKEN",
  "X_GW_ACCESS_TOKEN_SECRET",
  "X_GW_TIMEOUT_MS",
  "X_GW_RETRY",
  "X_GW_RETRY_BACKOFF",
  "X_GW_RETRY_BASE_MS",
  "X_GW_RETRY_MAX_MS",
  "X_GW_GRAPHQL_BASE_URL",
  "X_GW_AUTH_MODE",
  "X_GW_OUTPUT",
  "X_GW_STRICT_CAPABILITY_CHECKS",
] as const;

const ORIGINAL_FETCH = globalThis.fetch;

afterEach(() => {
  for (const key of ENV_KEYS) {
    delete process.env[key];
  }
  vi.restoreAllMocks();
  globalThis.fetch = ORIGINAL_FETCH;
});

describe("resolveConfig", () => {
  test("uses X_GW_ env vars when parameters are omitted", () => {
    process.env["X_GW_TOKEN"] = "env-token";
    process.env["X_GW_TIMEOUT_MS"] = "45000";
    process.env["X_GW_RETRY"] = "3";
    process.env["X_GW_RETRY_BACKOFF"] = "fixed";
    process.env["X_GW_RETRY_BASE_MS"] = "200";
    process.env["X_GW_RETRY_MAX_MS"] = "5000";
    process.env["X_GW_GRAPHQL_BASE_URL"] = "https://example.com/graphql";

    const resolved = resolveConfig();

    expect(resolved.auth.token).toBe("env-token");
    expect(resolved.graphqlBaseUrl).toBe("https://example.com/graphql");
    expect(resolved.timeoutMs).toBe(45000);
    expect(resolved.retry.retries).toBe(3);
    expect(resolved.retry.backoff).toBe("fixed");
    expect(resolved.retry.baseDelayMs).toBe(200);
    expect(resolved.retry.maxDelayMs).toBe(5000);
  });

  test("prefers explicit parameters over env", () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const resolved = resolveConfig({
      auth: { token: "param-token" },
      graphqlBaseUrl: "https://override.example/graphql",
      retry: {
        retries: 5,
        backoff: "none",
        baseDelayMs: 1,
        maxDelayMs: 2,
      },
    });

    expect(resolved.auth.token).toBe("param-token");
    expect(resolved.graphqlBaseUrl).toBe("https://override.example/graphql");
    expect(resolved.retry.retries).toBe(5);
    expect(resolved.retry.backoff).toBe("none");
    expect(resolved.retry.baseDelayMs).toBe(1);
    expect(resolved.retry.maxDelayMs).toBe(2);
  });

  test("authMode env ignores auth parameters", () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const resolved = resolveConfig({
      authMode: "env",
      auth: { token: "param-token" },
    });

    expect(resolved.auth.token).toBe("env-token");
  });

  test("authMode params ignores env auth", () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const resolved = resolveConfig({
      authMode: "params",
      auth: { token: "param-token" },
    });

    expect(resolved.auth.token).toBe("param-token");
  });

  test("accepts zero retries from env", () => {
    process.env["X_GW_RETRY"] = "0";

    const resolved = resolveConfig();

    expect(resolved.retry.retries).toBe(0);
  });

  test("rejects malformed retry env values instead of truncating or falling back", () => {
    process.env["X_GW_RETRY"] = "1.5";

    expect(() => resolveConfig()).toThrowError(XGatewayError);
  });

  test("rejects invalid auth-mode env values instead of silently falling back", () => {
    process.env["X_GW_AUTH_MODE"] = "broken";

    expect(() => resolveConfig()).toThrowError(XGatewayError);
  });

  test("does not accept the removed X_GW_API_BASE_URL compatibility env", () => {
    process.env["X_GW_API_BASE_URL"] = "https://legacy.example/graphql";

    const resolved = resolveConfig();

    expect(resolved.graphqlBaseUrl).toBeUndefined();
  });
});

describe("computeBackoffDelayMs", () => {
  test("returns fixed delay for fixed strategy", () => {
    const delay = computeBackoffDelayMs(2, "fixed", 300, 1000, 0.5);
    expect(delay).toBe(300);
  });

  test("returns zero for none strategy", () => {
    const delay = computeBackoffDelayMs(5, "none", 300, 1000, 0.5);
    expect(delay).toBe(0);
  });

  test("caps exponential-jitter delay by max", () => {
    const delay = computeBackoffDelayMs(8, "exponential-jitter", 300, 1000, 0.99);
    expect(delay).toBeLessThanOrEqual(1000);
  });
});

describe("normalizeError", () => {
  test("maps network-ish error messages to NETWORK_FAILURE", () => {
    const error = normalizeError(new Error("fetch failed: timeout while connecting"));

    expect(error).toBeInstanceOf(XGatewayError);
    expect(error.payload.code).toBe("NETWORK_FAILURE");
    expect(error.payload.retryable).toBe(true);
  });

  test("returns INTERNAL_ERROR for unknown thrown values", () => {
    const error = normalizeError("unexpected");

    expect(error.payload.code).toBe("INTERNAL_ERROR");
  });
});

describe("createXGatewayClient", () => {
  test("allows capability inspection without configured auth", () => {
    const client = createXGatewayClient();

    expect(client.capabilitiesGet("graphql.request")).toMatchObject({
      id: "graphql.request",
      status: "implemented",
    });
  });

  test("reports auth readiness without throwing when auth is missing", async () => {
    const client = createXGatewayClient();

    await expect(client.authVerify()).resolves.toMatchObject({
      ready: false,
      authMode: "unconfigured",
      transport: "graphql-only",
    });
  });

  test("sends raw GraphQL requests through fetch", async () => {
    process.env["X_GW_TOKEN"] = "env-token";
    process.env["X_GW_GRAPHQL_BASE_URL"] = "https://example.com/graphql";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ data: { viewer: { id: "1" } } }), {
        status: 200,
        headers: {
          "content-type": "application/json",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    const client = createXGatewayClient();
    const result = await client.request<{ data: { viewer: { id: string } } }>({
      operationName: "Viewer",
      documentId: "doc-1",
      variables: { withSafetyModeUserFields: true },
    });

    expect(result.data.viewer.id).toBe("1");
    expect(fetchMock).toHaveBeenCalledWith(
      "https://example.com/graphql/doc-1/Viewer",
      expect.objectContaining({
        method: "POST",
      }),
    );
  });

  test("accepts GraphQL JSON media types with +json suffix", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ data: { viewer: { id: "2" } } }), {
        status: 200,
        headers: {
          "content-type": "application/graphql-response+json; charset=utf-8",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    const client = createXGatewayClient();
    const result = await client.request<{ data: { viewer: { id: string } } }>({
      operationName: "Viewer",
      documentId: "doc-2",
    });

    expect(result.data.viewer.id).toBe("2");
  });

  test("rejects GraphQL requests when only OAuth1 credentials are configured", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.request({
        operationName: "Viewer",
        documentId: "doc-1",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("rejects GraphQL requests without documentId or query", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const client = createXGatewayClient();

    await expect(
      client.request({
        operationName: "Viewer",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects GraphQL requests when both documentId and query are provided", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const client = createXGatewayClient();

    await expect(
      client.request({
        operationName: "Viewer",
        documentId: "doc-1",
        query: "query Viewer { viewer { id } }",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("includes retry exhaustion context and retry-after metadata for retryable failures", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ error: "rate limited" }), {
        status: 429,
        headers: {
          "content-type": "application/json",
          "retry-after": "0",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    const client = createXGatewayClient({
      retry: {
        retries: 1,
        backoff: "fixed",
        baseDelayMs: 999,
        maxDelayMs: 999,
      },
      timeoutMs: 5_000,
    });

    await expect(
      client.request({
        operationName: "Viewer",
        documentId: "doc-1",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "RATE_LIMITED",
        attempts: 2,
        retryAfterMs: 0,
        details: expect.stringContaining("Retry policy exhausted"),
      }),
    });
  });

  test("exposes the GraphQL-first stable SDK surface", () => {
    const client = createXGatewayClient();

    expect("request" in client).toBe(true);
    expect("capabilitiesList" in client).toBe(true);
    expect("postCreate" in client).toBe(false);
  });
});

describe("executeCli", () => {
  test("rejects deferred legacy command groups at the CLI boundary", async () => {
    await expect(
      executeCli(["tweet", "get", "--tweet-id", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("rejects unknown command groups as validation errors", async () => {
    await expect(
      executeCli(["twet", "get", "--tweet-id", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects invalid auth-mode values", async () => {
    await expect(
      executeCli(["capabilities", "list", "--auth-mode", "broken"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects malformed numeric flags instead of truncating them", async () => {
    await expect(
      executeCli(["capabilities", "list", "--retry", "1.5"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects bare required string flags instead of treating them as true", async () => {
    await expect(
      executeCli(
        ["graphql", "request", "--operation-name", "--document-id", "doc-1"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --operation-name requires a value"),
      }),
    });
  });

  test("rejects bare numeric flags instead of coercing them to true", async () => {
    await expect(
      executeCli(
        ["graphql", "request", "--operation-name", "Viewer", "--document-id", "doc-1", "--retry"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --retry requires a value"),
      }),
    });
  });

  test("rejects mutation GraphQL requests in reader mode", async () => {
    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-type",
          "mutation",
          "--operation-name",
          "CreatePost",
          "--document-id",
          "doc-1",
        ],
        {
          commandName: "x-gateway-reader",
          surface: "reader",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("honors X_GW_AUTH_MODE from env when CLI flags omit auth-mode", async () => {
    process.env["X_GW_AUTH_MODE"] = "params";
    process.env["X_GW_TOKEN"] = "env-token";

    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "AUTH_MISSING",
      }),
    });
  });

  test("honors retry env settings when CLI flags omit retry controls", async () => {
    process.env["X_GW_TOKEN"] = "env-token";
    process.env["X_GW_RETRY"] = "1";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ error: "rate limited" }), {
        status: 429,
        headers: {
          "content-type": "application/json",
          "retry-after": "0",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "RATE_LIMITED",
        attempts: 2,
      }),
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  test("accepts --graphql-base-url as the GraphQL-only endpoint override", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ data: { viewer: { id: "1" } } }), {
        status: 200,
        headers: {
          "content-type": "application/json",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
          "--graphql-base-url",
          "https://cli.example/graphql",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toMatchObject({
      data: {
        viewer: {
          id: "1",
        },
      },
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "https://cli.example/graphql/doc-1/Viewer",
      expect.any(Object),
    );
  });

  test("validates bare global trace-id flags through the normal CLI error path", async () => {
    await expect(
      executeCli(["health", "--trace-id"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --trace-id requires a value"),
      }),
    });
  });

  test("rejects deprecated api-base flag aliases instead of silently accepting them", async () => {
    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
          "--api-base-url",
          "https://legacy.example/graphql",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --api-base-url is no longer supported"),
      }),
    });
  });

  test("validates global retry flags even for local-only commands", async () => {
    await expect(
      executeCli(["health", "--retry", "1.5"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --retry must be an integer"),
      }),
    });
  });

  test("rejects unknown flags instead of ignoring them", async () => {
    await expect(
      executeCli(["health", "--mystery-flag", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Unknown flag --mystery-flag"),
      }),
    });
  });
});
