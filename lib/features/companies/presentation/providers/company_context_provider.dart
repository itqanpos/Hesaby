// قبل:
final AuthState auth = ref.read(authProvider);
if (auth.isAuthenticated) {
  unawaited(_loadFromScratch());
}

// بعد:
final AuthState auth = ref.read(authProvider);
if (auth.isAuthenticated) {
  // `_loadFromScratch` writes to `state` at its very first statement
  // (before any `await`). Running it inline from `build()` would access
  // `state` while Riverpod has not yet stored the initial value returned
  // by `build()` — triggering
  // `StateError: Tried to read the state of an uninitialized provider`.
  // Deferring to the next microtask guarantees the notifier is fully
  // built before the load starts. `_isDisposed` still guards all writes
  // in case disposal happens before the microtask runs.
  scheduleMicrotask(_loadFromScratch);
}
