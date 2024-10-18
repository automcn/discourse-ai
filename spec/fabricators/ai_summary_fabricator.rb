# frozen_string_literal: true

Fabricator(:ai_summary) do
  summarized_text "complete summary"
  original_content_sha "123"
  algorithm "test"
  target { Fabricate(:topic) }
  summary_type AiSummary.summary_types[:complete]
end

Fabricator(:topic_ai_gist, from: :ai_summary) do
  summarized_text "gist"
  summary_type AiSummary.summary_types[:gist]
end
