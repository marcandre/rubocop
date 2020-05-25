# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Commissioner do
  describe '#investigate' do
    let(:cop) do
      # rubocop:disable RSpec/VerifiedDoubles
      double(RuboCop::Cop::Cop, offenses: [],
                                excluded_file?: false).as_null_object
      # rubocop:enable RSpec/VerifiedDoubles
    end
    let(:force) { instance_double(RuboCop::Cop::Force).as_null_object }

    it 'returns all offenses found by the cops' do
      allow(cop).to receive(:offenses).and_return([1])

      commissioner = described_class.new([cop], [])
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

        commissioner = described_class.new(cops, [])
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

      commissioner = described_class.new([cop], [])
      source = <<~RUBY
        def method
        1
        end
      RUBY
      processed_source = parse_source(source)

      commissioner.investigate(processed_source)
    end

    it 'passes the input params to all cops/forces that implement their own' \
       ' #investigate method' do
      source = ''
      processed_source = parse_source(source)

      expect(cop).to receive(:investigate).with(processed_source)
      expect(force).to receive(:investigate).with(processed_source)

      commissioner = described_class.new([cop], [force])

      commissioner.investigate(processed_source)
    end

    it 'stores all errors raised by the cops' do
      allow(cop).to receive(:on_int) { raise RuntimeError }

      commissioner = described_class.new([cop], [])
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

        commissioner = described_class.new([cop], [], raise_error: true)
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
end
