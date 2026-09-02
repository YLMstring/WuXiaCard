# Oracle Retirement Implementation Plan

Date: 2026-09-02

1. Inventory Oracle entry points, exclusive helpers, tests, benchmarks, and
   documentation; preserve shared production facade responsibilities.
2. Migrate fine-grained rule/card tests from `apply_action_oracle()` to the
   production `apply_action()` path and fix only genuine native regressions.
3. Replace Oracle-dependent search tests with native semantic fixtures and
   convert catalog-wide parity assertions into independent production
   coverage assertions.
4. Add and run the temporary real-deck deterministic lockstep seal, comparing
   exact state, events, zones, terminal status, and legal actions after every
   action.
5. Commit the passing pre-removal seal as the recoverable Oracle endpoint.
6. Remove Oracle transition/search entry points, exclusive helpers, historical
   runnable ablations, and comparison-only probes; keep recorded historical
   results in documentation.
7. Update architecture, AI, testing, decisions, handoff, and native README to
   describe the single native authority.
8. Build the native extension, run focused suites, run the full canonical
   suite, and complete one muted scene-driven production duel.
9. Commit the finished Oracle retirement with behavior-focused wording.
