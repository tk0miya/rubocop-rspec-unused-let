## [Unreleased]

- Fix a false positive in `RSpec/UnusedLet` when a `let` defined in a
  nested group was only referenced from an ancestor group's `let`,
  `subject`, or hook block. Those ancestor blocks run in the example's
  scope, so their references resolve to the nested definition.

## [1.1.0] - 2026-07-15

- `RSpec/UnusedLet` now supports autocorrect. The correction is marked
  unsafe because a `let!` block may exist for side effects — flagged
  definitions are removed under `rubocop --autocorrect-all`.

## [1.0.0] - 2026-07-15

- Initial release
