# frozen_string_literal: true

module Neo4j
  class DeduplicationService
    # Initialize the deduplication service
    # @param openai_client [OpenAI::Client] The OpenAI client for AI-assisted deduplication
    # @param logger [Logger] Logger instance for logging deduplication activities
    def initialize(openai_client, logger: nil)
      @openai_client = openai_client
      @logger = logger || Rails.logger
      @logger.level = Rails.env.production? ? Logger::INFO : Logger::DEBUG

      @logger.info("Initialized DeduplicationService with log level: #{@logger.level}")

      # Validate that the OpenAI client is properly configured
      return unless @openai_client.nil?

      @logger.warn("No OpenAI client provided. AI-assisted deduplication will be disabled.")
    end

    # Main method to deduplicate an entity
    # @param entity [Hash] The entity to deduplicate
    # @param entity_type [String] The type of the entity
    # @return [Hash, Neo4j::Node] The deduplicated entity (either the original or an existing duplicate node)
    def deduplicate(entity, entity_type)
      entity_name = entity["name"].to_s.strip
      entity_id = entity["id"].to_s
      entity_type = entity_type.to_s

      @logger.debug("\n#{'=' * 80}")
      @logger.debug("🔍 DEDUPLICATION START: #{entity_type} - #{entity_name} (ID: #{entity_id})")
      @logger.debug("-" * 80)

      begin
        # Log the entity being processed
        log_entity("Processing entity", entity, entity_type)

        # First, try to find potential duplicates
        @logger.debug("\n🔄 Searching for potential duplicates...")
        potential_duplicates = find_potential_duplicates(entity, entity_type)

        if potential_duplicates.empty?
          @logger.debug("\n✅ No potential duplicates found for #{entity_type}: #{entity_name}")
          @logger.debug("#{'=' * 80}\n")
          return entity
        end

        @logger.debug("\n🔍 Found #{potential_duplicates.size} potential #{'duplicate'.pluralize(potential_duplicates.size)} for #{entity_name}")
        log_potential_duplicates(potential_duplicates)

        # Use AI to determine if any of the potential duplicates are actual duplicates
        @logger.debug("\n🤖 Consulting AI for duplicate verification...")
        duplicate_node = check_for_duplicate(entity, potential_duplicates, entity_type)

        if duplicate_node
          @logger.debug("\n🔄 Found duplicate: #{duplicate_node[:name]} (ID: #{duplicate_node.id})")
          @logger.debug("   Original: #{entity_name} (ID: #{entity_id})")
          @logger.debug("#{'=' * 80}\n")
          return duplicate_node
        end

        @logger.debug("\n✅ No duplicates found for #{entity_type}: #{entity_name}")
        @logger.debug("#{'=' * 80}\n")
        entity
      rescue StandardError => e
        @logger.error("\n❌ ERROR during deduplication of #{entity_type} #{entity_name} (ID: #{entity_id}):")
        @logger.error("   #{e.class}: #{e.message}")
        if @logger.debug?
          @logger.error("   Backtrace:")
          e.backtrace.first(5).each { |line| @logger.error("     #{line}") }
        end
        @logger.debug("#{'=' * 80}\n")
        # Return the original entity on error
        entity
      end
    end

    # Find potential duplicates in the database
    # @param entity [Hash] The entity to find duplicates for
    # @param entity_type [String] The type of the entity
    # @return [Array<Neo4j::Node>] Array of potential duplicate nodes
    def find_potential_duplicates(entity, entity_type)
      entity_name = entity["name"].to_s.strip
      entity_type = entity_type.to_s # Ensure entity_type is a string

      @logger.debug("\n[#{Time.zone.now}] 🔍 Searching for potential duplicates of: #{entity_name.inspect} (Type: #{entity_type})")
      @logger.debug("Entity ID: #{entity['id'].inspect}")

      # Start with an empty array for matches
      matches = []

      # Try to find by name first (case-insensitive and partial matches)
      if entity_name.present?
        # 1. Exact match (case insensitive)
        exact_query = "MATCH (n) WHERE toLower(n.name) = $name AND any(label IN labels(n) WHERE toLower(label) = toLower($label)) RETURN n LIMIT 10"
        @logger.debug("  🔎 Executing exact name query: #{exact_query} with name: #{entity_name.downcase.inspect}, label: #{entity_type.downcase}")

        begin
          matches = Neo4j::ActiveBase.current_session.query(exact_query,
                                                            name: entity_name.downcase,
                                                            label: entity_type.downcase).map(&:n)

          log_matches("exact name", entity_name, matches)
        rescue StandardError => e
          @logger.error("  ❌ Error in exact name query: #{e.message}")
          @logger.error(e.backtrace.join("\n")) if @logger.debug?
        end

        # 2. Fuzzy match using CONTAINS if no exact matches found
        if matches.empty? && entity_name.length > 3
          partial_name = entity_name.split.first.downcase
          fuzzy_query = [
            "MATCH (n)",
            "WHERE toLower(n.name) CONTAINS toLower($partial_name)",
            "AND any(label IN labels(n) WHERE toLower(label) = toLower($label))",
            "RETURN n",
            "LIMIT 10"
          ].join(" ").freeze

          @logger.debug("  🔎 Executing fuzzy name query: #{fuzzy_query} with partial_name: #{partial_name.inspect}, label: #{entity_type.downcase}")

          begin
            fuzzy_matches = Neo4j::ActiveBase.current_session.query(fuzzy_query,
                                                                    partial_name: partial_name,
                                                                    label: entity_type.downcase).map(&:n)

            matches.concat(fuzzy_matches)
            log_matches("fuzzy name", partial_name, fuzzy_matches)
          rescue StandardError => e
            @logger.error("  ❌ Error in fuzzy name query: #{e.message}")
            @logger.error(e.backtrace.join("\n")) if @logger.debug?
          end
        end
      end

      # If still no matches, try other identifying properties
      if matches.empty? && entity["properties"].present?
        properties = parse_properties(entity["properties"])
        @logger.debug("  🔍 Checking additional properties: #{properties.keys.map(&:inspect).join(', ')}")

        # Try matching on serial number for assets
        if (serial = properties["serialNumber"].to_s.strip).present?
          query = [
            "MATCH (n)",
            "WHERE n.serialNumber = $serial",
            "OR (EXISTS(n.properties) AND n.properties.serialNumber = $serial)",
            "AND any(label IN labels(n) WHERE toLower(label) = toLower($label))",
            "RETURN n",
            "LIMIT 10"
          ].join(" ").freeze

          @logger.debug("  🔎 Executing serial number query: #{query} with serial: #{serial.inspect}, label: #{entity_type.downcase}")

          begin
            serial_matches = Neo4j::ActiveBase.current_session.query(query,
                                                                     serial: serial,
                                                                     label: entity_type.downcase).map(&:n)

            matches.concat(serial_matches)
            log_matches("serial number", serial, serial_matches)
          rescue StandardError => e
            @logger.error("  ❌ Error in serial number query: #{e.message}")
            @logger.error(e.backtrace.join("\n")) if @logger.debug?
          end
        end

        # Try matching on email for people
        if (email = properties["email"].to_s.strip).present?
          query = [
            "MATCH (n)",
            "WHERE toLower(n.email) = toLower($email)",
            "OR (EXISTS(n.properties) AND toLower(n.properties.email) = toLower($email))",
            "AND any(label IN labels(n) WHERE toLower(label) = toLower($label))",
            "RETURN n",
            "LIMIT 10"
          ].join(" ").freeze

          @logger.debug("  🔎 Executing email query: #{query} with email: #{email.downcase.inspect}, label: #{entity_type.downcase}")

          begin
            email_matches = Neo4j::ActiveBase.current_session.query(query,
                                                                    email: email.downcase,
                                                                    label: entity_type.downcase).map(&:n)

            matches.concat(email_matches)
            log_matches("email", email, email_matches)
          rescue StandardError => e
            @logger.error("  ❌ Error in email query: #{e.message}")
            @logger.error(e.backtrace.join("\n")) if @logger.debug?
          end
        end
      end

      # Remove nil values and duplicates (by Neo4j ID)
      matches = matches.compact.uniq { |node| node.respond_to?(:id) ? node.id : nil }.compact

      @logger.debug("  ✅ Found #{matches.size} potential #{'duplicate'.pluralize(matches.size)} for #{entity_name.inspect}")
      matches
    rescue StandardError => e
      @logger.error("Error finding potential duplicates: #{e.message}")
      @logger.error(e.backtrace.join("\n")) if @logger.debug?
      []
    end

    private

    # Use AI to determine if any of the potential duplicates are actual duplicates
    # @param entity [Hash] The new entity
    # @param potential_duplicates [Array<Neo4j::Node>] Potential duplicate entities
    # @param entity_type [String] The type of the entity
    # @return [Neo4j::Node, nil] The duplicate node if found, nil otherwise
    def check_for_duplicate(entity, potential_duplicates, entity_type)
      entity_name = entity["name"].to_s.strip
      entity_id = entity["id"].to_s

      @logger.debug("\n🤖 Starting AI duplicate check for: #{entity_name} (ID: #{entity_id})")
      @logger.debug("  Comparing against #{potential_duplicates.size} potential #{'duplicate'.pluralize(potential_duplicates.size)}")

      # Convert potential duplicates to hashes for the prompt
      duplicates_data = potential_duplicates.filter_map do |node|
        {
          id: node.id,
          name: node[:name] || (node.respond_to?(:properties) ? node.properties[:name] : nil),
          properties: if node.respond_to?(:properties)
                        node.properties.except(:id, :name, :created_at, :updated_at, :entity_type)
                      else
                        {}
                      end
        }.compact
      rescue StandardError => e
        @logger.error("  ❌ Error processing potential duplicate node: #{e.message}")
        nil
      end

      if duplicates_data.empty?
        @logger.debug("  ⚠️  No valid duplicate data to process")
        return nil
      end

      # Build the prompt for the AI
      @logger.debug("  📝 Building AI prompt...")
      prompt = build_duplicate_check_prompt(entity, duplicates_data, entity_type)
      @logger.debug("  📋 Prompt length: #{prompt.length} characters")

      # Call the AI to check for duplicates
      begin
        @logger.debug("  📡 Calling OpenAI API...")
        start_time = Time.zone.now

        response = @openai_client.chat(
          parameters: {
            model: "gpt-4",
            messages: [
              {
                role: "system",
                content: "You are a helpful assistant that identifies duplicate entities in a knowledge graph. " \
                         "Your response should be either 'NO_MATCH' or the ID of the matching duplicate."
              },
              {
                role: "user",
                content: prompt
              }
            ],
            temperature: 0.1,
            max_tokens: 50
          }
        )

        response_time = ((Time.zone.now - start_time) * 1000).round(2)

        # Extract and log the response
        ai_response = response.dig("choices", 0, "message", "content").to_s.strip
        usage = response["usage"] || {}

        @logger.debug("  ⚡ AI Response (in #{response_time}ms):")
        @logger.debug("  - Tokens Used: #{usage['total_tokens']} (Prompt: #{usage['prompt_tokens']}, Completion: #{usage['completion_tokens']})")
        @logger.debug("  - Response: #{ai_response.inspect}")

        # Parse the response to find the selected duplicate ID
        if ai_response.upcase == "NO_MATCH" || ai_response.empty?
          @logger.debug("  ✅ AI determined no duplicates found")
          return nil
        end

        # Try to find a matching duplicate by ID
        duplicate = potential_duplicates.find { |d| d.id.to_s == ai_response }

        if duplicate
          @logger.debug("  🔄 AI identified duplicate with ID: #{ai_response}")
          return duplicate
        else
          @logger.warn("  ⚠️  AI returned an invalid duplicate ID: #{ai_response.inspect}")
          @logger.debug("  Valid IDs: #{potential_duplicates.map(&:id).map(&:to_s).inspect}")
          return nil
        end
      rescue StandardError => e
        @logger.error("  ❌ Error calling OpenAI API: #{e.class}: #{e.message}")
        if @logger.debug?
          @logger.error("  Backtrace:")
          e.backtrace.first(5).each { |line| @logger.error("    #{line}") }
        end
      end

      # Extract and format entity details
      entity_name = entity["name"].to_s.strip
      entity_id = entity["id"].to_s
      entity_props = (entity["properties"] || {}).except("id", "name", "created_at", "updated_at")

      <<~PROMPT
        # Entity Deduplication Task

        ## Your Role
        You are an expert at identifying duplicate entities in a knowledge graph. Your task is to determine if the new entity is a duplicate of any existing entities.

        ## Entity Type
        #{entity_type}

        ## New Entity
        - ID: #{entity_id}
        - Name: #{entity_name}
        #{entity_props.map { |k, v| "- #{k}: #{v}" }.join("\n")}

        ## Potential Duplicates
        #{potential_duplicates.map.with_index(1) do |dup, idx|
          dup_name = dup[:name].to_s
          dup_id = dup[:id].to_s
          dup_props = (dup[:properties] || {}).reject { |_, v| v.nil? || v.to_s.empty? }
          # {'  '}
          "#{idx}. #{dup_name} (ID: #{dup_id})\n           #{dup_props.map { |k, v| "   - #{k}: #{v}" }.join("\n")}"
        end.join("\n\n")}

        ## Instructions
        1. Compare the new entity with each potential duplicate carefully.
        2. Consider the following when determining if they represent the same real-world entity:
           - Name similarity (including typos, abbreviations, nicknames)
           - Matching properties (emails, phone numbers, addresses, etc.)
           - Contextual clues from other properties
        3. Be cautious with common names that might be false positives.
        4. If you're not certain, prefer 'NO_MATCH' to avoid incorrect merges.

        ## Output Format
        Respond with ONLY one of the following:
        - 'NO_MATCH' if no duplicates are found
        - The exact ID of the matching duplicate (e.g., '12345')

        ## Important Notes
        - Your response must be exactly 'NO_MATCH' or a valid ID from the potential duplicates.
        - Do not include any explanations or additional text.
        - If multiple duplicates match, choose the one with the strongest match.

        ## Your Response
      PROMPT
    end

    # Parse properties from a string or return an empty hash
    def parse_properties(properties)
      return {} if properties.blank?

      if properties.is_a?(String)
        begin
          JSON.parse(properties)
        rescue StandardError
          {}
        end
      elsif properties.respond_to?(:to_h)
        properties.to_h
      else
        {}
      end
    end

    # Log entity information
    # @param action [String] The action being performed
    # @param entity [Hash, Neo4j::Node] The entity being processed
    # @param entity_type [String] The type of the entity
    def log_entity(action, entity, entity_type)
      if entity.is_a?(Hash)
        @logger.debug("#{action} #{entity_type}: #{entity['name']} (ID: #{entity['id']})")
        @logger.debug("  Properties: #{entity['properties'].inspect}") if entity["properties"].present?
      elsif entity.respond_to?(:[])
        @logger.debug("#{action} #{entity_type}: #{entity[:name]} (ID: #{entity.id})")
        props = entity.properties.except(:id, :name, :created_at, :updated_at, :entity_type)
        @logger.debug("  Properties: #{props.inspect}") unless props.empty?
      else
        @logger.debug("#{action} #{entity_type}: #{entity.inspect}")
      end
    end

    # Log potential duplicates
    # @param duplicates [Array<Neo4j::Node>] Array of potential duplicate nodes
    def log_potential_duplicates(duplicates)
      return if duplicates.empty?

      @logger.debug("\nPotential duplicates found:")
      duplicates.each_with_index do |node, i|
        @logger.debug("  #{i + 1}. #{node[:name]} (ID: #{node.id})")
        props = node.properties.except(:id, :name, :created_at, :updated_at, :entity_type)
        @logger.debug("     Properties: #{props.inspect}") unless props.empty?
      end
    end

    # Log when a duplicate is found
    # @param original [Hash] The original entity
    # @param duplicate [Neo4j::Node] The duplicate entity
    def log_duplicate_found(original, duplicate)
      @logger.debug("\n=== Duplicate Found ===")
      @logger.debug("Original: #{original['name']} (ID: #{original['id']})")
      @logger.debug("Duplicate: #{duplicate[:name]} (ID: #{duplicate.id})")

      @logger.debug("Original properties: #{original['properties'].inspect}") if original["properties"]

      return unless duplicate.properties

      @logger.debug("Duplicate properties: #{duplicate.properties.except(:id, :name, :created_at, :updated_at, :entity_type).inspect}")
    end

    # Log matches found by a specific field
    # @param field [String] The field that was matched on
    # @param value [String] The value that was matched
    # @param matches [Array<Neo4j::Node>] The matching nodes
    def log_matches(field, value, matches)
      if matches.empty?
        @logger.debug("  ⚠️  No matches found by #{field}: #{value.inspect}")
        return
      end

      @logger.debug("  🔍 Found #{matches.size} potential #{'duplicate'.pluralize(matches.size)} by #{field}: #{value.inspect}")

      matches.each_with_index do |match, i|
        # Safely get node properties and labels
        props = {}
        labels = []

        if match.respond_to?(:properties)
          props = match.properties.dup
          @logger.debug("    Node properties: #{props.inspect}")
        end

        if match.respond_to?(:labels)
          labels = Array(match.labels)
          @logger.debug("    Node labels: #{labels.inspect}")
        end

        # Extract name and ID safely
        match_name = props[:name] || props["name"] || "Unnamed"
        match_id = match.respond_to?(:id) ? match.id : "unknown"

        # Log basic info
        @logger.debug("    #{i + 1}. #{labels.join(':')} - #{match_name} (ID: #{match_id})")

        # Log additional properties for debugging
        if @logger.debug?
          # Exclude common properties to keep output clean
          excluded_keys = [:id, :name, :created_at, :updated_at, :entity_type]
          filtered_props = props.reject { |k, _| excluded_keys.include?(k.to_sym) }

          unless filtered_props.empty?
            @logger.debug("      Properties:")
            filtered_props.each do |k, v|
              @logger.debug("        #{k}: #{v.inspect}")
            end
          end

          # Log relationships if available
          if match.respond_to?(:query_as)
            begin
              rels = match.query_as(:n).match("(n)-[r]-(m)").pluck("type(r), m.name, m.id")
              unless rels.empty?
                @logger.debug("      Relationships:")
                rels.each do |type, name, id|
                  @logger.debug("        -[#{type}]-> #{name} (ID: #{id})")
                end
              end
            rescue StandardError => e
              @logger.debug("      Could not load relationships: #{e.message}")
            end
          end
        end

        @logger.debug("")
      rescue StandardError => e
        @logger.error("      ❌ Error logging match: #{e.message}")
        @logger.error("      #{e.backtrace.first}") if @logger.debug?
      end
    end
  end
end
