# frozen_string_literal: true

module DiscourseAi
  module Completions
    module Dialects
      class ChatGpt < Dialect
        class << self
          def can_translate?(model_name)
            %w[
              gpt-3.5-turbo
              gpt-4
              gpt-3.5-turbo-16k
              gpt-4-32k
              gpt-4-1106-preview
              gpt-4-turbo
            ].include?(model_name)
          end

          def tokenizer
            DiscourseAi::Tokenizer::OpenAiTokenizer
          end
        end

        def translate
          messages = prompt.messages

          # ChatGPT doesn't use an assistant msg to improve long-context responses.
          messages.pop if messages.last[:type] == :model

          trimmed_messages = trim_messages(messages)

          trimmed_messages.map do |msg|
            if msg[:type] == :system
              { role: "system", content: msg[:content] }
            elsif msg[:type] == :model
              { role: "assistant", content: msg[:content] }
            elsif msg[:type] == :tool_call
              call_details = JSON.parse(msg[:content], symbolize_names: true)
              call_details[:arguments] = call_details[:arguments].to_json

              {
                role: "assistant",
                content: nil,
                tool_calls: [{ type: "function", function: call_details, id: msg[:id] }],
              }
            elsif msg[:type] == :tool
              { role: "tool", tool_call_id: msg[:id], content: msg[:content] }
            else
              { role: "user", content: msg[:content] }.tap do |user_msg|
                user_msg[:name] = msg[:id] if msg[:id]
              end
            end
          end
        end

        def tools
          prompt.tools.map do |t|
            tool = t.dup

            tool[:parameters] = t[:parameters]
              .to_a
              .reduce({ type: "object", properties: {}, required: [] }) do |memo, p|
                name = p[:name]
                memo[:required] << name if p[:required]

                memo[:properties][name] = p.except(:name, :required, :item_type)

                memo[:properties][name][:items] = { type: p[:item_type] } if p[:item_type]
                memo
              end

            { type: "function", function: tool }
          end
        end

        def max_prompt_tokens
          # provide a buffer of 120 tokens - our function counting is not
          # 100% accurate and getting numbers to align exactly is very hard
          buffer = (opts[:max_tokens] || 2500) + 50

          if tools.present?
            # note this is about 100 tokens over, OpenAI have a more optimal representation
            @function_size ||= self.class.tokenizer.size(tools.to_json.to_s)
            buffer += @function_size
          end

          model_max_tokens - buffer
        end

        private

        def per_message_overhead
          # open ai defines about 4 tokens per message of overhead
          4
        end

        def calculate_message_token(context)
          self.class.tokenizer.size(context[:content].to_s + context[:name].to_s)
        end

        def model_max_tokens
          case model_name
          when "gpt-3.5-turbo-16k"
            16_384
          when "gpt-4"
            8192
          when "gpt-4-32k"
            32_768
          else
            8192
          end
        end
      end
    end
  end
end
