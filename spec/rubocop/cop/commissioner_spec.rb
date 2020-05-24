# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Commissioner do
  describe '#investigate' do
    let(:cop) do
      # rubocop:disable RSpec/VerifiedDoubles
      double(RuboCop::Cop::Cop, offenses: [],
                                excluded_file?: false).as_null_object
      # rubocop:enable RSpec/VerifiedDoubles
    end

    it 'returns all offenses found by the cops' do
      allow(cop).to receive(:offenses).and_return([1])

      commissioner = described_class.new([cop])
      source = ''
      processed_source = parse_source(source)

      expect(commissioner.investigate(processed_source)).to eq [1]
    end

    context 'when a cop has no interest in the file' do
      it 'returns all offenses except the ones of the cop' do
        cops = []
        cops << instance_double(RuboCop::Cop::Cop, offenses: %w[foo],
                                                   excluded_file?: false)
        cops << instance_double(RuboCop::Cop::Cop, excluded_file?: true)
        cops << instance_double(RuboCop::Cop::Cop, offenses: %w[baz],
                                                   excluded_file?: false)
        cops.each(&:as_null_object)

        commissioner = described_class.new(cops)
        source = ''
        processed_source = parse_source(source)

        expect(commissioner.investigate(processed_source)).to eq %w[foo baz]
      end

      it 'still processes the cop for other files later' do
        cop = instance_double(RuboCop::Cop::Cop, offenses: %w[bar])
        allow(cop).to receive(:excluded_file?) do |arg|
          arg == 'file_a.rb'
        end
        cop.as_null_object

        commissioner = described_class.new([cop])
        source = ''
        processed_source = parse_source(source, 'file_a.rb')
        expect(commissioner.investigate(processed_source)).to eq %w[]

        processed_source = parse_source(source, 'file_b.rb')
        commissioner.investigate(processed_source)

        expect(commissioner.investigate(processed_source)).to eq %w[bar]
      end
    end

    it 'traverses the AST and invoke cops specific callbacks' do
      expect(cop).to receive(:on_def).once

      commissioner = described_class.new([cop])
      source = <<~RUBY
        def method
        1
        end
      RUBY
      processed_source = parse_source(source)

      commissioner.investigate(processed_source)
    end

    context 'with a cop joining a force' do
      before do
        allow(force_class).to receive(:new).and_return(force)
        allow(RuboCop::Cop::Force).to receive(:all).and_return([force_class])
        allow(cop).to receive(:join_force?).with(force_class).and_return(true)
      end

      let(:force_class) { RuboCop::Cop::Force }
      let(:force) { instance_double(force_class).as_null_object }

      it 'passes the input params to all cops/forces that implement their own' \
         ' #investigate method' do
        source = ''
        processed_source = parse_source(source)
        expect(cop).to receive(:investigate).with(processed_source)
        expect(force).to receive(:investigate).with(processed_source)

        commissioner = described_class.new([cop])

        commissioner.investigate(processed_source)
      end
    end

    it 'stores all errors raised by the cops' do
      allow(cop).to receive(:on_int) { raise RuntimeError }

      commissioner = described_class.new([cop])
      source = <<~RUBY
        def method
        1
        end
      RUBY
      processed_source = parse_source(source)

      commissioner.investigate(processed_source)

      expect(commissioner.errors.size).to eq(1)
      expect(
        commissioner.errors[0].cause.instance_of?(RuntimeError)
      ).to be(true)
      expect(commissioner.errors[0].line).to eq 2
      expect(commissioner.errors[0].column).to eq 0
    end

    context 'when passed :raise_error option' do
      it 're-raises the exception received while processing' do
        allow(cop).to receive(:on_int) { raise RuntimeError }

        commissioner = described_class.new([cop], raise_error: true)
        source = <<~RUBY
          def method
          1
          end
        RUBY
        processed_source = parse_source(source)

        expect do
          commissioner.investigate(processed_source)
        end.to raise_error(RuntimeError)
      end
    end
  end

  describe '.forces_for' do
    subject(:forces) { described_class.forces_for(cops) }

    let(:cop_classes) { RuboCop::Cop::Cop.registry }
    let(:cops) { cop_classes.cops.map(&:new) }

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
end
