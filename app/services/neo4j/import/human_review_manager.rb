# frozen_string_literal: true

module Neo4j
  module Import
    # Manages human review queue for uncertain asset deduplication decisions
    class HumanReviewManager
      attr_reader :logger

      # Confidence thresholds for automatic decisions
      HIGH_CONFIDENCE_THRESHOLD = 0.9  # Auto-merge above this
      LOW_CONFIDENCE_THRESHOLD = 0.3   # Auto-reject below this
      # Between 0.3-0.9 requires human review

      def initialize(logger: nil)
        @logger = logger || Rails.logger
      end

      # Evaluate if assets should be merged, with human review for uncertain cases
      # @param existing_props [Hash] Properties of existing asset
      # @param new_props [Hash] Properties of new asset
      # @param matcher_class [Class] The node matcher class to use
      # @return [Hash] Decision result with action and confidence
      def evaluate_merge_decision(existing_props, new_props, matcher_class)
        # Calculate confidence score for the match
        confidence_score = calculate_confidence_score(existing_props, new_props, matcher_class)
        
        decision = {
          confidence: confidence_score,
          existing_props: existing_props,
          new_props: new_props,
          timestamp: Time.current
        }

        if confidence_score >= HIGH_CONFIDENCE_THRESHOLD
          decision[:action] = :auto_merge
          decision[:reason] = "High confidence match (#{confidence_score.round(2)})"
          log_info("Auto-merging assets: #{confidence_score.round(2)} confidence")
        elsif confidence_score <= LOW_CONFIDENCE_THRESHOLD
          decision[:action] = :auto_reject
          decision[:reason] = "Low confidence match (#{confidence_score.round(2)})"
          log_info("Auto-rejecting merge: #{confidence_score.round(2)} confidence")
        else
          decision[:action] = :human_review
          decision[:reason] = "Medium confidence requires human review (#{confidence_score.round(2)})"
          decision[:review_id] = queue_for_human_review(existing_props, new_props, confidence_score)
          log_info("Queuing for human review: #{confidence_score.round(2)} confidence")
        end

        decision
      end

      # Calculate a confidence score (0.0-1.0) for asset matching
      # @param existing_props [Hash] Properties of existing asset
      # @param new_props [Hash] Properties of new asset  
      # @param matcher_class [Class] The node matcher class to use
      # @return [Float] Confidence score between 0.0 and 1.0
      def calculate_confidence_score(existing_props, new_props, matcher_class)
        scores = []

        # Test each matching method and collect scores
        matcher_class.fuzzy_equality_methods.each do |method_name|
          begin
            match_result = matcher_class.send(method_name, existing_props, new_props)
            if match_result
              # Weight different match types differently
              weight = method_weight(method_name)
              method_score = calculate_method_confidence(method_name, existing_props, new_props)
              scores << { method: method_name, score: method_score, weight: weight }
            end
          rescue StandardError => e
            log_error("Error in #{method_name}: #{e.message}")
          end
        end

        return 0.0 if scores.empty?

        # Calculate weighted average confidence
        total_weighted_score = scores.sum { |s| s[:score] * s[:weight] }
        total_weight = scores.sum { |s| s[:weight] }
        
        confidence = total_weighted_score / total_weight
        
        # Apply modifiers based on data quality
        confidence = apply_data_quality_modifiers(confidence, existing_props, new_props)
        
        [confidence, 1.0].min # Cap at 1.0
      end

      private

      # Weight different matching methods by reliability
      def method_weight(method_name)
        weights = {
          exact_serial_number_match: 1.0,           # Highest reliability
          exact_unique_identifier_match: 0.95,     # Very high reliability  
          brand_and_model_match: 0.7,              # Medium-high reliability
          asset_name_similarity_match: 0.5         # Lower reliability
        }
        
        weights[method_name] || 0.5
      end

      # Calculate confidence for a specific matching method
      def calculate_method_confidence(method_name, existing_props, new_props)
        case method_name
        when :exact_serial_number_match, :exact_unique_identifier_match
          1.0 # Exact matches are 100% confident
        when :brand_and_model_match
          brand_confidence = calculate_brand_confidence(existing_props, new_props)
          model_confidence = calculate_model_confidence(existing_props, new_props)
          (brand_confidence + model_confidence) / 2.0
        when :asset_name_similarity_match
          calculate_name_similarity_confidence(existing_props, new_props)
        else
          0.5 # Default confidence for unknown methods
        end
      end

      # Calculate confidence for brand matching
      def calculate_brand_confidence(existing_props, new_props)
        existing_brand = extract_brand(existing_props)
        new_brand = extract_brand(new_props)
        
        return 0.3 if existing_brand.blank? || new_brand.blank?
        
        if existing_brand.downcase == new_brand.downcase
          1.0
        else
          # Use string similarity for fuzzy brand matching
          similarity = string_similarity(existing_brand, new_brand)
          [similarity, 0.3].max # Minimum 0.3 for any brand match attempt
        end
      end

      # Calculate confidence for model matching
      def calculate_model_confidence(existing_props, new_props)
        existing_model = extract_model(existing_props)
        new_model = extract_model(new_props)
        
        return 0.4 if existing_model.blank? || new_model.blank?
        
        if existing_model.downcase == new_model.downcase
          1.0
        else
          similarity = string_similarity(existing_model, new_model)
          [similarity, 0.4].max
        end
      end

      # Calculate confidence for name similarity
      def calculate_name_similarity_confidence(existing_props, new_props)
        existing_name = existing_props["name"].to_s
        new_name = new_props["name"].to_s
        
        return 0.1 if existing_name.blank? || new_name.blank?
        
        similarity = string_similarity(existing_name, new_name)
        
        # Lower confidence for name-only matching
        similarity * 0.8
      end

      # Apply modifiers based on data quality and completeness
      def apply_data_quality_modifiers(base_confidence, existing_props, new_props)
        modified_confidence = base_confidence

        # Boost confidence if both assets have multiple identifying properties
        existing_identifiers = count_identifying_properties(existing_props)
        new_identifiers = count_identifying_properties(new_props)
        
        if existing_identifiers >= 3 && new_identifiers >= 3
          modified_confidence += 0.1 # Boost for rich data
        elsif existing_identifiers <= 1 || new_identifiers <= 1
          modified_confidence -= 0.2 # Penalty for sparse data
        end

        # Penalty for very generic names
        if generic_name?(existing_props["name"]) || generic_name?(new_props["name"])
          modified_confidence -= 0.15
        end

        [modified_confidence, 0.0].max # Don't go below 0
      end

      # Count identifying properties in an asset
      def count_identifying_properties(props)
        identifying_fields = %w[serial_number license_plate vin part_number barcode brand model name]
        identifying_fields.count { |field| props[field].present? }
      end

      # Check if name is too generic for reliable matching
      def generic_name?(name)
        return false if name.blank?
        
        generic_names = %w[truck car vehicle bike item asset equipment tool part component]
        generic_names.any? { |generic| name.downcase.strip == generic }
      end

      # Queue asset pair for human review
      def queue_for_human_review(existing_props, new_props, confidence_score)
        review_id = SecureRandom.uuid
        
        review_record = {
          id: review_id,
          existing_asset: existing_props,
          new_asset: new_props,
          confidence_score: confidence_score,
          status: 'pending',
          created_at: Time.current,
          reviewed_at: nil,
          reviewer: nil,
          decision: nil,
          notes: nil
        }

        # Store in database or file system for human review
        store_review_record(review_record)
        
        review_id
      end

      # Store review record (implement based on your storage preference)
      def store_review_record(review_record)
        # Option 1: Store in database
        # HumanReview.create!(review_record)
        
        # Option 2: Store in JSON file for simple implementation
        reviews_file = Rails.root.join('tmp', 'human_reviews.json')
        existing_reviews = File.exist?(reviews_file) ? JSON.parse(File.read(reviews_file)) : []
        existing_reviews << review_record
        File.write(reviews_file, JSON.pretty_generate(existing_reviews))
        
        log_info("Stored review record: #{review_record[:id]}")
      end

      # Helper methods (delegate to AssetNodeMatcher for consistency)
      def extract_brand(props)
        Neo4j::Import::NodeMatchers::AssetNodeMatcher.extract_brand(props)
      end

      def extract_model(props)
        Neo4j::Import::NodeMatchers::AssetNodeMatcher.extract_model(props)
      end

      def string_similarity(str1, str2)
        # Simple Levenshtein similarity (you might want to use a gem like 'fuzzy_match')
        return 1.0 if str1 == str2
        return 0.0 if str1.blank? || str2.blank?
        
        str1, str2 = str1.downcase, str2.downcase
        longer = str1.length > str2.length ? str1 : str2
        shorter = str1.length > str2.length ? str2 : str1
        
        return 1.0 if longer.length.zero?
        
        edit_distance = levenshtein_distance(longer, shorter)
        (longer.length - edit_distance).to_f / longer.length
      end

      def levenshtein_distance(str1, str2)
        matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }
        
        (0..str1.length).each { |i| matrix[i][0] = i }
        (0..str2.length).each { |j| matrix[0][j] = j }
        
        (1..str1.length).each do |i|
          (1..str2.length).each do |j|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,
              matrix[i][j - 1] + 1,
              matrix[i - 1][j - 1] + cost
            ].min
          end
        end
        
        matrix[str1.length][str2.length]
      end

      def log_info(message)
        @logger&.info("[HumanReviewManager] #{message}")
      end

      def log_error(message)
        @logger&.error("[HumanReviewManager] #{message}")
      end
    end
  end
end