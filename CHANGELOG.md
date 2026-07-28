## [Unreleased]

- `RSpec/UnusedLet` now also flags `subject`/`subject!` definitions that
  nothing references. A subject answers to two names: its own, when it has
  one, and the implicit `subject`, which RSpec's one-liner syntax
  (`is_expected`, `are_expected`, `should`, `should_not`) and rspec-its' `its`
  reach. A reference by either name counts, in a shared example block as much
  as in an example group. `CheckLetBang` governs `subject!` alongside `let!`,
  and setting the new `CheckSubject` (default `true`) to `false` turns the
  check off entirely.
- `RSpec/UnusedLet` now also flags helper methods (`def`) written at an
  example group's level whose name is never referenced. Such a method
  becomes an instance method on the group's example class, so it is checked
  with the same rules as a `let`, and autocorrect removes it.
- `RSpec/UnusedLet` now understands `shared_examples` / `shared_context`.
  Where it used to silence every `let` an inclusion could reach, it now works
  out which ones the shared block really uses, falling back to the old
  behavior only for an inclusion it cannot resolve, and it no longer flags a
  `let` that overrides a name an inline inclusion (`include_examples` /
  `include_context`) injects and the shared block itself references. It also
  checks the `let`s defined inside a shared block that carries examples —
  expect new offenses on upgrade. `SharedExamplePaths` lists the files,
  besides the one under inspection, whose top-level blocks are resolved, and
  defaults to `spec/support/**/*.rb`; `CheckSharedExamples: false` leaves the
  `let`s inside shared blocks unchecked, as before.
- `RSpec/UnusedLet` now skips helper specs (rspec-rails `type: :helper`, or
  files under `spec/helpers`) by default, since the auto-included module may
  reference any `let` unseen. Set `CheckHelperSpecs: true` to check them.
- `RSpec/UnusedLet` now recognizes `let` definitions consumed by
  well-known gems' shared contexts and treats them as used. Currently
  supports [rspec-validator_spec_helper](https://github.com/izumin5210/rspec-validator_spec_helper):
  groups tagged with `type: :validator` may override `value`,
  `attribute_names`, `options` (and the helper's other overridable
  lets) without being flagged.
- Fix a false positive in `RSpec/UnusedLet` when a `let` defined in a
  nested group was only referenced from an ancestor group's `let`,
  `subject`, or hook block. Those ancestor blocks run in the example's
  scope, so their references resolve to the nested definition.
- Fix a false positive in `RSpec/UnusedLet` when a `let` was only
  referenced from a plain `def` helper method defined in an ancestor
  example group. Such helpers become instance methods on the example
  class and can reference `let` names visible at the example.

## [1.1.0] - 2026-07-15

- `RSpec/UnusedLet` now supports autocorrect. The correction is marked
  unsafe because a `let!` block may exist for side effects — flagged
  definitions are removed under `rubocop --autocorrect-all`.

## [1.0.0] - 2026-07-15

- Initial release
