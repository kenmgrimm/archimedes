# frozen_string_literal: true

module Neo4j
  module Import
    module NodeMatchers
      # Matcher for Person nodes with specialized fuzzy matching for people
      class PersonNodeMatcher < BaseNodeMatcher
        # Properties to include in the embedding text for similarity search
        def self.embedding_properties
          ["full_name", "first_name", "last_name", "name", "email", "phone", "phone_number", "title", "company_name"]
        end

        # Generate text for embedding that represents this person
        def self.generate_embedding_text(properties)
          # Prioritize full_name, but fall back to combining first and last, then name
          name = properties["full_name"].to_s
          name = "#{properties['first_name']} #{properties['last_name']}".strip if name.blank?
          name = properties["name"].to_s if name.blank?

          # Include other identifying information
          [
            name,
            properties["email"].to_s,
            properties["phone"].to_s,
            properties["phone_number"].to_s,
            properties["title"].to_s,
            properties["company_name"].to_s
          ].reject(&:blank?).join(" ").strip
        end

        # Define fuzzy matching methods to try in order
        def self.fuzzy_equality_methods
          [
            :exact_email_match,
            :exact_phone_match,
            :full_name_email_domain_match,
            :full_name_similarity_match,
            :last_name_first_initial_match
          ]
        end

        # Similarity threshold for person matching (0.0-1.0)
        def self.similarity_threshold
          0.85 # Higher threshold for person matching as names can be common
        end

        # Match nodes based on exact email match (most reliable)
        def self.exact_email_match(existing_props, new_props)
          return false if existing_props["email"].blank? || new_props["email"].blank?

          existing_email = existing_props["email"].to_s.downcase.strip
          new_email = new_props["email"].to_s.downcase.strip

          existing_email == new_email && existing_email.present?
        end

        # Match nodes based on exact phone match (without formatting)
        def self.exact_phone_match(existing_props, new_props)
          existing_phone = existing_props["phone"].to_s.strip
          existing_phone = existing_props["phone_number"].to_s.strip if existing_phone.blank?
          
          new_phone = new_props["phone"].to_s.strip
          new_phone = new_props["phone_number"].to_s.strip if new_phone.blank?
          
          return false if existing_phone.blank? || new_phone.blank?

          # Normalize phone numbers by removing non-digit characters
          existing_phone = existing_phone.gsub(/\D/, "")
          new_phone = new_phone.gsub(/\D/, "")

          # Consider it a match if either is a substring of the other (accounting for country codes)
          (existing_phone.include?(new_phone) || new_phone.include?(existing_phone)) &&
            [existing_phone.length, new_phone.length].min >= 8 # At least 8 digits to avoid false positives
        end

        # Match based on full name and email domain
        def self.full_name_email_domain_match(existing_props, new_props)
          return false if existing_props["email"].blank? || new_props["email"].blank?

          # Extract domains
          existing_domain = begin
            existing_props["email"].to_s.split("@").last.downcase
          rescue StandardError
            ""
          end
          new_domain = begin
            new_props["email"].to_s.split("@").last.downcase
          rescue StandardError
            ""
          end

          # If domains match, check name similarity
          if existing_domain == new_domain && existing_domain.present?
            existing_name = full_name(existing_props)
            new_name = full_name(new_props)

            return false if existing_name.blank? || new_name.blank?

            # Use string similarity to compare names
            string_similar?(existing_name, new_name, 0.8) # Slightly more lenient since we have domain match
          else
            false
          end
        end

        # Match based on full name similarity
        def self.full_name_similarity_match(existing_props, new_props)
          existing_name = full_name(existing_props)
          new_name = full_name(new_props)

          return false if existing_name.blank? || new_name.blank?

          # Use string similarity to compare names
          string_similar?(existing_name, new_name, 0.9) # High threshold for name-only matching
        end

        # Match based on last name and first initial
        def self.last_name_first_initial_match(existing_props, new_props)
          existing_last = existing_props["last_name"].to_s.downcase.strip
          new_last = new_props["last_name"].to_s.downcase.strip

          # Need at least last name to match
          return false if existing_last.blank? || new_last.blank?

          # Check last name match with some fuzziness
          last_name_similar = string_similar?(existing_last, new_last, 0.9)

          # If last names match, check first initial
          if last_name_similar
            existing_first = begin
              existing_props["first_name"].to_s.downcase.strip[0]
            rescue StandardError
              ""
            end
            new_first = begin
              new_props["first_name"].to_s.downcase.strip[0]
            rescue StandardError
              ""
            end

            # Either first initial matches, or one is missing
            existing_first.blank? || new_first.blank? || existing_first == new_first
          else
            false
          end
        end

        # Helper to get full name from properties
        def self.full_name(props)
          return props["full_name"] if props["full_name"].present?
          return props["name"] if props["name"].present?

          first = props["first_name"].to_s.strip
          last = props["last_name"].to_s.strip

          [first, last].reject(&:blank?).join(" ")
        end
      end
    end
  end
end
