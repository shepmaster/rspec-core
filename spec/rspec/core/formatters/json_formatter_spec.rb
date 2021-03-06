require 'rspec/core/formatters/json_formatter'
require 'json'
require 'rspec/core/reporter'

# todo, someday:
# it "lists the groups (describe and context) separately"
# it "includes full 'execution_result'"
# it "relativizes backtrace paths"
# it "includes profile information (implements dump_profile)"
# it "shows the pending message if one was given"
# it "shows the seed if run was randomized"
# it "lists pending specs that were fixed"
RSpec.describe RSpec::Core::Formatters::JsonFormatter do
  include FormatterSupport

  it "can be loaded via `--format json`" do
    formatter_output = run_example_specs_with_formatter("json", false)
    parsed = JSON.parse(formatter_output)
    expect(parsed.keys).to include("examples", "summary", "summary_line")
  end

  it "outputs expected json (brittle high level functional test)" do
    group = RSpec.describe("one apiece") do
      it("succeeds") { expect(1).to eq 1 }
      it("fails") { fail "eek" }
      it("pends") { pending "world peace"; fail "eek" }
    end
    succeeding_line = __LINE__ - 4
    failing_line = __LINE__ - 4
    pending_line = __LINE__ - 4

    now = Time.now
    allow(Time).to receive(:now).and_return(now)
    reporter.report(2) do |r|
      group.run(r)
    end

    # grab the actual backtrace -- kind of a cheat
    examples = formatter.output_hash[:examples]
    failing_backtrace = examples[1][:exception][:backtrace]
    this_file = relative_path(__FILE__)

    expected = {
      :examples => [
        {
          :description => "succeeds",
          :full_description => "one apiece succeeds",
          :status => "passed",
          :file_path => this_file,
          :line_number => succeeding_line,
          :run_time => formatter.output_hash[:examples][0][:run_time]
        },
        {
          :description => "fails",
          :full_description => "one apiece fails",
          :status => "failed",
          :file_path => this_file,
          :line_number => failing_line,
          :run_time => formatter.output_hash[:examples][1][:run_time],
          :exception => {
            :class     => "RuntimeError",
            :message   => "eek",
            :backtrace => failing_backtrace
          }
        },
        {
          :description => "pends",
          :full_description => "one apiece pends",
          :status => "pending",
          :file_path => this_file,
          :line_number => pending_line,
          :run_time => formatter.output_hash[:examples][2][:run_time]
        },
      ],
      :summary => {
        :duration => formatter.output_hash[:summary][:duration],
        :example_count => 3,
        :failure_count => 1,
        :pending_count => 1,
      },
      :summary_line => "3 examples, 1 failure, 1 pending"
    }
    expect(formatter.output_hash).to eq expected
    expect(output.string).to eq expected.to_json
  end

  describe "#stop" do
    it "adds all examples to the output hash" do
      send_notification :stop, stop_notification
      expect(formatter.output_hash[:examples]).not_to be_nil
    end
  end

  describe "#close" do
    it "outputs the results as a JSON string" do
      expect(output.string).to eq ""
      send_notification :close, null_notification
      expect(output.string).to eq("{}")
    end
  end

  describe "#message" do
    it "adds a message to the messages list" do
      send_notification :message, message_notification("good job")
      expect(formatter.output_hash[:messages]).to eq ["good job"]
    end
  end

  describe "#dump_summary" do
    it "adds summary info to the output hash" do
      send_notification :dump_summary, summary_notification(1.0, examples(10), examples(3), examples(4), 0)
      expect(formatter.output_hash[:summary]).to include(
        :duration => 1.0, :example_count => 10, :failure_count => 3,
        :pending_count => 4
      )
      summary_line = formatter.output_hash[:summary_line]
      expect(summary_line).to eq "10 examples, 3 failures, 4 pending"
    end
  end

  describe "#dump_profile", :slow do

    def profile *groups
      groups.each { |group| group.run(reporter) }
      examples = groups.map(&:examples).flatten
      send_notification :dump_profile, profile_notification(0.5, examples, 10)
    end

    before do
      formatter
      config.profile_examples = 10
    end

    context "with one example group" do
      before do
        profile( RSpec.describe("group") do
          example("example") { }
        end)
      end

      it "names the example" do
        expect(formatter.output_hash[:profile][:examples].first[:full_description]).to eq("group example")
      end

      it "provides example execution time" do
        expect(formatter.output_hash[:profile][:examples].first[:run_time]).not_to be_nil
      end

      it "doesn't profile a single example group" do
        expect(formatter.output_hash[:profile][:groups]).to be_empty
      end

      it "has the summary of profile information" do
        expect(formatter.output_hash[:profile].keys).to match_array([:examples, :groups, :slowest, :total])
      end
    end

    context "with multiple example groups", :slow do
      before do
        example_clock = class_double(RSpec::Core::Time, :now => RSpec::Core::Time.now + 0.5)

        group1 = RSpec.describe("slow group") do
          example("example") do |example|
            # make it look slow without actually taking up precious time
            example.clock = example_clock
          end
        end
        group2 = RSpec.describe("fast group") do
          example("example 1") { }
          example("example 2") { }
        end
        profile group1, group2
      end

      it "provides the slowest example groups" do
        expect(formatter.output_hash).not_to be_empty
      end

      it "provides information" do
        expect(formatter.output_hash[:profile][:groups].first.keys).to match_array([:total_time, :count, :description, :average, :location])
      end

      it "ranks the example groups by average time" do
        expect(formatter.output_hash[:profile][:groups].first[:description]).to eq("slow group")
      end
    end
  end
end
