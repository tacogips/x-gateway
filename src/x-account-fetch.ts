function failGraphqlOnly(): never {
  throw new Error(
    [
      "x-account-fetch is disabled in GraphQL-only mode.",
      "The previous implementation used twitter-api-v2 REST endpoints, which violates the repository-wide GraphQL-only access requirement.",
      "If you need this workflow again, implement it with explicit GraphQL operation ids/documents and variables.",
    ].join(" "),
  );
}

failGraphqlOnly();
