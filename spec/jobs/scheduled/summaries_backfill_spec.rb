# frozen_string_literal: true

RSpec.describe Jobs::SummariesBackfill do
  fab!(:topic) { Fabricate(:topic, word_count: 200, highest_post_number: 2) }
  let(:limit) { 24 } # guarantee two summaries per batch
  let(:intervals) { 12 } # budget is split into intervals. Job runs every five minutes.

  before do
    assign_fake_provider_to(:ai_summarization_model)
    SiteSetting.ai_summarization_enabled = true
    SiteSetting.ai_summary_backfill_maximum_topics_per_hour = limit
  end

  describe "#current_budget" do
    let(:type) { AiSummary.summary_types[:complete] }

    context "when no summary has been backfilled yet" do
      it "returns the full budget" do
        expect(subject.current_budget(type)).to eq(limit / intervals)
      end

      it "ignores summaries generated by users" do
        Fabricate(:ai_summary, target: topic, origin: AiSummary.origins[:human])

        expect(subject.current_budget(type)).to eq(limit / intervals)
      end

      it "only accounts for summaries of the given type" do
        Fabricate(:topic_ai_gist, target: topic, origin: AiSummary.origins[:human])

        expect(subject.current_budget(type)).to eq(limit / intervals)
      end
    end
  end

  describe "#backfill_candidates" do
    let(:type) { AiSummary.summary_types[:complete] }

    it "only selects posts with enough words" do
      topic.update!(word_count: 100)

      expect(subject.backfill_candidates(type)).to be_empty
    end

    it "ignores up to date summaries" do
      Fabricate(:ai_summary, target: topic, content_range: (1..2))

      expect(subject.backfill_candidates(type)).to be_empty
    end

    it "orders candidates by topic#last_posted_at" do
      topic.update!(last_posted_at: 1.minute.ago)
      topic_2 = Fabricate(:topic, word_count: 200, last_posted_at: 2.minutes.ago)

      expect(subject.backfill_candidates(type).map(&:id)).to contain_exactly(topic.id, topic_2.id)
    end

    it "prioritizes topics without summaries" do
      topic_2 =
        Fabricate(:topic, word_count: 200, last_posted_at: 2.minutes.ago, highest_post_number: 1)
      topic.update!(last_posted_at: 1.minute.ago)
      Fabricate(:ai_summary, target: topic, content_range: (1..1))

      expect(subject.backfill_candidates(type).map(&:id)).to contain_exactly(topic_2.id, topic.id)
    end
  end

  describe "#execute" do
    it "backfills a batch" do
      topic_2 =
        Fabricate(:topic, word_count: 200, last_posted_at: 2.minutes.ago, highest_post_number: 1)
      topic.update!(last_posted_at: 1.minute.ago)
      Fabricate(:ai_summary, target: topic, created_at: 3.hours.ago, content_range: (1..1))
      Fabricate(:topic_ai_gist, target: topic, created_at: 3.hours.ago, content_range: (1..1))

      summary_1 = "Summary of topic_2"
      gist_1 = "Gist of topic_2"
      summary_2 = "Summary of topic"
      gist_2 = "Gist of topic"

      DiscourseAi::Completions::Llm.with_prepared_responses(
        [summary_1, summary_2, gist_1, gist_2],
      ) { subject.execute({}) }

      expect(AiSummary.complete.find_by(target: topic_2).summarized_text).to eq(summary_1)
      expect(AiSummary.gist.find_by(target: topic_2).summarized_text).to eq(gist_1)
      expect(AiSummary.complete.find_by(target: topic).summarized_text).to eq(summary_2)
      expect(AiSummary.gist.find_by(target: topic).summarized_text).to eq(gist_2)
    end
  end
end