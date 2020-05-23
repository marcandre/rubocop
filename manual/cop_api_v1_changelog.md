# Cop API v0 to v1 API changes

## Upgrade guide

Your custom cops should continue to work in v1.
Nevertheless it is suggested that you tweak them to use the v1 API by following the following steps:

1) Your class should inherit from `RuboCop::Cop::Base` instead of `RuboCop::Cop::Cop`.

2) Locate your calls to `add_offense` and make sure that you pass as the first argument either a `AST::Node`, a `::Parser::Source::Comment` or a `::Parser::Source::Range`, and no `location:` named parameter

## Example:

```
# Before
    class MySillyCop < Cop
      def on_send(node)
        if node.method_name == :+
          add_offense(node, location: :selector, message: "Wrap all +")
        end
      end
    end

# After
    class MySillyCop < Base
      def on_send(node)
        if node.method_name == :+
          add_offense(node.loc.selector, message: "Wrap all +")
        end
      end
    end
```


3) If your class support autocorrection

Your class must `extend Autocorrector`

The `corrector` is now yielded from `add_offense`. Move the code of your method `auto_correct` in that block and do not wrap your correction in a lambda.

### Example:

```
# Before
    class MySillyCorrectingCop < Cop
      def on_send(node)
        if node.method_name == :-
          add_offense(node, location: :selector, message: 'Be positive')
        end
      end

      def auto_correct(node)
        lambda do |corrector|
          corrector.replace(node.loc.selector, '+')
        end
      end
    end
```

```
# After
    class MySillyCorrectingCop < Base
      extend Autocorrector

      def on_send(node)
        if node.method_name == :+
          add_offense(node.loc.selector, message: 'Be positive') do |corrector|
            corrector.replace(node.loc.selector, '+')
          end
        end
      end
    end
```

## Upgrading specs

It is highly recommended you use `expect_offense` / `expect_no_offense` in your specs, e.g.:

```
require 'rubocop/rspec/support'

RSpec.describe RuboCop::Cop::Custom::MySillyCorrectingCop, :config do
  it 'wraps +' do
    expect_offense(<<~RUBY)
      42 + 2 - 2
             ^ Be positive
    RUBY

    expect_correction(<<~RUBY)
      42 + 2 + 2
    RUBY
  end

  it 'does not register an offense for calls to `despair`' do
    expect_no_offenses(<<~RUBY)
      "don't".despair
    RUBY
  end
end
```

# Detailed API Changes

This section lists all changes (big or small) to the API. It is meant for maintainers of the nuts & bolts of RuboCop; most cop writers will not be impacted by these and are thus not the target audience.


## `add_offense` API

### arguments

Legacy: interface allowed for a `node`, with an optional `location` (symbol or range) or a range with a mandatory range as the location. Some cops were abusing the `node` argument and passing very different things.

Current: pass a range (or node as a shortcut for `node.loc.expression`), no `location:`.

### de-dupping changes

Both de-dup on `range` and won't process the duplicated offenses at all.

Legacy: if offenses on same `node` but different `range`: considered as multiple offenses but a single auto-correct call

Current: not applicable and not needed with autocorrection's API

### yield

Both yield under the same conditions (unless cop is disabled for that line), but:

Legacy: yields after offense added to `#offenses`

Current: yields before offense is added to `#offenses`.


## Autocorrection

#### `#autocorrect`

Legacy: calls `autocorrect` unless it is disabled / autocorrect is off

Current: yields a corrector unless it is disabled. No support for `autocorrect`

### Empty corrections

Legacy: `autocorrect` could return `nil` / `false` in cases where it couldn't actually make a correction.

Current: No special API. Cases where no corrections are made are automatically detected.

### Correction timing

Legacy: the lambda was called only later in the process, and only under specific conditions (if the auto-correct setting is turned on, etc.)

Current: correction is built immediately (assuming the cop isn't disabled for the line) and applied later in the process.

### Exception handling

Both: `Commissionner` will rescue all `StandardError`s during analysis (unless `option[:raise_error]`) and store a corresponding `ErrorWithAnalyzedFileLocation` in its error list. This is done when calling the cop's `on_send` & al., or when calling `investigate` / `investigate_post_walk` callback. When the

Legacy: autocorrections were called from `Team`, so they were rescued, wrapped in `ErrorWithAnalyzedFileLocation` and re-raise in the correction code. `Team` would then rescue those and add them to the list of errors.

Current: `Team` no longer has any special error handling to do as potential exceptions happen when `Commissioner` is running.

### Other error handling

Legacy: Clobbering errors are silently ignored. Calling `insert_before` with ranges that extend beyond the source code was silently fixed.

Current: Such errors are not ignored. It is still ok that a given Cop's corrections clobber another Cop's, but any given Cop should not issue corrections that clobber each other, or with invalid ranges.


### `#corrections`

Legacy: Corrections are held in `#corrections` an array of lambdas.

Current: Corrections are held in a `Corrector` which inherits from `Source::TreeRewriter`. A proxy was written to maintain compatibility with `corrections << ...`, `corrections.concat ...`, etc.

### `#support_autocorrect?`

Legacy: instance method.

Current: class method.

## Other

* `#find_location` is deprecated

* `Correction` is deprecated.

* A few registry access methods were moved from `Cop` to `Registry`:
  * `Cop.registry` => `Registry.global`
  * `Cop.all` => `Registry.all`
  * `Cop.qualified_cop_name` => `Registry.qualified_cop_name`
