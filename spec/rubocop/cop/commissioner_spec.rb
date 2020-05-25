# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Commissioner do
  describe '#investigate' do
    subject(:offenses) { do_investigate.call }

    let(:cop) do
      # rubocop:disable RSpec/VerifiedDoubles
      double(RuboCop::Cop::Cop, offenses: [],
                                excluded_file?: false).as_null_object
      # rubocop:enable RSpec/VerifiedDoubles
    end
    let(:cops) { [cop] }
    let(:options) { {} }
    let(:commissioner) { described_class.new(cops, **options) }
    let(:errors) { commissioner.errors }
    let(:source) { '' }
    let(:processed_source) { parse_source(source, 'file.rb') }
    let(:do_investigate) { ->(source = processed_source) { commissioner.investigate(source) } }

    it 'returns all offenses found by the cops' do
      allow(cop).to receive(:offenses).and_return([1])

      expect(offenses).to eq [1]
    end

    context 'when a cop has no interest in the file' do
      before do
        allow(cop).to receive(:excluded_file?) do |arg|
          arg == 'file.rb'
        end
        allow(cop).to receive(:offenses).and_return(%w[bar])
      end

      context 'and with other cops' do
        let(:cops) do
          cops = []
          cops << instance_double(RuboCop::Cop::Cop, offenses: %w[foo],
                                                     excluded_file?: false).as_null_object
          cops << cop
          cops << instance_double(RuboCop::Cop::Cop, offenses: %w[baz],
                                                     excluded_file?: false).as_null_object
        end

        it 'returns all offenses except the ones of the cop' do
          expect(offenses).to eq %w[foo baz]
        end
      end

      it 'still processes the cop for other files later' do
        expect(offenses).to eq %w[]

        next_offenses = do_investigate.call(parse_source(source, 'other_file.rb'))

        expect(next_offenses).to eq %w[bar]
      end
    end

    context 'with a method definition source' do
      let(:source) { <<~RUBY }
        def method
        1
        end
      RUBY

      it 'traverses the AST and invoke cops specific callbacks' do
        expect(cop).to receive(:on_def).once
        offenses
      end

      it 'stores all errors raised by the cops' do
        allow(cop).to receive(:on_int) { raise RuntimeError }

        expect(offenses).to eq []
        expect(errors.size).to eq(1)
        expect(
          errors[0].cause.instance_of?(RuntimeError)
        ).to be(true)
        expect(errors[0].line).to eq 2
        expect(errors[0].column).to eq 0
      end

      context 'when passed :raise_error option' do
        let(:options) { { raise_error: true } }

        it 're-raises the exception received while processing' do
          allow(cop).to receive(:on_int) { raise RuntimeError }

          expect do
            offenses
          end.to raise_error(RuntimeError)
        end
      end
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
        expect(cop).to receive(:investigate).with(processed_source)
        expect(force).to receive(:investigate).with(processed_source)
        offenses
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
