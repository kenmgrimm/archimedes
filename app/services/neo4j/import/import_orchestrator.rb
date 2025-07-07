# frozen_string_literal: true

require_relative "node_importer"
require_relative "relationship_importer"

module Neo4j
  module Import
    # Coordinates the import process
    class ImportOrchestrator
      def initialize(logger: nil, dry_run: false)
        @logger = logger || Rails.logger
        @dry_run = dry_run
        @node_importer = NodeImporter.new(logger: @logger, dry_run: dry_run)
        @relationship_importer = RelationshipImporter.new(logger: @logger, dry_run: dry_run)
      end

      # Imports data into Neo4j
      # @param data [Hash] Contains :entities and :relationships arrays
      # @return [Hash] Import statistics
      def import(data)
        log_header("Starting Neo4j Import")

        stats = {
          nodes: {},
          relationships: {},
          start_time: Time.current
        }

        # Import nodes first
        if data[:entities]&.any?
          log_info("\nImporting #{data[:entities].size} nodes...")
          stats[:nodes] = @node_importer.import(data[:entities])
        end

        # Then import relationships
        if data[:relationships]&.any?
          log_info("\nImporting #{data[:relationships].size} relationships...")

          # If we have a node mapping, use it to look up Neo4j internal IDs
          node_mapping = data[:node_mapping] || {}
          stats[:relationships] = @relationship_importer.import(data[:relationships], node_mapping)
        end

        # Calculate duration
        stats[:duration] = Time.current - stats[:start_time]

        log_summary(stats)
        stats
      end

      private

      def log_header(message)
        return unless @logger

        border = "=" * 80
        @logger.info("\n#{border}")
        @logger.info(message)
        @logger.info(border)
      end

      def log_info(message)
        @logger&.info(message)
      end

      def log_summary(stats)
        return unless @logger

        nodes = stats[:nodes]
        rels = stats[:relationships]

        @logger.info("\n#{'=' * 80}")
        @logger.info("IMPORT SUMMARY")
        @logger.info("=" * 80)

        if nodes
          @logger.info("\nNODES:")
          @logger.info("  Total:     #{nodes[:total]}")
          @logger.info("  Created:   #{nodes[:created]}")
          @logger.info("  Updated:   #{nodes[:updated]}")
          @logger.info("  Errors:    #{nodes[:errors]}")
        end

        if rels
          @logger.info("\nRELATIONSHIPS:")
          @logger.info("  Total:     #{rels[:total]}")
          @logger.info("  Created:   #{rels[:created]}")
          @logger.info("  Skipped:   #{rels[:skipped]}")
          @logger.info("  Errors:    #{rels[:errors]}")
        end

        @logger.info("\nDuration: #{format_duration(stats[:duration])}")
        @logger.info("=" * 80)
      end

      def format_duration(seconds)
        return "N/A" unless seconds

        if seconds < 1
          "#{(seconds * 1000).round(2)}ms"
        else
          "#{seconds.round(2)}s"
        end
      end
    end
  end
end
