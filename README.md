# rubocop-rspec-unused-let

A [RuboCop](https://github.com/rubocop/rubocop) extension that detects
unreferenced RSpec `let` definitions.

It adds a single cop, `RSpec/UnusedLet`, which flags `let` (and optionally
`let!`) definitions whose name is never referenced within their scope. The cop
resolves `shared_examples` references precisely when the shared block is defined
in the same file, and stays conservative otherwise, so that it avoids false
positives that a naive implementation would produce.

## Installation

Add the gem to your `Gemfile`:

```ruby
gem "rubocop-rspec-unused-let", require: false
```

This gem builds on [rubocop-rspec](https://github.com/rubocop/rubocop-rspec),
so make sure that is available too.

## Usage

Enable both plugins in your `.rubocop.yml`:

```yaml
plugins:
  - rubocop-rspec
  - rubocop-rspec-unused-let
```

## What it detects

```ruby
# bad
RSpec.describe Foo do
  let(:used)   { 1 }
  let(:unused) { 2 } # never referenced

  it { expect(used).to eq(1) }
end

# good
RSpec.describe Foo do
  let(:used) { 1 }

  it { expect(used).to eq(1) }
end
```

A `let` is considered *used* when its name appears as a bare method call
anywhere in its scope — inside examples, hooks (`before`/`after`/`around`),
`subject`, other `let` blocks, and nested example groups. Dynamic references
such as `send(:name)` / `public_send("name")` are also treated as usages.

## How it handles `shared_examples`

Because RuboCop analyzes one file at a time, a `let` can be consumed by a shared
example block defined in another file. The cop is precise when the block is in
reach and conservative when it is not:

- `let` definitions **inside** a `shared_examples` / `shared_context` block —
  including any nested `context`/`describe` within it — are never flagged, since
  the groups that include the block (possibly in other files) may reference them.
- When an included shared example is **defined in the same file**, only the
  `let`s that block actually references are treated as used; every other `let`
  stays checked.
- When the included block is **not defined in this file** (or is included under
  a non-literal name), the cop cannot tell what it references, so it leaves every
  `let` **visible at that inclusion point** alone. Sibling subtrees without such
  an inclusion are still checked. To resolve blocks defined in other files (e.g.
  under `spec/support`), list them in `SharedExamplePaths` (see below).

```ruby
RSpec.shared_examples "uses a" do
  it { expect(a).to eq(1) }  # references `a`, and only `a`
end

RSpec.describe Foo do
  let(:a) { 1 }              # skipped: referenced by the shared block above
  let(:b) { 2 }              # flagged: the shared block never references it

  it_behaves_like "uses a"
end
```

For an inclusion the cop cannot resolve, it falls back to silencing every
visible `let`:

```ruby
RSpec.describe Foo do
  let(:a) { 1 }              # skipped: visible at the inclusion below

  context "with shared" do
    let(:b) { 2 }            # skipped: same
    it_behaves_like "an external thing"   # defined in another file
  end

  context "other" do
    let(:c) { 3 }            # checked: the shared block cannot see `c`
    it { expect(c).to eq(3) }
  end
end
```

### Resolving shared examples defined in other files

Shared examples usually live under `spec/support` and are included from many
spec files. List those files in `SharedExamplePaths` (paths or globs) and the
cop pre-loads them, so an inclusion of a block defined there is resolved with
the same precision as an in-file one, instead of the conservative fallback
above.

```yaml
# .rubocop.yml
RSpec/UnusedLet:
  SharedExamplePaths:
    - "spec/support/**/*.rb"
```

Paths resolve relative to the `.rubocop.yml` that sets them (as `Include` and
`Exclude` do). A listed file that is missing or cannot be parsed is skipped, and
when a name is defined both in a pre-loaded file and in the spec itself, the
in-file definition wins (mirroring RSpec's load order).

## Autocorrect

The cop can remove flagged `let` definitions automatically, but the
correction is marked **unsafe** because a `let!` block may exist for its
side effects. Run `rubocop --autocorrect-all` (or `-A`) to apply the
corrections, and review the diff before committing.

```ruby
# before -A
RSpec.describe Foo do
  let(:used)   { 1 }
  let(:unused) { 2 }

  it { expect(used).to eq(1) }
end

# after -A
RSpec.describe Foo do
  let(:used)   { 1 }

  it { expect(used).to eq(1) }
end
```

## Configuration

```yaml
RSpec/UnusedLet:
  # Whether to also check `let!`. On by default. Since `let!` is sometimes used
  # purely for its side effects (e.g. `let!(:user) { create(:user) }`), set this
  # to `false` to opt out.
  CheckLetBang: true

  # Whether to check helper specs. Off by default. A helper spec (rspec-rails
  # `type: :helper`, or a spec file under `spec/helpers`) auto-includes the
  # described module into the example group, so its externally defined methods
  # may reference any `let` in scope — invisibly to single-file analysis. Set
  # this to `true` to check them anyway, accepting the risk of false positives.
  CheckHelperSpecs: false
```

## Known-gem support

Some gems ship a shared context that dereferences `let` names dynamically
(e.g. via `eval`), so a single-file static analysis cannot see the
references. When the cop recognizes such a gem by the `type:` metadata on
an example group (or one of its ancestors), it treats the affected `let`
names as used automatically.

Currently supported:

- [rspec-validator_spec_helper](https://github.com/izumin5210/rspec-validator_spec_helper)
  — groups tagged with `type: :validator` may define `let(:value)`,
  `let(:attribute_names)`, `let(:options)` (and the helper's other
  overridable lets) without being flagged.

```ruby
RSpec.describe JsonFormatValidator, type: :validator do
  let(:value) { "String" }   # not flagged
  it { is_expected.to be_invalid }
end
```

## Helper specs

Helper specs (rspec-rails `type: :helper` groups, or spec files under
`spec/helpers`) auto-include the described module into the example group.
Its methods live in another file and may reference any `let` in scope, so a
single-file static analysis cannot see those references. To avoid false
positives, such groups are skipped by default. Set `CheckHelperSpecs: true`
to check them anyway.

```ruby
RSpec.describe MyHelper, type: :helper do
  let(:current_user) { User.new }   # not flagged (may be used by MyHelper's methods)
  it { expect(helper.greeting).to eq("Hi") }
end
```

## Known limitations

- Analysis is limited to a single file; references reachable only across files
  (e.g. through external shared examples) are intentionally not flagged.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run
`rake spec` to run the tests and `rake rubocop` to lint the gem. `rake` runs
both.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/tk0miya/rubocop-rspec-unused-let.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
