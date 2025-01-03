# frozen_string_literal: true

desc "Backfill embeddings for all topics and posts"
task "ai:embeddings:backfill", %i[model concurrency] => [:environment] do |_, args|
  public_categories = Category.where(read_restricted: false).pluck(:id)

  if args[:model].present?
    strategy = DiscourseAi::Embeddings::Strategies::Truncation.new
    vector_rep =
      DiscourseAi::Embeddings::VectorRepresentations::Base.find_representation(args[:model]).new(
        strategy,
      )
  else
    vector_rep = DiscourseAi::Embeddings::VectorRepresentations::Base.current_representation
  end
  table_name = DiscourseAi::Embeddings::Schema::TOPICS_TABLE

  topics =
    Topic
      .joins("LEFT JOIN #{table_name} ON #{table_name}.topic_id = topics.id")
      .where("#{table_name}.topic_id IS NULL")
      .where("category_id IN (?)", public_categories)
      .where(deleted_at: nil)
      .order("topics.id DESC")

  Parallel.each(topics.all, in_processes: args[:concurrency].to_i, progress: "Topics") do |t|
    ActiveRecord::Base.connection_pool.with_connection do
      vector_rep.generate_representation_from(t)
    end
  end

  table_name = vector_rep.post_table_name
  posts =
    Post
      .joins("LEFT JOIN #{table_name} ON #{table_name}.post_id = posts.id")
      .where("#{table_name}.post_id IS NULL")
      .where(deleted_at: nil)
      .order("posts.id DESC")

  Parallel.each(posts.all, in_processes: args[:concurrency].to_i, progress: "Posts") do |t|
    ActiveRecord::Base.connection_pool.with_connection do
      vector_rep.generate_representation_from(t)
    end
  end
end
