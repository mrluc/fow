# Fog of War

Fog of War lets selected pages remain available as read-only, last-known content when their live server cannot be reached.

## Language

**Public preload**: A distributable copy of explicitly selected, unauthenticated page content included with an application. It contains no particular user's logged-in session.

**Cached page**: A last-known presentation of a route, available without its server. It may come from a public preload or from an earlier online visit, subject to the application's caching policy.

**Live page**: A page whose current presentation and interactive actions are owned by a connected LiveView on the server. Merely displaying cached LiveView markup does not make a page live.

**Startup recovery**: The automatic transition from an available cached page to a live page after an application opens. It must also work when the application has never connected before.

**Live handoff**: The point at which a ready live page replaces the cached presentation for the user's current route. A connection attempt or an open transport alone is not a live handoff.
