# frozen_string_literal: true

module Neo4j
  module Importers
    module Relationships
      # Importer for ownership relationships (Person -> Item)
      class OwnershipImporter < BaseRelationshipImporter
        def self.handles
          "OWNS"
        end

        def property_mappings
          {
            startDate: :owned_since,
            endDate: :owned_until,
            percentage: :ownership_percentage,
            description: :notes
          }
        end

        private

        def validate_relationship
          super && validate_ownership_dates
        end

        def validate_ownership_dates
          return true unless @relationship_data["startDate"].present? && @relationship_data["endDate"].present?

          begin
            start_date = Date.parse(@relationship_data["startDate"])
            end_date = Date.parse(@relationship_data["endDate"])

            return add_error("End date cannot be before start date", @relationship_data) if end_date < start_date
          rescue ArgumentError => e
            return add_error("Invalid date format: #{e.message}", @relationship_data)
          end

          true
        end

        def find_existing_relationship
          source_node.owner_relationships
                     .where(to_node: target_node)
                     .where("owned_until IS NULL OR owned_until > ?", Date.current)
                     .first
        end

        def source_node
          @source_node ||= Person.find(@relationship_data["source_id"])
        end

        def target_node
          @target_node ||= Item.find(@relationship_data["target_id"])
        end
      end
    end
  end
end
