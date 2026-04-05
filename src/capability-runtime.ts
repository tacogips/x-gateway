import type {
  CapabilityDescriptor,
  CapabilityPlanningDefinition,
  CapabilityRouteAdapterKind,
  CapabilityRouteDefinition,
  StableCapabilityId,
  XGatewayCapabilityReadinessStatus,
  XGatewayCapabilityRequirement,
} from "./capability-metadata";

export type RuntimeAuthMode = "oauth1" | "bearer";

export type ResolvedCapabilityAuth = Readonly<{
  hasOauth1: boolean;
  hasBearerToken: boolean;
  availableAuthModes: readonly RuntimeAuthMode[];
}>;

export type CapabilityExecutionContext = Readonly<{
  capabilityId: string;
  capabilityLabel: string;
  transportLabel: string;
  traceId?: string;
}>;

export type CapabilityExecutionPlan<T> = Readonly<{
  capability: CapabilityDescriptor;
  selectedAuthMode: RuntimeAuthMode;
  context: CapabilityExecutionContext;
  execute: () => Promise<T>;
}>;

export type XGatewayCapabilityReadiness = Readonly<{
  capabilityId: string;
  status: XGatewayCapabilityReadinessStatus;
  requirement: XGatewayCapabilityRequirement;
  reason: string;
  selectedAuthMode?: RuntimeAuthMode;
}>;

type CapabilityRuntimeErrorFactories<TError extends Error> = Readonly<{
  createCapabilityRegistryMissingError: (capabilityId: string) => TError;
  createCapabilityPlanningMissingError: (capabilityId: string) => TError;
  createConfiguredAuthUnsupportedError: (
    capabilityLabel: string,
    planning: CapabilityPlanningDefinition,
  ) => TError;
  createCapabilityAuthMissingError: (
    capability: CapabilityDescriptor,
    planning: CapabilityPlanningDefinition,
  ) => TError;
  createHandlerMissingError: (
    capabilityId: StableCapabilityId,
    adapterKind: "read-capability" | "stable-posting",
  ) => TError;
  createUnsupportedAdapterKindError: (
    capabilityId: StableCapabilityId,
    adapterKind: CapabilityRouteAdapterKind,
  ) => TError;
}>;

type CapabilityAdapterFactories<TReadAdapter, TPostingAdapter> = Readonly<{
  createReadAdapter: (authMode: RuntimeAuthMode) => TReadAdapter;
  createStablePostingAdapter: (authMode: RuntimeAuthMode) => TPostingAdapter;
}>;

type CapabilityExecutionHandlers<TReadAdapter, TPostingAdapter, TResult> =
  Readonly<{
    read?: ((adapter: TReadAdapter) => Promise<TResult>) | undefined;
    stablePosting?:
      | ((adapter: TPostingAdapter) => Promise<TResult>)
      | undefined;
  }>;

type TraceFactory = (traceId?: string) => Readonly<{ traceId?: string }>;

export function createCapabilityReadiness(
  capabilityId: string,
  status: XGatewayCapabilityReadinessStatus,
  requirement: XGatewayCapabilityRequirement,
  reason: string,
  selectedAuthMode?: RuntimeAuthMode,
): XGatewayCapabilityReadiness {
  return selectedAuthMode === undefined
    ? {
        capabilityId,
        status,
        requirement,
        reason,
      }
    : {
        capabilityId,
        status,
        requirement,
        reason,
        selectedAuthMode,
      };
}

function isRouteConfigured(
  route: CapabilityRouteDefinition,
  auth: ResolvedCapabilityAuth,
): boolean {
  return route.authMode === "oauth1" ? auth.hasOauth1 : auth.hasBearerToken;
}

export function getConfiguredCapabilityRoute(
  planning: CapabilityPlanningDefinition,
  auth: ResolvedCapabilityAuth,
): CapabilityRouteDefinition | undefined {
  return planning.routes.find((route) => isRouteConfigured(route, auth));
}

export function buildAuthCapabilityReadiness(
  planningRegistry: readonly CapabilityPlanningDefinition[],
  auth: ResolvedCapabilityAuth,
): readonly XGatewayCapabilityReadiness[] {
  return planningRegistry.map((planning) => {
    const selectedRoute = getConfiguredCapabilityRoute(planning, auth);
    if (!selectedRoute) {
      return createCapabilityReadiness(
        planning.capabilityId,
        "blocked",
        planning.missingAuthRequirement,
        planning.missingAuthReason,
      );
    }

    return createCapabilityReadiness(
      planning.capabilityId,
      selectedRoute.readinessStatus ?? "ready",
      selectedRoute.readinessRequirement,
      selectedRoute.readinessReason,
      selectedRoute.authMode,
    );
  });
}

function getCapabilityDescriptorById(
  capabilityId: string,
  capabilityRegistry: readonly CapabilityDescriptor[],
  createCapabilityRegistryMissingError: (capabilityId: string) => Error,
): CapabilityDescriptor {
  const capability = capabilityRegistry.find(
    (entry) => entry.id === capabilityId,
  );
  if (!capability) {
    throw createCapabilityRegistryMissingError(capabilityId);
  }
  return capability;
}

function getCapabilityPlanningDefinition(
  capabilityId: CapabilityPlanningDefinition["capabilityId"],
  planningRegistry: readonly CapabilityPlanningDefinition[],
  createCapabilityPlanningMissingError: (capabilityId: string) => Error,
): CapabilityPlanningDefinition {
  const planning = planningRegistry.find(
    (entry) => entry.capabilityId === capabilityId,
  );
  if (!planning) {
    throw createCapabilityPlanningMissingError(capabilityId);
  }
  return planning;
}

export function planCapabilityExecution<
  TReadAdapter,
  TPostingAdapter,
  TResult,
  TError extends Error,
>(
  capabilityId: StableCapabilityId,
  capabilityLabel: string,
  handlers: CapabilityExecutionHandlers<TReadAdapter, TPostingAdapter, TResult>,
  options: Readonly<{
    capabilityRegistry: readonly CapabilityDescriptor[];
    planningRegistry: readonly CapabilityPlanningDefinition[];
    auth: ResolvedCapabilityAuth;
    adapters: CapabilityAdapterFactories<TReadAdapter, TPostingAdapter>;
    errors: CapabilityRuntimeErrorFactories<TError>;
    withOptionalTrace: TraceFactory;
    traceId?: string;
  }>,
): CapabilityExecutionPlan<TResult> {
  const createTransportLabel = (route: CapabilityRouteDefinition): string => {
    return `${route.transport}/${route.authMode}`;
  };
  const capability = getCapabilityDescriptorById(
    capabilityId,
    options.capabilityRegistry,
    options.errors.createCapabilityRegistryMissingError,
  );
  const planning = getCapabilityPlanningDefinition(
    capabilityId,
    options.planningRegistry,
    options.errors.createCapabilityPlanningMissingError,
  );
  const selectedRoute = getConfiguredCapabilityRoute(planning, options.auth);

  if (!selectedRoute) {
    if (options.auth.availableAuthModes.length > 0) {
      throw options.errors.createConfiguredAuthUnsupportedError(
        capabilityLabel,
        planning,
      );
    }
    throw options.errors.createCapabilityAuthMissingError(capability, planning);
  }

  if (selectedRoute.adapterKind === "read-capability") {
    const adapter = options.adapters.createReadAdapter(selectedRoute.authMode);
    const handler = handlers.read;
    if (!handler) {
      throw options.errors.createHandlerMissingError(
        capabilityId,
        selectedRoute.adapterKind,
      );
    }
    return {
      capability,
      selectedAuthMode: selectedRoute.authMode,
      context: {
        capabilityId,
        capabilityLabel,
        transportLabel: createTransportLabel(selectedRoute),
        ...options.withOptionalTrace(options.traceId),
      },
      execute: async () => handler(adapter),
    };
  }

  if (selectedRoute.adapterKind === "stable-posting") {
    const adapter = options.adapters.createStablePostingAdapter(
      selectedRoute.authMode,
    );
    const handler = handlers.stablePosting;
    if (!handler) {
      throw options.errors.createHandlerMissingError(
        capabilityId,
        selectedRoute.adapterKind,
      );
    }
    return {
      capability,
      selectedAuthMode: selectedRoute.authMode,
      context: {
        capabilityId,
        capabilityLabel,
        transportLabel: createTransportLabel(selectedRoute),
        ...options.withOptionalTrace(options.traceId),
      },
      execute: async () => handler(adapter),
    };
  }

  throw options.errors.createUnsupportedAdapterKindError(
    capabilityId,
    selectedRoute.adapterKind,
  );
}
