# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Cache do
  subject(:instance) { cached_class.new }

  let(:cached_class) do
    Class.new do
      extend RuboCop::Cop::Cache
      cache :foo, :bar, :with_underscore

      attr_reader :calls

      def initialize
        @calls = []
      end

      def foo
        @calls << :foo
        :foo
      end

      # Even methods returning `nil` should be cacheable
      def bar
        @calls << :bar
        nil
      end

      def on_walk_begin
        @calls << :on_walk_begin
      end
    end
  end

  it 'prepends a nicely named module' do
    expect(cached_class.ancestors).to include(cached_class::FooAndBarAndWithUnderscoreCache)
  end

  it 'caches the calls' do
    expect(instance.calls).to eq([])
    expect(instance.foo).to be(:foo)
    expect(instance.bar).to be(nil)
    expect(instance.calls).to eq(%i[foo bar])
    expect(instance.foo).to be(:foo)
    expect(instance.bar).to be(nil)
    expect(instance.calls).to eq(%i[foo bar])
  end

  it 'defines on_walk_begin to clear cache' do
    expect(instance.bar).to be(nil)
    expect(instance.calls).to eq([:bar])
    instance.on_walk_begin
    expect(instance.calls).to eq(%i[bar on_walk_begin])
    expect(instance.bar).to be(nil)
    expect(instance.calls).to eq(%i[bar on_walk_begin bar])
  end
end
