# Comprehensive Weaviate Ingestion: Kaiser Soze Biography & Details
#
# This script ingests all structured content from the Kaiser Soze biography markdown:
# - People, pets, home, vehicles, projects, documents, shopping lists, project details, etc.
# - Creates schema classes, inserts entities, and establishes relationships with debug logging.
#
# Requires: gem 'weaviate-ruby', running Weaviate instance on localhost:8080

require "weaviate"
require_relative "concerns/weaviate_cleanup"
require_relative "concerns/weaviate_visualization"

class WeaviateService
  include WeaviateCleanup
  include WeaviateVisualization

  def initialize
    @logger = Logger.new($stdout)
    @logger.level = Logger::DEBUG
    @client = Weaviate::Client.new(url: "http://localhost:8080")
  end

  # --- 1. Create Schema Classes ---
  def ensure_class(class_name, properties, description = nil)
    return if @client.schema.list["classes"].any? { |c| c["class"] == class_name }

    @logger.debug("Creating class #{class_name}")
    @client.schema.create(
      class_name: class_name,
      description: description,
      properties: properties,
      vectorizer: "text2vec-openai"
    )
  end

  # --- 2. Helper Functions ---
  def upsert_object(class_name, properties)
    debug_label = properties[:name] || properties[:file_name] || class_name
    @logger.debug("Upserting #{class_name} #{debug_label}")

    # First, try to find existing object by name or unique identifier
    existing_object = find(class_name, properties)

    if existing_object
      @logger.debug("Found existing #{class_name} #{debug_label}, updating...")
      @logger.debug("Existing object: #{existing_object.inspect}")
      # Update existing object
      object_id = existing_object["_additional"]["id"]
      @logger.debug("Extracted object_id: #{object_id.inspect}")
      @client.objects.update(
        class_name: class_name,
        id: object_id,
        properties: properties
      )
      object_id
    else
      @logger.debug("Creating new #{class_name} #{debug_label}")
      # Create new object
      result = @client.objects.create(
        class_name: class_name,
        properties: properties
      )
      result["id"]
    end
  end

  def find(class_name, properties)
    unique_field = case class_name
                   when "Document" then "file_name"
                   when "Vehicle" then "vin"
                   else "name"
                   end

    unique_value = properties[unique_field.to_sym] || properties[unique_field]
    unless unique_value
      @logger.debug("No unique value found for #{class_name} with properties: #{properties.inspect}")
      return nil
    end

    begin
      escaped_value = unique_value.gsub('"', '\\"')
      query = <<~GRAPHQL
        {
          Get {
            #{class_name}(where: {path: ["#{unique_field}"], operator: Equal, valueString: "#{escaped_value}"}) {
              _additional { id }
              #{unique_field}
            }
          }
        }
      GRAPHQL

      @logger.debug("Executing GraphQL query: #{query}")
      result = @client.graphql.query(query)

      # Try multiple ways to access the response data
      objects = if result.respond_to?(:data) && result.data.respond_to?(:dig)
                  result.data.dig("Get", class_name)
                elsif result.respond_to?(:dig)
                  result.dig("data", "Get", class_name)
                else
                  result.instance_variable_get(:@original_hash).dig("data", "Get", class_name)
                end

      @logger.debug("GraphQL result for #{class_name} search: #{objects.inspect}")

      # Return first object if found, otherwise nil
      objects.is_a?(Array) ? objects.first : nil
    rescue StandardError => e
      @logger.error("Error finding #{class_name} with #{unique_field}='#{unique_value}': #{e.message}")
      @logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")
      nil
    end
  end

  def add_reference(from_class, from_id, prop, to_class, to_id, direct_reference = true)
    @logger.debug("Adding reference from #{from_class}(#{from_id}) #{prop} → #{to_class}(#{to_id})")

    # Check if reference already exists
    if reference_exists?(from_class, from_id, prop, to_id)
      @logger.debug("Reference already exists: #{from_class}/#{from_id} -> #{prop} -> #{to_class}/#{to_id}")
      return
    end

    # Use direct HTTP call since weaviate-ruby gem doesn't have reference.add method
    require "net/http"
    require "json"

    uri = URI("http://localhost:8080/v1/objects/#{from_class}/#{from_id}/references/#{prop}")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = {}.tap do |body|
      if direct_reference
        body[:uuid] = to_id
      else
        body[:beacon] = "weaviate://localhost/#{to_class}/#{to_id}"
      end
    end.to_json

    response = http.request(request)

    if response.code != "200"
      @logger.error("Failed to add reference: #{response.code} - #{response.body}")
      raise "Failed to add reference: #{response.message}"
    end

    @logger.debug("Successfully added reference: #{from_class}/#{from_id} -> #{prop} -> #{to_class}/#{to_id}")
  end

  def reference_exists?(from_class, from_id, prop, to_id)
    query = build_reference_existence_query(from_class, from_id, prop)

    # Skip if the query is empty (property doesn't exist in schema)
    if query.empty?
      @logger.debug("Skipping reference existence check for #{from_class}.#{prop} as it's not a valid reference property")
      return false
    end

    @logger.debug("Checking if reference exists with query: #{query}")

    begin
      result = @client.graphql.query(query)

      # Try multiple ways to access the response data
      from_objects = if result.respond_to?(:data) && result.data.respond_to?(:dig)
                       result.data.dig("Get", from_class)
                     elsif result.respond_to?(:dig)
                       result.dig("data", "Get", from_class)
                     else
                       result.instance_variable_get(:@original_hash).dig("data", "Get", from_class)
                     end

      @logger.debug("Reference check result for #{from_class}/#{from_id}.#{prop}: #{from_objects.inspect}")

      return false if from_objects.nil? || !from_objects.is_a?(Array) || from_objects.empty?

      refs = from_objects.first[prop]
      return false if refs.nil? || !refs.is_a?(Array)

      exists = refs.any? do |ref|
        ref && ref["_additional"] && ref["_additional"]["id"] == to_id
      end

      @logger.debug("Reference #{from_class}/#{from_id}.#{prop} -> #{to_id} exists: #{exists}")
      exists
    rescue StandardError => e
      @logger.error("Error checking reference existence: #{e.message}")
      @logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")
      @logger.error("Query: #{query}")
      @logger.error("Result: #{result.inspect}")
      false # If we can't check, assume it doesn't exist and try to add it
    end
  end

  def build_reference_existence_query(from_class, from_id, prop)
    # Define which types each reference property can point to (only for properties that exist)
    reference_types = {
      "children" => ["Person"], # For Person -> Person reference
      "created_by" => ["Person"], # For Document -> Person reference
      "home" => ["Place"], # For Person -> Place reference
      "members" => ["Person"], # For Project -> Person reference
      "owner" => ["Person"], # For Pet -> Person reference
      "parents" => ["Person"], # For Person -> Person reference
      "pets" => ["Pet"], # For Person -> Pet reference
      "projects" => ["Project"], # For Person -> Project reference
      "related_to" => ["Document", "Person", "Pet", "Place", "Project", "Vehicle"], # For Document -> * references
      "residents" => ["Person"], # For Place -> Person reference
      "spouse" => ["Person"], # For Person -> Person reference
      "vehicles" => ["Vehicle"] # For Person -> Vehicle reference
    }

    # Skip if this property isn't in our reference types
    unless reference_types.key?(prop)
      @logger.debug("Skipping reference check for non-existent property: #{prop} on #{from_class}")
      return ""
    end

    # Get the allowed types for this property
    allowed_types = reference_types[prop] || []

    # Build fragments only for allowed types - just need id for existence check
    fragments = allowed_types.map do |type|
      "... on #{type} { _additional { id } }"
    end.join("\n              ")

    <<~GRAPHQL
      {
        Get {
          #{from_class}(where: {path: ["_id"], operator: Equal, valueString: "#{from_id}"}) {
            #{prop} {
              #{fragments}
            }
          }
        }
      }
    GRAPHQL
  end

  # Add new properties to an existing class
  def update_class_properties(class_name, properties)
    @logger.debug("Updating properties for class #{class_name}")

    # Get existing class definition
    class_def = @client.schema.get(class_name: class_name)
    existing_props = class_def["properties"] || []

    # Add new properties that don't already exist
    new_properties = properties.reject do |new_prop|
      existing_props.any? { |existing| existing["name"] == new_prop[:name] }
    end

    return if new_properties.empty?

    # Convert symbols to strings for the API
    new_properties.each do |prop|
      @logger.debug("Adding property #{prop[:name]} to class #{class_name}")

      # Use direct HTTP call since weaviate-ruby gem doesn't have a direct method for this
      require "net/http"
      require "json"

      uri = URI("http://localhost:8080/v1/schema/#{class_name}/properties")
      http = Net::HTTP.new(uri.host, uri.port)

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"

      property_config = {
        dataType: prop[:dataType],
        name: prop[:name],
        moduleConfig: {
          "text2vec-openai" => {
            skip: false,
            vectorizePropertyName: false
          }
        }
      }

      # Add tokenization for text properties
      property_config[:tokenization] = "word" if prop[:dataType].include?("text")

      request.body = property_config.to_json

      response = http.request(request)

      unless response.code == "200"
        @logger.error("Failed to add property: #{response.code} - #{response.body}")
        raise "Failed to add property: #{response.message}"
      end

      @logger.debug("Successfully added property #{prop[:name]} to class #{class_name}")
    end
  end
end
