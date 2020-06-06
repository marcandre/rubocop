# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Team do
  subject(:team) { described_class.mobilize(cop_classes, config, options) }

  let(:cop_classes) { RuboCop::Cop::Cop.registry }
  let(:config) { RuboCop::ConfigLoader.default_configuration }
  let(:options) { {} }
  let(:ruby_version) { RuboCop::TargetRuby.supported_versions.last }

  before do
    RuboCop::ConfigLoader.default_configuration = nil
  end

  context 'when incompatible cops are correcting together' do
    include FileHelper

    let(:options) { { formatters: [], auto_correct: true } }
    let(:runner) { RuboCop::Runner.new(options, RuboCop::ConfigStore.new) }
    let(:file_path) { 'example.rb' }

    it 'auto corrects without SyntaxError', :isolated_environment do
      source = <<~'RUBY'
        foo.map{ |a| a.nil? }

        'foo' +
          'bar' +
          "#{baz}"

        i=i+1

        def a
          self::b
        end
      RUBY
      corrected = <<~'RUBY'
        # frozen_string_literal: true

        foo.map(&:nil?)

        'foo' \
          'bar' \
          "#{baz}"

        i += 1

        def a
          b
        end
      RUBY

      create_file(file_path, source)
      runner.run([])
      expect(File.read(file_path)).to eq(corrected)
    end
  end

  describe '#autocorrect?' do
    subject { team.autocorrect? }

    context 'when the option argument of .new is omitted' do
      subject { described_class.new(cop_classes, config).autocorrect? }

      it { is_expected.to be_falsey }
    end

    context 'when { auto_correct: true } is passed to .new' do
      let(:options) { { auto_correct: true } }

      it { is_expected.to be_truthy }
    end
  end

  describe '#debug?' do
    subject { team.debug? }

    context 'when the option argument of .new is omitted' do
      subject { described_class.new(cop_classes, config).debug? }

      it { is_expected.to be_falsey }
    end

    context 'when { debug: true } is passed to .new' do
      let(:options) { { debug: true } }

      it { is_expected.to be_truthy }
    end
  end

  describe '#inspect_file', :isolated_environment do
    include FileHelper

    let(:file_path) { '/tmp/example.rb' }
    let(:source) { RuboCop::ProcessedSource.from_file(file_path, ruby_version) }
    let(:offenses) do
      team.inspect_file(source)
    end

    before do
      create_file(file_path, [
                    '#' * 90,
                    'puts test;'
                  ])
    end

    it 'returns offenses' do
      expect(offenses.empty?).to be(false)
      expect(offenses).to all(be_a(RuboCop::Cop::Offense))
    end

    context 'when Parser reports non-fatal warning for the file' do
      before do
        create_file(file_path, ['#' * 130, 'puts *test'])
      end

      let(:cop_names) { offenses.map(&:cop_name) }

      it 'returns Parser warning offenses' do
        expect(cop_names).to include('Lint/AmbiguousOperator')
      end

      it 'returns offenses from cops' do
        expect(cop_names).to include('Layout/LineLength')
      end

      context 'when a cop has no interest in the file' do
        it 'returns all offenses except the ones of the cop' do
          allow_any_instance_of(RuboCop::Cop::Layout::LineLength)
            .to receive(:excluded_file?).and_return(true)

          expect(cop_names).to include('Lint/AmbiguousOperator')
          expect(cop_names).not_to include('Layout/LineLength')
        end
      end
    end

    context 'when autocorrection is enabled' do
      let(:options) { { auto_correct: true } }

      before do
        create_file(file_path, 'puts "string"')
      end

      it 'does autocorrection' do
        source = RuboCop::ProcessedSource.from_file(file_path, ruby_version)
        team.inspect_file(source)
        corrected_source = File.read(file_path)
        expect(corrected_source).to eq(<<~RUBY)
          # frozen_string_literal: true
          puts 'string'
        RUBY
      end

      it 'still returns offenses' do
        expect(offenses[1].cop_name).to eq('Style/StringLiterals')
      end
    end

    context 'when Cop#on_* raises an error' do
      include_context 'mock console output'
      before do
        allow_any_instance_of(RuboCop::Cop::Style::NumericLiterals)
          .to receive(:on_int).and_raise(StandardError)

        create_file(file_path, '10_00_000')
      end

      let(:error_message) do
        'An error occurred while Style/NumericLiterals cop was inspecting ' \
        '/tmp/example.rb:1:0.'
      end

      it 'records Team#errors' do
        source = RuboCop::ProcessedSource.from_file(file_path, ruby_version)
        team.inspect_file(source)

        expect(team.errors).to eq([error_message])
        expect($stderr.string).to include(error_message)
      end
    end

    context 'when a correction raises an error' do
      include_context 'mock console output'

      before do
        allow_any_instance_of(RuboCop::Cop::Style::NumericLiterals)
          .to receive(:autocorrect).and_return(buggy_correction)

        create_file(file_path, '10_00_000')
      end

      let(:buggy_correction) do
        lambda do |_corrector|
          raise cause
        end
      end
      let(:options) { { auto_correct: true } }

      let(:cause) { StandardError.new('cause') }

      let(:error_message) do
        'An error occurred while Style/NumericLiterals cop was inspecting ' \
        '/tmp/example.rb:1:0.'
      end

      it 'records Team#errors' do
        source = RuboCop::ProcessedSource.from_file(file_path, ruby_version)

        team.inspect_file(source)
        expect($stderr.string).to include(error_message)
      end
    end

    context 'when done twice' do
      let(:cop_classes) { [RuboCop::Cop::Base, RuboCop::Cop::Cop] }

      it 'allows cops to get ready' do
        before = team.cops.dup
        team.inspect_file(source)
        team.inspect_file(source)
        expect(team.cops).to match_array([be(before.first), be_a(RuboCop::Cop::Cop)])
        expect(team.cops.last).not_to be(before.last)
      end
    end
  end

  describe '#cops' do
    subject(:cops) { team.cops }

    it 'returns cop instances' do
      expect(cops.empty?).to be(false)
      expect(cops.all? { |c| c.is_a?(RuboCop::Cop::Base) }).to be_truthy
    end

    context 'when only some cop classes are passed to .new' do
      let(:cop_classes) do
        RuboCop::Cop::Registry.new(
          [RuboCop::Cop::Lint::Void, RuboCop::Cop::Layout::LineLength]
        )
      end

      it 'returns only instances of the classes' do
        expect(cops.size).to eq(2)
        cops.sort! { |a, b| a.name <=> b.name }
        expect(cops[0].name).to eq('Layout/LineLength')
        expect(cops[1].name).to eq('Lint/Void')
      end
    end

    context 'when some classes are disabled with config' do
      let(:disabled_config) do
        %w[
          Lint/Void
          Layout/LineLength
        ].each_with_object(RuboCop::Config.new) do |cop_name, accum|
          accum[cop_name] = { 'Enabled' => false }
        end
      end
      let(:config) do
        RuboCop::ConfigLoader.merge_with_default(disabled_config, '')
      end
      let(:cop_names) { cops.map(&:name) }

      it 'does not return instances of the classes' do
        expect(cops.empty?).to be(false)
        expect(cop_names).not_to include('Lint/Void')
        expect(cop_names).not_to include('Layout/LineLength')
      end
    end
  end

  describe '#forces' do
    subject(:forces) { team.forces }

    let(:cop_classes) { RuboCop::Cop::Cop.registry }

    it 'returns force instances' do
      expect(forces.empty?).to be(false)

      forces.each do |force|
        expect(force.is_a?(RuboCop::Cop::Force)).to be(true)
      end
    end

    context 'when a cop joined a force' do
      let(:cop_classes) do
        RuboCop::Cop::Registry.new([RuboCop::Cop::Lint::UselessAssignment])
      end

      it 'returns the force' do
        expect(forces.size).to eq(1)
        expect(forces.first.is_a?(RuboCop::Cop::VariableForce)).to be(true)
      end
    end

    context 'when multiple cops joined a same force' do
      let(:cop_classes) do
        RuboCop::Cop::Registry.new(
          [
            RuboCop::Cop::Lint::UselessAssignment,
            RuboCop::Cop::Lint::ShadowingOuterLocalVariable
          ]
        )
      end

      it 'returns only one force instance' do
        expect(forces.size).to eq(1)
      end
    end

    context 'when no cops joined force' do
      let(:cop_classes) do
        RuboCop::Cop::Registry.new([RuboCop::Cop::Style::For])
      end

      it 'returns nothing' do
        expect(forces.empty?).to be(true)
      end
    end
  end

  describe '#external_dependency_checksum' do
    let(:cop_classes) { RuboCop::Cop::Registry.new }

    it 'does not error with no cops' do
      expect(team.external_dependency_checksum.is_a?(String)).to be(true)
    end

    context 'when a cop joins' do
      let(:cop_classes) do
        RuboCop::Cop::Registry.new([RuboCop::Cop::Lint::UselessAssignment])
      end

      it 'returns string' do
        expect(team.external_dependency_checksum.is_a?(String)).to be(true)
      end
    end

    context 'when multiple cops join' do
      let(:cop_classes) do
        RuboCop::Cop::Registry.new(
          [
            RuboCop::Cop::Lint::UselessAssignment,
            RuboCop::Cop::Lint::ShadowingOuterLocalVariable
          ]
        )
      end

      it 'returns string' do
        expect(team.external_dependency_checksum.is_a?(String)).to be(true)
      end
    end

    context 'when cop with different checksum joins' do
      before do
        # rubocop:disable RSpec/LeakyConstantDeclaration
        module Test
          class CopWithExternalDeps < ::RuboCop::Cop::Cop
            def external_dependency_checksum
              'something other than nil'
            end
          end
        end
        # rubocop:enable RSpec/LeakyConstantDeclaration
      end

      let(:new_cop_classes) do
        RuboCop::Cop::Registry.new(
          [
            Test::CopWithExternalDeps,
            RuboCop::Cop::Lint::UselessAssignment,
            RuboCop::Cop::Lint::ShadowingOuterLocalVariable
          ]
        )
      end

      it 'has a different checksum for the whole team' do
        original_checksum = team.external_dependency_checksum
        new_team = described_class.mobilize(new_cop_classes, config, options)
        new_checksum = new_team.external_dependency_checksum
        expect(original_checksum).not_to eq(new_checksum)
      end
    end
  end

  describe '.new' do
    it 'calls mobilize when passed classes' do
      expect(described_class).to receive(:mobilize).with(cop_classes, config, options)
      described_class.new(cop_classes, config, options)
    end

    it 'accepts cops directly classes' do
      cop = RuboCop::Cop::Metrics::AbcSize.new
      team = described_class.new([cop], config, options)
      expect(team.cops.first).to equal(cop)
    end
  end
end
