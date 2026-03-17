export type CapabilityStatus =
  | "implemented"
  | "planned"
  | "blocked_by_scope"
  | "blocked_by_plan"
  | "unsupported";

export type CapabilityTransportStrategy =
  | "rest-v1"
  | "rest-v2"
  | "graphql-web"
  | "hybrid";

export type CapabilitySurfaceCategory =
  | "stable-contract"
  | "escape-hatch"
  | "deferred";

export type XGatewayCapabilityAccessType = "read" | "write" | "read-write";

export type CapabilityDescriptor = Readonly<{
  id: string;
  publicOperationName?: string;
  surfaceCategory: CapabilitySurfaceCategory;
  endpointFamily: string;
  operation: string;
  status: CapabilityStatus;
  accessType: XGatewayCapabilityAccessType;
  transportStrategy: CapabilityTransportStrategy;
  preferredTransport: CapabilityTransportStrategy;
  fallbackTransport?: CapabilityTransportStrategy;
  authModes: readonly ("bearer" | "oauth1")[];
  notes: string;
}>;

export type XGatewayCapabilityReadinessStatus =
  | "ready"
  | "conditional"
  | "blocked";

export type XGatewayCapabilityRequirement =
  | "configured-auth"
  | "oauth1"
  | "bearer"
  | "user-context-bearer";

export const STABLE_CAPABILITY_IDS = [
  "account.me",
  "post.get",
  "post.create",
  "post.delete",
  "post.reply",
  "post.quote",
  "post.repost",
  "post.unrepost",
] as const;

export type StableCapabilityId = (typeof STABLE_CAPABILITY_IDS)[number];

export type CapabilityRouteAdapterKind =
  | "graphql-request"
  | "read-capability"
  | "stable-posting";

export type CapabilityRouteDefinition = Readonly<{
  authMode: "oauth1" | "bearer";
  transport: CapabilityTransportStrategy;
  adapterKind: CapabilityRouteAdapterKind;
  readinessStatus?: XGatewayCapabilityReadinessStatus;
  readinessRequirement: XGatewayCapabilityRequirement;
  readinessReason: string;
}>;

export type CapabilityPlanningDefinition = Readonly<{
  capabilityId: "graphql.request" | StableCapabilityId;
  missingAuthRequirement: XGatewayCapabilityRequirement;
  missingAuthReason: string;
  unsupportedConfiguredAuthReason?: string;
  unsupportedConfiguredAuthRemediations?: readonly string[];
  routes: readonly CapabilityRouteDefinition[];
}>;

export function isStableCapabilityId(
  capabilityId: string,
): capabilityId is StableCapabilityId {
  return (STABLE_CAPABILITY_IDS as readonly string[]).includes(capabilityId);
}

type StablePostingCapabilityId = Exclude<
  StableCapabilityId,
  "account.me" | "post.get"
>;

type StablePostingCapabilityDescriptorInput = Readonly<{
  id: StablePostingCapabilityId;
  publicOperationName: string;
  operation: string;
  notes: string;
}>;

function createStablePostingCapabilityDescriptor(
  input: StablePostingCapabilityDescriptorInput,
): CapabilityDescriptor {
  return {
    id: input.id,
    publicOperationName: input.publicOperationName,
    surfaceCategory: "stable-contract",
    endpointFamily: "posts",
    operation: input.operation,
    status: "implemented",
    accessType: "write",
    transportStrategy: "rest-v2",
    preferredTransport: "rest-v2",
    authModes: ["oauth1"],
    notes: input.notes,
  };
}

const STABLE_POSTING_UNSUPPORTED_REMEDIATIONS = [
  "Configure OAuth1 credentials to use the stable posting capability.",
  "No reviewed bearer-mode stable fallback exists for this capability in the current release.",
  "Use 'graphql request' only if you are intentionally invoking a separate low-level upstream GraphQL workflow.",
] as const;

function createStablePostingPlanningDefinition(
  capabilityId: StablePostingCapabilityId,
  unsupportedConfiguredAuthReason: string,
): CapabilityPlanningDefinition {
  return {
    capabilityId,
    missingAuthRequirement: "oauth1",
    missingAuthReason: "Stable posting currently requires OAuth1 credentials.",
    unsupportedConfiguredAuthReason,
    unsupportedConfiguredAuthRemediations:
      STABLE_POSTING_UNSUPPORTED_REMEDIATIONS,
    routes: [
      {
        authMode: "oauth1",
        transport: "rest-v2",
        adapterKind: "stable-posting",
        readinessRequirement: "oauth1",
        readinessReason:
          "OAuth1 credentials are configured for the reviewed stable posting adapter.",
      },
    ],
  };
}

export const CAPABILITY_REGISTRY: readonly CapabilityDescriptor[] = [
  {
    id: "graphql.request",
    surfaceCategory: "escape-hatch",
    endpointFamily: "graphql",
    operation: "raw GraphQL query or mutation execution",
    status: "implemented",
    accessType: "read-write",
    transportStrategy: "graphql-web",
    preferredTransport: "graphql-web",
    authModes: ["bearer"],
    notes:
      "Low-level escape hatch for explicit GraphQL execution. Requires operationName plus documentId or inline query, and bearer auth.",
  },
  {
    id: "account.me",
    publicOperationName: "accountMe",
    surfaceCategory: "stable-contract",
    endpointFamily: "account",
    operation: "fetch authenticated account profile",
    status: "implemented",
    accessType: "read",
    transportStrategy: "hybrid",
    preferredTransport: "rest-v1",
    fallbackTransport: "rest-v2",
    authModes: ["oauth1", "bearer"],
    notes:
      "Uses REST-backed identity adapters. OAuth1 is stable; bearer support depends on a user-context token rather than an app-only bearer.",
  },
  {
    id: "auth.verify",
    surfaceCategory: "stable-contract",
    endpointFamily: "auth",
    operation: "verify identity and access",
    status: "implemented",
    accessType: "read",
    transportStrategy: "hybrid",
    preferredTransport: "hybrid",
    authModes: ["bearer", "oauth1"],
    notes:
      "Local auth/config diagnostic command. Confirms resolved credential mode and transport readiness, not a full live upstream verification.",
  },
  {
    id: "post.get",
    publicOperationName: "post",
    surfaceCategory: "stable-contract",
    endpointFamily: "posts",
    operation: "fetch a post with referenced-post expansion",
    status: "implemented",
    accessType: "read",
    transportStrategy: "rest-v2",
    preferredTransport: "rest-v2",
    authModes: ["oauth1", "bearer"],
    notes:
      "Stable lookup baseline uses the public post-lookup API with author and referenced-post expansion. Supports OAuth1 and bearer-token reads when the upstream token can read posts.",
  },
  createStablePostingCapabilityDescriptor({
    id: "post.create",
    publicOperationName: "createPost",
    operation: "create post with text and optional image attachments",
    notes:
      "Stable baseline is OAuth1-backed posting through the public REST API. The reviewed slice supports text posts plus up to four inline image attachments with optional alt text. Bearer-token posting is deferred until a reviewed user-context auth flow exists.",
  }),
  createStablePostingCapabilityDescriptor({
    id: "post.delete",
    publicOperationName: "deletePost",
    operation: "delete an existing post",
    notes:
      "Stable baseline is OAuth1-backed post deletion through the public REST API. Bearer-token deletion is deferred until a reviewed user-context auth flow exists.",
  }),
  createStablePostingCapabilityDescriptor({
    id: "post.reply",
    publicOperationName: "replyToPost",
    operation: "reply to a post with text and optional image attachments",
    notes:
      "Stable baseline is OAuth1-backed reply posting through the public REST API. The reviewed slice supports text replies plus up to four inline image attachments with optional alt text. Bearer-token posting is deferred until a reviewed user-context auth flow exists.",
  }),
  createStablePostingCapabilityDescriptor({
    id: "post.quote",
    publicOperationName: "quotePost",
    operation: "quote a post with text and optional image attachments",
    notes:
      "Stable baseline is OAuth1-backed quote posting through the public REST API. The reviewed slice supports text quotes plus up to four inline image attachments with optional alt text. Bearer-token posting is deferred until a reviewed user-context auth flow exists.",
  }),
  createStablePostingCapabilityDescriptor({
    id: "post.repost",
    publicOperationName: "repostPost",
    operation: "repost an existing post",
    notes:
      "Stable baseline is OAuth1-backed reposting through the public REST API. Bearer-token reposting is deferred until a reviewed user-context auth flow exists.",
  }),
  createStablePostingCapabilityDescriptor({
    id: "post.unrepost",
    publicOperationName: "unrepostPost",
    operation: "undo a repost",
    notes:
      "Stable baseline is OAuth1-backed repost removal through the public REST API. Bearer-token repost removal is deferred until a reviewed user-context auth flow exists.",
  }),
  {
    id: "likes.list",
    surfaceCategory: "deferred",
    endpointFamily: "likes",
    operation: "list liked posts for a user",
    status: "blocked_by_plan",
    accessType: "read",
    transportStrategy: "rest-v2",
    preferredTransport: "rest-v2",
    authModes: ["oauth1"],
    notes:
      "Deferred until a reviewed live route is verified. The previously attempted OAuth1 REST adapter currently fails with upstream HTTP 400 in real CLI usage, so likes are intentionally removed from the stable CLI, SDK, and project-owned GraphQL contract until the adapter contract is corrected.",
  },
  {
    id: "post.article",
    surfaceCategory: "deferred",
    endpointFamily: "posts",
    operation: "long-form article style post",
    status: "blocked_by_scope",
    accessType: "write",
    transportStrategy: "hybrid",
    preferredTransport: "hybrid",
    authModes: ["bearer", "oauth1"],
    notes:
      "Depends on provider-level article availability; strict mode can block.",
  },
  {
    id: "media.upload",
    surfaceCategory: "deferred",
    endpointFamily: "media",
    operation: "standalone media upload and alt-text management",
    status: "blocked_by_plan",
    accessType: "write",
    transportStrategy: "rest-v1",
    preferredTransport: "rest-v1",
    authModes: ["oauth1"],
    notes:
      "No standalone reviewed upload capability is exposed in the current release. Image upload plus optional alt text exists only as an internal OAuth1-backed helper behind the stable create/reply/quote post mutations.",
  },
  {
    id: "tweet.references",
    surfaceCategory: "deferred",
    endpointFamily: "tweets",
    operation: "thread, quote, likes, retweet user views",
    status: "blocked_by_plan",
    accessType: "read",
    transportStrategy: "hybrid",
    preferredTransport: "rest-v2",
    fallbackTransport: "graphql-web",
    authModes: ["bearer", "oauth1"],
    notes:
      "Foundational referenced-post expansion is available through 'post.get', but broader thread, likes, and retweet-user views remain deferred.",
  },
  {
    id: "timeline.search",
    surfaceCategory: "deferred",
    endpointFamily: "timelines",
    operation: "home/user/mentions/recent search with pagination",
    status: "blocked_by_plan",
    accessType: "read",
    transportStrategy: "hybrid",
    preferredTransport: "rest-v2",
    fallbackTransport: "graphql-web",
    authModes: ["bearer", "oauth1"],
    notes:
      "Deferred until a reviewed timeline/search adapter contract is implemented. Raw GraphQL remains available as a low-level fallback for explicitly mapped operations.",
  },
  {
    id: "social.follows",
    surfaceCategory: "deferred",
    endpointFamily: "social-graph",
    operation: "followers/following and follow/unfollow mutations",
    status: "blocked_by_plan",
    accessType: "read-write",
    transportStrategy: "hybrid",
    preferredTransport: "rest-v2",
    fallbackTransport: "graphql-web",
    authModes: ["bearer", "oauth1"],
    notes:
      "Deferred until reviewed follow-graph adapters are implemented. Raw GraphQL remains available as a low-level fallback for explicitly mapped operations.",
  },
  {
    id: "dm.core",
    surfaceCategory: "deferred",
    endpointFamily: "dm",
    operation: "send/list direct messages",
    status: "blocked_by_scope",
    accessType: "read-write",
    transportStrategy: "hybrid",
    preferredTransport: "hybrid",
    authModes: ["oauth1", "bearer"],
    notes: "Availability varies by auth mode and API tier.",
  },
];

export const CAPABILITY_PLANNING_REGISTRY: readonly CapabilityPlanningDefinition[] =
  [
    {
      capabilityId: "graphql.request",
      missingAuthRequirement: "bearer",
      missingAuthReason: "Raw GraphQL requests require a bearer token.",
      routes: [
        {
          authMode: "bearer",
          transport: "graphql-web",
          adapterKind: "graphql-request",
          readinessRequirement: "bearer",
          readinessReason:
            "Bearer auth is configured for low-level GraphQL requests.",
        },
      ],
    },
    {
      capabilityId: "account.me",
      missingAuthRequirement: "configured-auth",
      missingAuthReason:
        "Account identity lookup requires OAuth1 credentials or a user-context bearer token.",
      routes: [
        {
          authMode: "oauth1",
          transport: "rest-v1",
          adapterKind: "read-capability",
          readinessRequirement: "configured-auth",
          readinessReason:
            "OAuth1 credentials are configured for the reviewed identity adapter.",
        },
        {
          authMode: "bearer",
          transport: "rest-v2",
          adapterKind: "read-capability",
          readinessStatus: "conditional",
          readinessRequirement: "user-context-bearer",
          readinessReason:
            "Bearer auth is configured, but account identity lookup requires a user-context bearer token to succeed live.",
        },
      ],
    },
    {
      capabilityId: "post.get",
      missingAuthRequirement: "configured-auth",
      missingAuthReason:
        "Stable post lookup requires OAuth1 credentials or a bearer token.",
      routes: [
        {
          authMode: "oauth1",
          transport: "rest-v2",
          adapterKind: "read-capability",
          readinessRequirement: "configured-auth",
          readinessReason:
            "OAuth1 credentials are configured for the preferred stable read adapter.",
        },
        {
          authMode: "bearer",
          transport: "rest-v2",
          adapterKind: "read-capability",
          readinessRequirement: "bearer",
          readinessReason:
            "Bearer auth is configured for the reviewed REST-backed post lookup adapter.",
        },
      ],
    },
    createStablePostingPlanningDefinition(
      "post.create",
      "Stable 'post create' currently supports OAuth1 credentials only. Bearer-token posting is not a reviewed adapter path in this repository state.",
    ),
    createStablePostingPlanningDefinition(
      "post.delete",
      "Stable 'post delete' currently supports OAuth1 credentials only. Bearer-token deletion is not a reviewed adapter path in this repository state.",
    ),
    createStablePostingPlanningDefinition(
      "post.reply",
      "Stable 'post reply' currently supports OAuth1 credentials only. Bearer-token posting is not a reviewed adapter path in this repository state.",
    ),
    createStablePostingPlanningDefinition(
      "post.quote",
      "Stable 'post quote' currently supports OAuth1 credentials only. Bearer-token posting is not a reviewed adapter path in this repository state.",
    ),
    createStablePostingPlanningDefinition(
      "post.repost",
      "Stable 'post repost' currently supports OAuth1 credentials only. Bearer-token reposting is not a reviewed adapter path in this repository state.",
    ),
    createStablePostingPlanningDefinition(
      "post.unrepost",
      "Stable 'post unrepost' currently supports OAuth1 credentials only. Bearer-token repost removal is not a reviewed adapter path in this repository state.",
    ),
  ];
