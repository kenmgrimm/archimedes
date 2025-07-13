# frozen_string_literal: true

module Neo4j
  module Import
    module NodeMatchers
      # Default node matcher used when no specific matcher is available
      class DefaultNodeMatcher < BaseNodeMatcher
        class << self
          def fuzzy_equality_methods
            [
              :exact_id_match,
              :name_similarity_match
            ]
          end

          private

          def exact_id_match(props1, props2)
            props1["id"].present? && props1["id"] == props2["id"]
          end

          def name_similarity_match(props1, props2)
            name1 = props1["name"] || props1["title"]
            name2 = props2["name"] || props2["title"]

            return false if name1.blank? || name2.blank?

            string_similar?(name1, name2, 0.9)
          end
        end
      end
    end
  end
end
