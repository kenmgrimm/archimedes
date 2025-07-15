# frozen_string_literal: true

module Neo4j
  module Import
    module NodeMatchers
      # Matcher for Asset nodes with specialized fuzzy matching for vehicles, equipment, etc.
      class AssetNodeMatcher < BaseNodeMatcher
        # Properties to include in the embedding text for similarity search
        def self.embedding_properties
          ["name", "model", "brand", "make", "serial_number", "license_plate", "description", "category"]
        end

        # Generate text for embedding that represents this asset
        def self.generate_embedding_text(properties)
          [
            properties["name"].to_s,
            properties["model"].to_s,
            properties["brand"].to_s,
            properties["make"].to_s,
            properties["serial_number"].to_s,
            properties["license_plate"].to_s,
            properties["description"].to_s,
            properties["category"].to_s
          ].compact_blank.join(" ").strip
        end

        # Define fuzzy matching methods to try in order
        def self.fuzzy_equality_methods
          [
            :exact_serial_number_match,
            :exact_unique_identifier_match,
            :brand_and_model_match,
            :asset_name_similarity_match
          ]
        end

        # Similarity threshold for asset matching
        def self.similarity_threshold
          0.8
        end

        # Match based on exact serial number
        def self.exact_serial_number_match(existing_props, new_props)
          existing_serial = existing_props["serial_number"].to_s.strip
          new_serial = new_props["serial_number"].to_s.strip

          return false if existing_serial.blank? || new_serial.blank?

          existing_serial.downcase == new_serial.downcase
        end

        # Match based on any unique identifier (license plate, VIN, part number, etc.)
        def self.exact_unique_identifier_match(existing_props, new_props)
          unique_fields = ["license_plate", "vin", "part_number", "registration", "barcode", "product_code"]

          unique_fields.each do |field|
            existing_value = existing_props[field].to_s.strip
            new_value = new_props[field].to_s.strip

            next if existing_value.blank? || new_value.blank?

            # Normalize by removing spaces and special characters for comparison
            existing_normalized = existing_value.gsub(/[^A-Z0-9]/i, "").upcase
            new_normalized = new_value.gsub(/[^A-Z0-9]/i, "").upcase

            return true if existing_normalized == new_normalized
          end

          false
        end

        # Match based on brand and model combination
        def self.brand_and_model_match(existing_props, new_props)
          existing_brand = extract_brand(existing_props)
          new_brand = extract_brand(new_props)
          existing_model = extract_model(existing_props)
          new_model = extract_model(new_props)

          # Try different combinations of brand/model matching

          # Case 1: Both have explicit brand and model
          if existing_brand.present? && new_brand.present? && existing_model.present? && new_model.present?
            brand_match = string_similar?(existing_brand, new_brand, 0.8)
            model_match = string_similar?(existing_model, new_model, 0.7)
            return true if brand_match && model_match
          end

          # Case 2: One has brand, other doesn't, but models match and names are similar
          if (existing_brand.present? || new_brand.present?) && existing_model.present? && new_model.present?
            model_match = string_similar?(existing_model, new_model, 0.7)
            name_similar = string_similar?(existing_props["name"].to_s, new_props["name"].to_s, 0.6)
            return true if model_match && name_similar
          end

          # Case 3: Cross-reference brand from one with model/name from other
          # e.g., "GMC Sierra 1500" matches "Truck" with model "Sierra"
          if existing_brand.present? && new_model.present?
            # Check if the brand appears in the other's name or model appears in the first's name
            brand_in_new_name = new_props["name"].to_s.downcase.include?(existing_brand.downcase)
            model_in_existing_name = existing_props["name"].to_s.downcase.include?(new_model.downcase)
            return true if brand_in_new_name || model_in_existing_name
          end

          if new_brand.present? && existing_model.present?
            brand_in_existing_name = existing_props["name"].to_s.downcase.include?(new_brand.downcase)
            model_in_new_name = new_props["name"].to_s.downcase.include?(existing_model.downcase)
            return true if brand_in_existing_name || model_in_new_name
          end

          false
        end

        # Match based on asset name similarity
        def self.asset_name_similarity_match(existing_props, new_props)
          existing_name = existing_props["name"].to_s.strip
          new_name = new_props["name"].to_s.strip

          return false if existing_name.blank? || new_name.blank?

          # Higher threshold for name-only matching
          string_similar?(existing_name, new_name, 0.85)
        end

        # Helper: Extract brand from asset properties (generic for any asset type)
        def self.extract_brand(props)
          brand_sources = [
            props["brand"],
            props["make"],
            props["manufacturer"],
            props["name"]
          ].compact.map(&:to_s)

          brand_sources.each do |source|
            # Try to extract any capitalized word that looks like a brand
            words = source.split(/\s+/)
            words.each do |word|
              # Skip common non-brand words
              next if word.downcase.match?(/^(the|and|or|of|for|with|model|type|size|inch|inches|mm|cm|kg|lb|lbs)$/i)

              # If it's a capitalized word or all caps, it's likely a brand
              return word.upcase if word.match?(/^[A-Z][A-Za-z]*$/) || word.match?(/^[A-Z]+$/)
            end
          end

          # If no obvious brand found, try to extract first meaningful word from name
          if props["name"].present?
            first_word = props["name"].split(/\s+/).first
            return first_word.upcase if first_word&.length&.> 2
          end

          nil
        end

        # Helper: Extract model from asset properties (generic for any asset type)
        def self.extract_model(props)
          [
            props["model"],
            props["name"],
            props["description"],
            props["product_name"]
          ].compact.map(&:to_s)

          # First try explicit model field
          return props["model"].strip if props["model"].present?

          # Then try to extract model from name
          if props["name"].present?
            name_words = props["name"].split(/\s+/)

            # If name has multiple words, try to find the model part
            if name_words.length > 1
              # Skip the first word (likely brand) and look for model indicators
              model_words = name_words[1..]

              # Look for patterns like numbers, model names, etc.
              model_words.each do |word|
                # Model often contains numbers or specific patterns
                return word if word.match?(/\d/) || word.length > 4
              end

              # Fall back to second word if no obvious model found
              return name_words[1] if name_words[1]
            end
          end

          nil
        end
      end
    end
  end
end
