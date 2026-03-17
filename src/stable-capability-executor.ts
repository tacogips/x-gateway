import {
  CAPABILITY_PLANNING_REGISTRY,
  CAPABILITY_REGISTRY,
  isStableCapabilityId,
  type CapabilityDescriptor,
  type CapabilityPlanningDefinition,
  type StableCapabilityId,
} from "./capability-metadata";
import {
  planCapabilityExecution as createCapabilityExecutionPlan,
  type CapabilityExecutionContext,
  type CapabilityExecutionPlan,
  type ResolvedCapabilityAuth,
} from "./capability-runtime";
import type {
  XGatewayAccountProfile,
  XGatewayError,
  XGatewayPostPage,
  XGatewayPostCreateOptions,
  XGatewayPostDeleteOptions,
  XGatewayPostGetOptions,
  XGatewayPostLookupResult,
  XGatewayPostQuoteOptions,
  XGatewayPostReplyOptions,
  XGatewayPostRepostOptions,
  XGatewayTimelinePageOptions,
  XGatewayTimelineSearchOptions,
  XGatewayTimelineUserOptions,
} from "./lib";

export type XGatewayReadCapabilityAdapter = Readonly<{
  adapterKind: "rest-oauth1" | "rest-bearer";
  accountMe: () => Promise<XGatewayAccountProfile>;
  postGet: (
    options: XGatewayPostGetOptions,
  ) => Promise<XGatewayPostLookupResult>;
  timelineSearch: (
    options: XGatewayTimelineSearchOptions,
  ) => Promise<XGatewayPostPage>;
  timelineHome: (
    options: XGatewayTimelinePageOptions,
  ) => Promise<XGatewayPostPage>;
  timelineUser: (
    options: XGatewayTimelineUserOptions,
  ) => Promise<XGatewayPostPage>;
  timelineMentions: (
    options: XGatewayTimelineUserOptions,
  ) => Promise<XGatewayPostPage>;
}>;

export type XGatewayStablePostingAdapter = Readonly<{
  adapterKind: "rest-oauth1";
  postCreate: (options: XGatewayPostCreateOptions) => Promise<unknown>;
  postDelete: (options: XGatewayPostDeleteOptions) => Promise<unknown>;
  postReply: (options: XGatewayPostReplyOptions) => Promise<unknown>;
  postQuote: (options: XGatewayPostQuoteOptions) => Promise<unknown>;
  postRepost: (options: XGatewayPostRepostOptions) => Promise<unknown>;
  postUndoRepost: (options: XGatewayPostRepostOptions) => Promise<unknown>;
}>;

export type StableCapabilityInputById = Readonly<{
  "account.me": undefined;
  "post.get": XGatewayPostGetOptions;
  "timeline.search": XGatewayTimelineSearchOptions;
  "timeline.home": XGatewayTimelinePageOptions;
  "timeline.user": XGatewayTimelineUserOptions;
  "timeline.mentions": XGatewayTimelineUserOptions;
  "post.create": XGatewayPostCreateOptions;
  "post.delete": XGatewayPostDeleteOptions;
  "post.reply": XGatewayPostReplyOptions;
  "post.quote": XGatewayPostQuoteOptions;
  "post.repost": XGatewayPostRepostOptions;
  "post.unrepost": XGatewayPostRepostOptions;
}>;

export type StableCapabilityResultById = Readonly<{
  "account.me": XGatewayAccountProfile;
  "post.get": XGatewayPostLookupResult;
  "timeline.search": XGatewayPostPage;
  "timeline.home": XGatewayPostPage;
  "timeline.user": XGatewayPostPage;
  "timeline.mentions": XGatewayPostPage;
  "post.create": unknown;
  "post.delete": unknown;
  "post.reply": unknown;
  "post.quote": unknown;
  "post.repost": unknown;
  "post.unrepost": unknown;
}>;

type StableCapabilityExecutionDefinition<K extends StableCapabilityId> =
  Readonly<{
    capabilityLabel: string;
    plan: (
      input: StableCapabilityInputById[K],
      traceId?: string,
    ) => CapabilityExecutionPlan<StableCapabilityResultById[K]>;
  }>;

type StableCapabilityExecutionRegistry = Readonly<{
  [K in StableCapabilityId]: StableCapabilityExecutionDefinition<K>;
}>;

type TraceFactory = (traceId?: string) => Readonly<{ traceId?: string }>;

type StableCapabilityExecutorDependencies = Readonly<{
  auth: ResolvedCapabilityAuth;
  withOptionalTrace: TraceFactory;
  executeCapabilityOperation: <T>(
    context: CapabilityExecutionContext,
    operation: () => Promise<T>,
  ) => Promise<T>;
  adapters: Readonly<{
    createReadAdapter: (
      authMode: "oauth1" | "bearer",
    ) => XGatewayReadCapabilityAdapter;
    createStablePostingAdapter: (
      authMode: "oauth1" | "bearer",
    ) => XGatewayStablePostingAdapter;
  }>;
  errors: Readonly<{
    createCapabilityRegistryMissingError: (capabilityId: string) => XGatewayError;
    createCapabilityPlanningMissingError: (
      capabilityId: string,
    ) => XGatewayError;
    createConfiguredAuthUnsupportedError: (
      capabilityLabel: string,
      planning: CapabilityPlanningDefinition,
    ) => XGatewayError;
    createCapabilityAuthMissingError: (
      capability: CapabilityDescriptor,
      planning: CapabilityPlanningDefinition,
    ) => XGatewayError;
    createHandlerMissingError: (
      capabilityId: StableCapabilityId,
      adapterKind: "read-capability" | "stable-posting",
    ) => XGatewayError;
    createUnsupportedAdapterKindError: (
      capabilityId: StableCapabilityId,
      adapterKind: "graphql-request" | "read-capability" | "stable-posting",
    ) => XGatewayError;
  }>;
}>;

function assertStableCapabilityExecutionRegistryCoherent(
  registry: StableCapabilityExecutionRegistry,
): void {
  const implementedStableCapabilityIds = CAPABILITY_REGISTRY.filter(
    (capability): capability is CapabilityDescriptor & { id: StableCapabilityId } =>
      capability.status === "implemented" && isStableCapabilityId(capability.id),
  ).map((capability) => capability.id);
  const plannedStableCapabilityIds = CAPABILITY_PLANNING_REGISTRY.filter(
    (
      planning,
    ): planning is CapabilityPlanningDefinition & {
      capabilityId: StableCapabilityId;
    } => isStableCapabilityId(planning.capabilityId),
  ).map((planning) => planning.capabilityId);
  const executorCapabilityIds = Object.keys(registry) as StableCapabilityId[];

  const plannedStableCapabilityIdSet = new Set(plannedStableCapabilityIds);
  const executorCapabilityIdSet = new Set(executorCapabilityIds);
  const implementedStableCapabilityIdSet = new Set(implementedStableCapabilityIds);

  for (const capabilityId of implementedStableCapabilityIds) {
    if (!plannedStableCapabilityIdSet.has(capabilityId)) {
      throw new Error(
        `Stable capability '${capabilityId}' is marked implemented in capability metadata, but no planning route exists for it.`,
      );
    }
    if (!executorCapabilityIdSet.has(capabilityId)) {
      throw new Error(
        `Stable capability '${capabilityId}' is marked implemented in capability metadata, but no executor entry exists for it.`,
      );
    }
  }

  for (const capabilityId of executorCapabilityIds) {
    if (!implementedStableCapabilityIdSet.has(capabilityId)) {
      throw new Error(
        `Stable capability executor contains '${capabilityId}', but capability metadata does not mark it as an implemented stable capability.`,
      );
    }
    if (!plannedStableCapabilityIdSet.has(capabilityId)) {
      throw new Error(
        `Stable capability executor contains '${capabilityId}', but no planning route exists for it.`,
      );
    }
  }
}

export function createStableCapabilityExecutor(
  dependencies: StableCapabilityExecutorDependencies,
): Readonly<{
  executeStableCapability: <K extends StableCapabilityId>(
    capabilityId: K,
    input: StableCapabilityInputById[K],
    traceId?: string,
  ) => Promise<StableCapabilityResultById[K]>;
}> {
  function buildCapabilityExecutionPlan<T>(
    capabilityId: StableCapabilityId,
    capabilityLabel: string,
    handlers: Readonly<{
      read?:
        | ((adapter: XGatewayReadCapabilityAdapter) => Promise<T>)
        | undefined;
      stablePosting?:
        | ((adapter: XGatewayStablePostingAdapter) => Promise<T>)
        | undefined;
    }>,
    traceId?: string,
  ): CapabilityExecutionPlan<T> {
    return createCapabilityExecutionPlan<
      XGatewayReadCapabilityAdapter,
      XGatewayStablePostingAdapter,
      T,
      XGatewayError
    >(capabilityId, capabilityLabel, handlers, {
      capabilityRegistry: CAPABILITY_REGISTRY,
      planningRegistry: CAPABILITY_PLANNING_REGISTRY,
      auth: dependencies.auth,
      adapters: dependencies.adapters,
      errors: dependencies.errors,
      withOptionalTrace: dependencies.withOptionalTrace,
      ...(traceId === undefined ? {} : { traceId }),
    });
  }

  async function executeCapabilityPlan<T>(
    plan: CapabilityExecutionPlan<T>,
  ): Promise<T> {
    return dependencies.executeCapabilityOperation(plan.context, plan.execute);
  }

  const stableCapabilityExecutionRegistry: StableCapabilityExecutionRegistry = {
    "account.me": {
      capabilityLabel: "Authenticated account lookup",
      plan: (_input, traceId) =>
        buildCapabilityExecutionPlan(
          "account.me",
          "Authenticated account lookup",
          {
            read: async (adapter) => adapter.accountMe(),
          },
          traceId,
        ),
    },
    "post.get": {
      capabilityLabel: "Post lookup",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "post.get",
          "Post lookup",
          {
            read: async (adapter) => adapter.postGet(input),
          },
          traceId,
        ),
    },
    "timeline.search": {
      capabilityLabel: "Recent search",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "timeline.search",
          "Recent search",
          {
            read: async (adapter) => adapter.timelineSearch(input),
          },
          traceId,
        ),
    },
    "timeline.home": {
      capabilityLabel: "Home timeline",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "timeline.home",
          "Home timeline",
          {
            read: async (adapter) => adapter.timelineHome(input),
          },
          traceId,
        ),
    },
    "timeline.user": {
      capabilityLabel: "User timeline",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "timeline.user",
          "User timeline",
          {
            read: async (adapter) => adapter.timelineUser(input),
          },
          traceId,
        ),
    },
    "timeline.mentions": {
      capabilityLabel: "Mentions timeline",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "timeline.mentions",
          "Mentions timeline",
          {
            read: async (adapter) => adapter.timelineMentions(input),
          },
          traceId,
        ),
    },
    "post.create": {
      capabilityLabel: "Post creation",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "post.create",
          "Post creation",
          {
            stablePosting: async (adapter) => adapter.postCreate(input),
          },
          traceId,
        ),
    },
    "post.delete": {
      capabilityLabel: "Post deletion",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "post.delete",
          "Post deletion",
          {
            stablePosting: async (adapter) => adapter.postDelete(input),
          },
          traceId,
        ),
    },
    "post.reply": {
      capabilityLabel: "Post reply",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "post.reply",
          "Post reply",
          {
            stablePosting: async (adapter) => adapter.postReply(input),
          },
          traceId,
        ),
    },
    "post.quote": {
      capabilityLabel: "Post quote",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "post.quote",
          "Post quote",
          {
            stablePosting: async (adapter) => adapter.postQuote(input),
          },
          traceId,
        ),
    },
    "post.repost": {
      capabilityLabel: "Post repost",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "post.repost",
          "Post repost",
          {
            stablePosting: async (adapter) => adapter.postRepost(input),
          },
          traceId,
        ),
    },
    "post.unrepost": {
      capabilityLabel: "Post unrepost",
      plan: (input, traceId) =>
        buildCapabilityExecutionPlan(
          "post.unrepost",
          "Post unrepost",
          {
            stablePosting: async (adapter) => adapter.postUndoRepost(input),
          },
          traceId,
        ),
    },
  };
  assertStableCapabilityExecutionRegistryCoherent(
    stableCapabilityExecutionRegistry,
  );

  async function executeStableCapability<K extends StableCapabilityId>(
    capabilityId: K,
    input: StableCapabilityInputById[K],
    traceId?: string,
  ): Promise<StableCapabilityResultById[K]> {
    const definition = stableCapabilityExecutionRegistry[capabilityId];
    return executeCapabilityPlan<StableCapabilityResultById[K]>(
      definition.plan(input, traceId),
    );
  }

  return {
    executeStableCapability,
  };
}
