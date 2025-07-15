module Neo4j
  class ChatService
    def initialize(query)
      @query = query
      @prompt = TTY::Prompt.new
      @logger = Rails.logger

      begin
        @taxonomy_service = Neo4j::TaxonomyService.new
        @logger.debug { "ChatService: Loading taxonomy via TaxonomyService" }
        @logger.debug { "ChatService: Taxonomy loaded with entity types: #{@taxonomy_service.entity_types}" }

        @current_user = User.current.full_name
        @logger.debug { "ChatService: Initialized with user: #{@current_user}" }
      rescue StandardError => e
        @logger.error { "ChatService: Error in initialize: #{e.class} - #{e.message}" }
        @logger.error { "ChatService: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
        raise
      end
    end

    def execute
      @logger.debug { "ChatService: Starting chat with query: #{@query.inspect}" }
      @logger.debug { "ChatService: Current user: #{@current_user.inspect}" }
      @logger.debug { "ChatService: Taxonomy service loaded: #{@taxonomy_service.present?}" }

      # Step 1: Analyze intent
      @logger.debug { "ChatService: Analyzing intent..." }
      @intent = Chat::IntentAnalyzer.new(@query, @taxonomy_service).analyze
      @logger.debug { "ChatService: Intent analysis result: #{Chat::Utils.clean_embeddings(@intent.inspect)}" }

      if @intent["clarification_needed"]
        question = @intent["clarification_question"].to_s
        @logger.debug { "ChatService: Asking for clarification: #{question}" }

        begin
          question = question.presence || "Could you clarify what you mean?"
          @logger.debug { "ChatService: Asking question: #{question}" }
          answer = @prompt.ask_safely(question, default: "all")
          @logger.debug { "ChatService: Got answer: #{answer}" }

          # Get new intent based on original query + clarification
          updated_query = "#{@query} - #{answer}"
          @logger.debug { "ChatService: Updating intent with answer: #{updated_query}" }
          @intent = Chat::IntentAnalyzer.new(updated_query, @taxonomy_service).analyze
          @logger.debug { "ChatService: Updated intent: #{Chat::Utils.clean_embeddings(@intent.inspect)}" }
        rescue TTY::Reader::InputInterrupt
          @logger.info { "ChatService: User interrupted input" }
          return "Query cancelled"
        rescue StandardError => e
          @logger.error { "ChatService: Error in prompt: #{e.class} - #{e.message}" }
          @logger.error { "ChatService: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
          return "Sorry, there was an error processing your input"
        end
      end

      # Step 2: Plan and execute queries
      @logger.debug { "ChatService: Planning queries..." }
      query_plan = Chat::QueryPlanner.new(@intent, @taxonomy_service).plan_queries
      @logger.debug { "ChatService: Query plan: #{query_plan.inspect}" }

      # Step 3: Execute queries and gather results
      results = []
      read_results = {}

      query_plan.reject { |step| step["write"] }.each do |step|
        @logger.debug { "ChatService: Executing query step: #{step['description']}" }

        begin
          @logger.info { "ChatService: Proposing query: #{step['description']}" }
          @prompt.say_safely("\nProposed query: #{step['description']}")
          @prompt.say_safely(TTY::Box.frame(step["query"]))

          next unless @prompt.yes_safely?("Execute this query?")
        rescue TTY::Reader::InputInterrupt
          @logger.info { "ChatService: User interrupted input" }
          return "Query cancelled"
        rescue StandardError => e
          @logger.error { "ChatService: Error in prompt: #{e.class} - #{e.message}" }
          @logger.error { "ChatService: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
          return "Sorry, there was an error processing your input"
        end

        begin
          tx_type = step["write"] ? :write_transaction : :read_transaction
          query_results = Neo4j::DatabaseService.send(tx_type) do |tx|
            params = step["params"] || { name: User.current.full_name }
            @logger.debug { "ChatService: Running query with params: #{params.inspect}" }
            Rails.logger.debug step["query"]
            Rails.logger.debug params
            results = tx.run(step["query"], **params).to_a
            @logger.debug { "ChatService: Raw Neo4j results: #{Chat::Utils.clean_embeddings(results.inspect)}" }
            results.map(&:to_h)
          end
          @logger.info { "ChatService: Query results: #{Chat::Utils.clean_embeddings(query_results.inspect)}" }

          # Show any results we found before proceeding
          unless query_results.empty?
            @prompt.say("\nFound relationships:")
            query_results.each do |r|
              # Handle standardized relationship query results
              # Format should be: {"type(r)" => "RELATIONSHIP_TYPE", "startNode(r)" => node1, "endNode(r)" => node2}

              # First try with symbol keys
              type = r[:"type(r)"] || r["type(r)"]

              if type && r[:"startNode(r)"] && r[:"endNode(r)"]
                # Standard relationship format
                start_node = r[:"startNode(r)"] || r["startNode(r)"]
                end_node = r[:"endNode(r)"] || r["endNode(r)"]
                rel_id = r[:"id(r)"] || r["id(r)"]

                source_name = start_node.properties[:name]
                target_name = end_node.properties[:name]

                @prompt.say("- [#{rel_id}] #{source_name} #{type} #{target_name}")
              else
                # Non-standard format, display as key-value pairs
                @logger.warn { "Non-standard query result format: #{r.inspect}" }
                r.each do |k, v|
                  if v.is_a?(Neo4j::Driver::Internal::InternalNode)
                    node_name = begin
                      v.properties[:name]
                    rescue StandardError
                      v.to_s
                    end
                    @prompt.say("- #{k}: #{node_name}")
                  else
                    @prompt.say("- #{k}: #{v}")
                  end
                end
              end
            end
          end

          result = {
            "query" => step["query"],
            "description" => step["description"],
            "results" => query_results,
            "empty_message" => query_results.empty? ? step.dig("next_steps", "if_empty") : nil
          }
          # Store read results by relationship type
          relationship_type = step["relationship_type"]
          read_results[relationship_type] = query_results
          @logger.debug { "ChatService: Read results for #{relationship_type}: #{Chat::Utils.clean_embeddings(query_results.inspect)}" }

          results << result
        rescue StandardError => e
          @logger.error { "ChatService: Error executing query: #{e.class} - #{e.message}" }
          @logger.error { "ChatService: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
          raise
        end
      end

      # Step 4: Execute any write operations
      write_plan = query_plan.select { |step| step["write"] }
      @logger.debug { "ChatService: Write operations: #{write_plan.inspect}" }

      write_plan.each do |step|
        # Extract operation type and target ID
        operation_type = step["operation"] || "create"
        target_id = step["target_id"] || @intent.dig("intent", "target_id")

        # Initialize params hash with target_id if available
        params = {}
        params[:target_id] = target_id.to_i if target_id

        # Collect required information for write operations
        if step["required_info"].is_a?(Array) && step["required_info"].any?
          @logger.debug { "ChatService: Collecting required info: #{step['required_info'].inspect}" }

          # Each required_info entry is a property name to update
          step["required_info"].each do |property|
            prompt_text = "Enter new value for #{property}:"
            value = @prompt.ask(prompt_text)
            params[property.to_sym] = value
          end

          @logger.debug { "ChatService: Collected params: #{params.inspect}" }
        end

        # Store params in the step for execution
        step["params"] = params

        # Don't prompt for actions unless the user's intent indicates they want to modify data
        next unless @intent.dig("intent", "action_type") == "modify"

        # Show the user what we're about to do
        @logger.debug { "ChatService: Preparing write operation" }
        @prompt.say_safely("\nProposed #{operation_type} operation: #{step['description']}")
        @prompt.say_safely(TTY::Box.frame(step["query"]))

        # Show the parameters we've collected
        if step["params"].any?
          @prompt.say_safely("\nParameters:")
          step["params"].each do |key, value|
            @prompt.say_safely("- #{key}: #{value}")
          end
        end

        # Confirm before executing
        @prompt.say_safely("\n⚠️  This is a WRITE operation that will modify the database!")
        next unless @prompt.yes?("Proceed with this operation?")

        debugger

        # Execute the write query with the collected parameters
        @logger.debug { "ChatService: Executing write query: #{step['query']}" }
        @logger.debug { "ChatService: With params: #{step['params'].inspect}" }

        begin
          # Add comprehensive debug logging
          @logger.info { "ChatService: Executing #{operation_type} operation" }

          # First verify the node exists
          @logger.info { "ChatService: Verifying target node exists" }
          verify_results = Neo4j::DatabaseService.read_transaction do |tx|
            verify_query = "MATCH (n) WHERE elementId(n) = $target_id RETURN n"
            # Use the full elementId from the query
            element_id = step["query"].match(/elementId\(n\) = '([^']+)'/)[1]
            verify_params = { target_id: element_id }
            @logger.debug { "ChatService: Verifying node with params: #{verify_params.inspect}" }
            tx.run(verify_query, **verify_params).to_a
          end

          if verify_results.empty?
            target_id = step["params"][:target_id]
            @logger.error { "ChatService: Node with ID #{target_id} not found" }
            @prompt.say("\n⚠️  Error: Node with ID #{target_id} does not exist.")
            next
          end

          # Execute the write query
          @logger.info { "ChatService: About to execute write query" }
          write_results = Neo4j::DatabaseService.write_transaction do |tx|
            # Convert string keys to symbols if needed by Neo4j driver
            query_params = step["params"].transform_keys(&:to_sym)
            # Use the full elementId from the query
            if query_params[:target_id]
              element_id = step["query"].match(/elementId\(n\) = '([^']+)'/)[1]
              query_params[:target_id] = element_id
            end
            @logger.debug { "ChatService: Final query params: #{query_params.inspect}" }

            @logger.debug { "ChatService: Write query: #{step['query'].inspect}" }
            @logger.debug { "ChatService: With params (before conversion): #{query_params.inspect}" }

            results = tx.run(step["query"], **query_params).to_a
            @logger.info { "ChatService: Query executed with results: #{results.inspect}" }
            results.map(&:to_h)
          end
          results << {
            "query" => step["query"],
            "description" => step["description"],
            "results" => write_results
          }
        rescue StandardError => e
          @logger.error { "ChatService: Error executing write query: #{e.class} - #{e.message}" }
          @logger.error { "ChatService: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
          raise
        end
      end

      # Step 5: Generate final response
      @logger.debug { "ChatService: Interpreting results..." }
      @logger.debug { "ChatService: Final results: #{Chat::Utils.clean_embeddings(results.inspect)}" }
      interpretation = Chat::ResponseGenerator.new(@intent, results, @taxonomy_service).generate
      @logger.debug { "ChatService: Interpretation: #{interpretation.inspect}" }

      # Show interpreted response and follow-ups
      raise "Invalid response format" unless interpretation.is_a?(Hash) && interpretation["response"]

      @prompt.say("\n#{interpretation['response']}")
      if interpretation["follow_ups"].any?
        @prompt.say("\nSuggested follow-ups:")
        interpretation["follow_ups"].each { |f| @prompt.say("- #{f}") }
      end

      interpretation["response"]
    rescue TTY::Reader::InputInterrupt
      @logger.info { "ChatService: User interrupted input" }
      "Query cancelled"
    rescue StandardError => e
      @logger.error { "ChatService: Unhandled error in execute: #{e.class} - #{e.message}" }
      @logger.error { "ChatService: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
      raise
    end
  end
end
