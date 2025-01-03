# frozen_string_literal: true

RSpec.describe Jobs::GenerateRagEmbeddings do
  describe "#execute" do
    let(:vector_rep) { DiscourseAi::Embeddings::VectorRepresentations::Base.current_representation }

    let(:expected_embedding) { [0.0038493] * vector_rep.dimensions }

    fab!(:ai_persona)

    fab!(:rag_document_fragment_1) { Fabricate(:rag_document_fragment, target: ai_persona) }
    fab!(:rag_document_fragment_2) { Fabricate(:rag_document_fragment, target: ai_persona) }

    before do
      SiteSetting.ai_embeddings_enabled = true
      SiteSetting.ai_embeddings_discourse_service_api_endpoint = "http://test.com"

      WebMock.stub_request(
        :post,
        "#{SiteSetting.ai_embeddings_discourse_service_api_endpoint}/api/v1/classify",
      ).to_return(status: 200, body: JSON.dump(expected_embedding))
    end

    it "generates a new vector for each fragment" do
      expected_embeddings = 2

      subject.execute(fragment_ids: [rag_document_fragment_1.id, rag_document_fragment_2.id])

      embeddings_count =
        DB.query_single(
          "SELECT COUNT(*) from #{DiscourseAi::Embeddings::Schema::RAG_DOCS_TABLE}",
        ).first

      expect(embeddings_count).to eq(expected_embeddings)
    end

    describe "Publishing progress updates" do
      it "sends an update through mb after a batch finishes" do
        updates =
          MessageBus.track_publish("/discourse-ai/rag/#{rag_document_fragment_1.upload_id}") do
            subject.execute(fragment_ids: [rag_document_fragment_1.id])
          end

        upload_index_stats = updates.last.data

        expect(upload_index_stats[:total]).to eq(1)
        expect(upload_index_stats[:indexed]).to eq(1)
        expect(upload_index_stats[:left]).to eq(0)
      end
    end
  end
end
