# Incremental recent search

Issue: https://github.com/tacogips/x-gateway/issues/2

Add optional `sinceId` and `nextToken` to recent `searchPosts`, forwarding them
as X request parameters without rewriting the search expression. Preserve the
existing query and pageInfo contracts. Test parser and encoded URL values,
omitted/invalid cursors, and response cursor/watermark preservation offline.

Document stable bounds during pagination and advancing the watermark only after
completion. Release as 0.1.8 because 0.1.7 was already published. Remove redundant
Homebrew renderer version declarations discovered by strict audit of 0.1.7.

Reference: https://docs.x.com/x-api/posts/search-recent-posts
