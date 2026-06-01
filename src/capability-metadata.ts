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

export type CapabilitySurfaceCategory = "stable-contract" | "deferred";

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
  "usage.tweets",
  "post.get",
  "post.replies",
  "timeline.search",
  "timeline.home",
  "timeline.following",
  "timeline.user",
  "timeline.mentions",
  "post.create",
  "post.delete",
  "post.reply",
  "post.quote",
  "post.repost",
  "post.unrepost",
] as const;

export type StableCapabilityId = (typeof STABLE_CAPABILITY_IDS)[number];

export type CapabilityRouteAdapterKind = "read-capability" | "stable-posting";

export type CapabilityRouteDefinition = Readonly<{
  authMode: "oauth1" | "bearer";
  transport: CapabilityTransportStrategy;
  adapterKind: CapabilityRouteAdapterKind;
  readinessStatus?: XGatewayCapabilityReadinessStatus;
  readinessRequirement: XGatewayCapabilityRequirement;
  readinessReason: string;
}>;

export type CapabilityPlanningDefinition = Readonly<{
  capabilityId: StableCapabilityId;
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
  | "account.me"
  | "post.get"
  | "timeline.search"
  | "timeline.home"
  | "timeline.following"
  | "timeline.user"
  | "timeline.mentions"
>;

type StableReadCapabilityId = Extract<
  StableCapabilityId,
  | "account.me"
  | "usage.tweets"
  | "post.get"
  | "post.replies"
  | "timeline.search"
  | "timeline.home"
  | "timeline.following"
  | "timeline.user"
  | "timeline.mentions"
>;

type StablePostingCapabilityDescriptorInput = Readonly<{
  id: StablePostingCapabilityId;
  publicOperationName: string;
  operation: string;
  notes: string;
}>;

type StableReadCapabilityDescriptorInput = Readonly<{
  id: StableReadCapabilityId;
  publicOperationName?: string;
  endpointFamily: string;
  operation: string;
  transportStrategy?: CapabilityTransportStrategy;
  preferredTransport?: CapabilityTransportStrategy;
  fallbackTransport?: CapabilityTransportStrategy;
  authModes?: readonly ("bearer" | "oauth1")[];
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

function createStableReadCapabilityDescriptor(
  input: StableReadCapabilityDescriptorInput,
): CapabilityDescriptor {
  return {
    id: input.id,
    ...(input.publicOperationName === undefined
      ? {}
      : { publicOperationName: input.publicOperationName }),
    surfaceCategory: "stable-contract",
    endpointFamily: input.endpointFamily,
    operation: input.operation,
    status: "implemented",
    accessType: "read",
    transportStrategy: input.transportStrategy ?? "rest-v2",
    preferredTransport: input.preferredTransport ?? "rest-v2",
    ...(input.fallbackTransport === undefined
      ? {}
      : { fallbackTransport: input.fallbackTransport }),
    authModes: input.authModes ?? ["oauth1", "bearer"],
    notes: input.notes,
  };
}

const STABLE_POSTING_UNSUPPORTED_REMEDIATIONS = [
  "Configure OAuth1 credentials to use the stable posting capability.",
  "No reviewed bearer-mode stable fallback exists for this capability in the current release.",
  "Use 'graphql query' only for reviewed project-owned GraphQL fields backed by stable capabilities.",
] as const;

type StableReadPlanningDefinitionInput = Readonly<{
  capabilityId: Exclude<StableReadCapabilityId, "account.me">;
  missingAuthReason: string;
  oauth1ReadinessReason: string;
  bearerReadinessRequirement?: XGatewayCapabilityRequirement;
  bearerReadinessStatus?: XGatewayCapabilityReadinessStatus;
  bearerReadinessReason: string;
  unsupportedConfiguredAuthReason?: string;
  unsupportedConfiguredAuthRemediations?: readonly string[];
}>;

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

function createStableReadPlanningDefinition(
  input: StableReadPlanningDefinitionInput,
): CapabilityPlanningDefinition {
  return {
    capabilityId: input.capabilityId,
    missingAuthRequirement: "configured-auth",
    missingAuthReason: input.missingAuthReason,
    ...(input.unsupportedConfiguredAuthReason === undefined
      ? {}
      : {
          unsupportedConfiguredAuthReason:
            input.unsupportedConfiguredAuthReason,
        }),
    ...(input.unsupportedConfiguredAuthRemediations === undefined
      ? {}
      : {
          unsupportedConfiguredAuthRemediations:
            input.unsupportedConfiguredAuthRemediations,
        }),
    routes: [
      {
        authMode: "oauth1",
        transport: "rest-v2",
        adapterKind: "read-capability",
        readinessRequirement: "configured-auth",
        readinessReason: input.oauth1ReadinessReason,
      },
      {
        authMode: "bearer",
        transport: "rest-v2",
        adapterKind: "read-capability",
        ...(input.bearerReadinessStatus === undefined
          ? {}
          : { readinessStatus: input.bearerReadinessStatus }),
        readinessRequirement: input.bearerReadinessRequirement ?? "bearer",
        readinessReason: input.bearerReadinessReason,
      },
    ],
  };
}

export const CAPABILITY_REGISTRY: readonly CapabilityDescriptor[] = [
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
  createStableReadCapabilityDescriptor({
    id: "usage.tweets",
    publicOperationName: "apiUsage",
    endpointFamily: "usage",
    operation: "fetch API usage counts",
    authModes: ["bearer"],
    notes:
      "Uses the REST v2 usage endpoint for API usage tracking. This capability intentionally avoids console-billing integration and returns usage counts and caps, not an exact current dollar cost.",
  }),
  createStableReadCapabilityDescriptor({
    id: "post.get",
    publicOperationName: "post",
    endpointFamily: "posts",
    operation: "fetch a post with referenced-post expansion",
    notes:
      "Stable lookup baseline uses the public post-lookup API with author and referenced-post expansion. Supports OAuth1 and bearer-token reads when the upstream token can read posts.",
  }),
  createStableReadCapabilityDescriptor({
    id: "post.replies",
    endpointFamily: "posts",
    operation: "fetch direct replies to a post with explicit pagination tokens",
    notes:
      "Stable direct-reply lookup uses the REST v2 recent-search endpoint with the in_reply_to_tweet_id operator. OAuth1 and bearer-token reads are both supported in the reviewed baseline.",
  }),
  createStableReadCapabilityDescriptor({
    id: "timeline.search",
    publicOperationName: "searchPosts",
    endpointFamily: "timelines",
    operation: "recent search with explicit pagination tokens",
    notes:
      "Stable recent-search baseline uses the REST v2 recent-search endpoint and returns explicit page metadata. OAuth1 and bearer-token reads are both supported.",
  }),
  createStableReadCapabilityDescriptor({
    id: "timeline.home",
    publicOperationName: "homeTimeline",
    endpointFamily: "timelines",
    operation: "home timeline with explicit pagination tokens",
    notes:
      "Stable home-timeline baseline uses the REST v2 reverse-chronological timeline endpoint. OAuth1 is reviewed; bearer auth may require a user-context token rather than an app-only bearer.",
  }),
  createStableReadCapabilityDescriptor({
    id: "timeline.following",
    publicOperationName: "followingTimeline",
    endpointFamily: "timelines",
    operation: "latest posts from followed accounts",
    notes:
      "Stable following-timeline baseline reads the authenticated account follow graph, then fetches recent user timelines for followed accounts and merges them by recency. OAuth1 is reviewed; bearer auth may require a user-context token.",
  }),
  createStableReadCapabilityDescriptor({
    id: "timeline.user",
    publicOperationName: "userTimeline",
    endpointFamily: "timelines",
    operation: "user timeline with explicit pagination tokens",
    notes:
      "Stable user-timeline baseline uses the REST v2 user-timeline endpoint and returns explicit page metadata for page-by-page traversal.",
  }),
  createStableReadCapabilityDescriptor({
    id: "timeline.mentions",
    publicOperationName: "mentionsTimeline",
    endpointFamily: "timelines",
    operation: "mentions timeline with explicit pagination tokens",
    notes:
      "Stable mentions-timeline baseline uses the REST v2 mentions endpoint and returns explicit page metadata. OAuth1 is reviewed; bearer auth may require a user-context token.",
  }),
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
      "Deferred until reviewed follow-graph adapters are implemented and exposed through the stable public contract.",
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
      capabilityId: "usage.tweets",
      missingAuthRequirement: "bearer",
      missingAuthReason:
        "Usage inspection requires a bearer token for the reviewed usage endpoint.",
      routes: [
        {
          authMode: "bearer",
          transport: "rest-v2",
          adapterKind: "read-capability",
          readinessRequirement: "bearer",
          readinessReason:
            "Bearer auth is configured for the reviewed usage endpoint adapter.",
        },
      ],
    },
    createStableReadPlanningDefinition({
      capabilityId: "post.get",
      missingAuthReason:
        "Stable post lookup requires OAuth1 credentials or a bearer token.",
      oauth1ReadinessReason:
        "OAuth1 credentials are configured for the preferred stable read adapter.",
      bearerReadinessReason:
        "Bearer auth is configured for the reviewed REST-backed post lookup adapter.",
    }),
    createStableReadPlanningDefinition({
      capabilityId: "post.replies",
      missingAuthReason:
        "Post replies lookup requires OAuth1 credentials or a bearer token.",
      oauth1ReadinessReason:
        "OAuth1 credentials are configured for the reviewed direct-reply search adapter.",
      bearerReadinessReason:
        "Bearer auth is configured for the reviewed direct-reply search adapter.",
    }),
    createStableReadPlanningDefinition({
      capabilityId: "timeline.search",
      missingAuthReason:
        "Recent search requires OAuth1 credentials or a bearer token.",
      oauth1ReadinessReason:
        "OAuth1 credentials are configured for the reviewed recent-search adapter.",
      bearerReadinessReason:
        "Bearer auth is configured for the reviewed recent-search adapter.",
    }),
    createStableReadPlanningDefinition({
      capabilityId: "timeline.home",
      missingAuthReason:
        "Home timeline requires OAuth1 credentials or a user-context bearer token.",
      oauth1ReadinessReason:
        "OAuth1 credentials are configured for the reviewed home-timeline adapter.",
      bearerReadinessRequirement: "user-context-bearer",
      bearerReadinessStatus: "conditional",
      bearerReadinessReason:
        "Bearer auth is configured, but home timeline requires a user-context bearer token to succeed live.",
    }),
    createStableReadPlanningDefinition({
      capabilityId: "timeline.following",
      missingAuthReason:
        "Following timeline requires OAuth1 credentials or a user-context bearer token.",
      oauth1ReadinessReason:
        "OAuth1 credentials are configured for the reviewed following timeline adapter.",
      bearerReadinessRequirement: "user-context-bearer",
      bearerReadinessStatus: "conditional",
      bearerReadinessReason:
        "Bearer auth is configured, but following timeline requires a user-context bearer token to read the follow graph live.",
    }),
    createStableReadPlanningDefinition({
      capabilityId: "timeline.user",
      missingAuthReason:
        "User timeline requires OAuth1 credentials or a bearer token.",
      oauth1ReadinessReason:
        "OAuth1 credentials are configured for the reviewed user-timeline adapter.",
      bearerReadinessReason:
        "Bearer auth is configured for the reviewed user-timeline adapter.",
    }),
    createStableReadPlanningDefinition({
      capabilityId: "timeline.mentions",
      missingAuthReason:
        "Mentions timeline requires OAuth1 credentials or a user-context bearer token.",
      oauth1ReadinessReason:
        "OAuth1 credentials are configured for the reviewed mentions-timeline adapter.",
      bearerReadinessRequirement: "user-context-bearer",
      bearerReadinessStatus: "conditional",
      bearerReadinessReason:
        "Bearer auth is configured, but mentions timeline requires a user-context bearer token to succeed live.",
    }),
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
