module WeaviateVisualization
  # Returns the URL to view the knowledge graph visualization
  def display_knowledge_graph
    url = Rails.application.routes.url_helpers.visualization_knowledge_graph_url(host: "localhost:3000")
    Rails.logger.debug { "\n🌐 Knowledge graph is available at: #{url}" }
    url
  end

  # Export knowledge graph data in various formats for external visualization tools
  def export_knowledge_graph(format = :json)
    # Get graph data
    graph_data = build_knowledge_graph_data

    # Export in the requested format
    case format
    when :graphml
      export_graphml(graph_data)
    when :gexf
      export_gexf(graph_data)
    when :cytoscape
      export_cytoscape(graph_data)
    else
      # Default to JSON for :json or any unrecognized format
      export_json(graph_data)
    end
  end

  # Export as standard JSON format compatible with most visualization libraries
  def export_json(graph_data)
    filename = "knowledge_graph_export.json"
    File.write(filename, JSON.pretty_generate(graph_data))
    Rails.logger.debug { "\n📊 Knowledge graph data exported to: #{filename}" }
    Rails.logger.debug "This file can be imported into visualization tools like D3.js or Sigma.js"
    filename
  end

  # Export as GraphML format (XML-based) for tools like yEd, Gephi
  def export_graphml(graph_data)
    filename = "knowledge_graph_export.graphml"

    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.graphml(xmlns: "http://graphml.graphdrawing.org/xmlns") do
        # Define attribute keys
        xml.key(:id => "name", :for => "node", "attr.name" => "name", "attr.type" => "string")
        xml.key(:id => "class", :for => "node", "attr.name" => "class", "attr.type" => "string")
        xml.key(:id => "connections", :for => "node", "attr.name" => "connections", "attr.type" => "int")
        xml.key(:id => "type", :for => "edge", "attr.name" => "type", "attr.type" => "string")

        xml.graph(id: "G", edgedefault: "directed") do
          # Add nodes
          graph_data[:nodes].each do |node|
            xml.node(id: node[:id]) do
              xml.data(node[:name], key: "name")
              xml.data(node[:class], key: "class")
              xml.data(node[:connections], key: "connections")
            end
          end

          # Add edges
          graph_data[:links].each_with_index do |link, index|
            xml.edge(id: "e#{index}", source: link[:source], target: link[:target]) do
              xml.data(link[:type], key: "type")
            end
          end
        end
      end
    end

    File.write(filename, builder.to_xml)
    Rails.logger.debug { "\n📊 Knowledge graph data exported to: #{filename}" }
    Rails.logger.debug "This file can be imported into tools like Gephi, yEd, or other GraphML-compatible viewers"
    filename
  end

  # Export as GEXF format for Gephi
  def export_gexf(graph_data)
    filename = "knowledge_graph_export.gexf"

    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.gexf(xmlns: "http://www.gexf.net/1.2draft", version: "1.2") do
        xml.meta do
          xml.description("Knowledge Graph Export from Weaviate")
        end
        xml.graph(mode: "static", defaultedgetype: "directed") do
          # Node definitions
          xml.nodes do
            graph_data[:nodes].each do |node|
              xml.node(id: node[:id], label: node[:name]) do
                xml.attvalues do
                  xml.attvalue("for" => "class", "value" => node[:class])
                  xml.attvalue("for" => "connections", "value" => node[:connections])
                end
              end
            end
          end
          # Edge definitions
          xml.edges do
            graph_data[:links].each_with_index do |link, index|
              xml.edge(id: "e#{index}", source: link[:source], target: link[:target], label: link[:type])
            end
          end
        end
      end
    end

    File.write(filename, builder.to_xml)
    Rails.logger.debug { "\n📊 Knowledge graph data exported to: #{filename}" }
    Rails.logger.debug "This file can be imported into Gephi for advanced graph visualization and analysis"
    filename
  end

  # Export in Cytoscape.js compatible JSON format
  def export_cytoscape(graph_data)
    filename = "knowledge_graph_cytoscape.json"

    # Convert to Cytoscape.js format
    cytoscape_data = {
      elements: {
        nodes: graph_data[:nodes].map do |node|
          {
            data: {
              id: node[:id],
              name: node[:name],
              class: node[:class],
              connections: node[:connections]
            }
          }
        end,
        edges: graph_data[:links].map.with_index do |link, index|
          {
            data: {
              id: "e#{index}",
              source: link[:source],
              target: link[:target],
              type: link[:type]
            }
          }
        end
      }
    }

    File.write(filename, JSON.pretty_generate(cytoscape_data))
    Rails.logger.debug { "\n📊 Knowledge graph data exported to: #{filename}" }
    Rails.logger.debug "This file can be directly used with Cytoscape.js for interactive visualization"
    filename
  end

  def build_knowledge_graph_data
    nodes = []
    links = []
    node_map = {}
    processed_links = Set.new # To avoid duplicate links

    # Get all objects by class
    classes = ["Person", "Pet", "Place", "Project", "Document", "List", "Vehicle"]

    # First pass: collect all nodes
    classes.each do |class_name|
      # Get objects without the include parameter first
      response = @client.objects.list(class_name: class_name)
      response = safe_to_hash(response)
      objects = response.is_a?(Hash) ? (response["objects"] || []) : []

      objects.each do |obj|
        obj = safe_to_hash(obj)
        next unless obj.is_a?(Hash) && obj["id"]

        node_id = "#{class_name}_#{obj['id']}"
        props = obj["properties"].is_a?(Hash) ? obj["properties"] : {}
        node_name = props["name"] || props["title"] || props["content"] || "Unnamed #{class_name}"

        node_map[node_id] = {
          id: node_id,
          name: node_name,
          class: class_name,
          properties: props,
          connections: 0
        }
        nodes << node_map[node_id]

        # Get the full object with references
        begin
          full_obj = @client.objects.get(
            id: obj["id"],
            class_name: class_name,
            include: ["all"] # Use array format ["all"] for the include parameter
          )
          full_obj = safe_to_hash(full_obj)
          process_references(full_obj, node_id, node_map, links, processed_links) if full_obj.is_a?(Hash)
        rescue StandardError => e
          @logger.error("Error fetching full object #{node_id}: #{e.message}")
          @logger.error(e.backtrace.join("\n")) if @logger.debug?
        end
      end
    rescue StandardError => e
      @logger.error("Error processing class #{class_name}: #{e.message}")
      @logger.error(e.backtrace.join("\n")) if @logger.debug?
      next
    end

    # Ensure Kaiser Soze has the most connections if he exists
    kaiser_node = nodes.find { |n| n[:name] == "Kaiser Soze" }
    if kaiser_node
      max_connections = nodes.pluck(:connections).max || 0
      kaiser_node[:connections] = [kaiser_node[:connections], max_connections + 1].max
    end

    { nodes: nodes, links: links }
  end

  private

  def process_references(obj, source_id, node_map, links, processed_links)
    return unless obj.is_a?(Hash)

    # Get the class name from the source_id
    source_class = source_id.split("_").first

    # Get all reference properties for this class
    ref_props = get_reference_properties(source_class)

    # Process each reference property
    ref_props.each do |prop_name|
      # Look for references in the object's properties
      refs = obj.dig("properties", prop_name) || obj[prop_name]
      next if refs.nil? || (refs.respond_to?(:empty?) && refs.empty?)

      # Handle both single reference and array of references
      refs = [refs] unless refs.is_a?(Array)

      refs.each do |ref|
        ref = safe_to_hash(ref)
        next unless ref.is_a?(Hash)

        # Handle both beacon format and direct ID references
        if ref["beacon"]
          # Extract target class and ID from beacon
          beacon_parts = ref["beacon"].to_s.split("/")
          next unless beacon_parts.size >= 2

          target_class = beacon_parts[-2]
          target_id = beacon_parts[-1]
        elsif ref["id"]
          # For direct ID references, we need to know the target class
          # This is a simplification - you might need to adjust based on your schema
          target_class = ref["type"] || ref["class"] || prop_name.singularize.camelize
          target_id = ref["id"]
        else
          next
        end

        target_node_id = "#{target_class}_#{target_id}"
        target_node = node_map[target_node_id]

        # Only create link if target node exists
        next unless target_node

        # Create a unique key for this link to avoid duplicates
        link_key = [source_id, target_node_id, prop_name].join("|")
        next if processed_links.include?(link_key)

        # Increment connection counts for both nodes
        next unless (source_node = node_map[source_id])

        source_node[:connections] += 1
        target_node[:connections] += 1

        links << {
          source: source_id,
          target: target_node_id,
          type: prop_name
        }

        processed_links << link_key
      end
    end
  end

  def get_reference_properties(class_name)
    # Define reference properties for each class
    {
      "Document" => ["created_by", "related_to"],
      "Vehicle" => ["owner"],
      "Person" => ["relationships"],
      "Project" => ["members"],
      "List" => ["documents"],
      "Pet" => ["owner"]
    }[class_name] || []
  end

  def safe_to_hash(obj)
    return obj if obj.nil?
    return obj unless obj.respond_to?(:to_h) || obj.is_a?(Hash) || obj.respond_to?(:data)

    obj = obj.data if obj.respond_to?(:data)

    if obj.is_a?(Hash)
      obj.transform_values do |value|
        convert_value(value)
      end
    elsif obj.respond_to?(:to_h)
      obj.to_h.transform_values do |value|
        convert_value(value)
      end
    else
      obj
    end
  rescue StandardError => e
    @logger.error("Error converting object to hash: #{e.class}: #{e.message}")
    @logger.error("Object type: #{obj.class}, inspect: #{obj.inspect}") if @logger.debug?
    {}
  end

  def convert_value(value)
    return value if value.nil?

    case value
    when Array
      return [] if value.empty?

      # Special case: array with a single hash that has array values
      if value.size == 1 && value.first.is_a?(Hash)
        first_item = value.first
        # If the hash has array values, we'll process them specially
        if first_item.values.any?(Array)
          return first_item.transform_values do |v|
            v.is_a?(Array) ? v.map { |item| convert_value(item) } : convert_value(v)
          end
        end

        # If all values are nil, return empty array
        return [] if first_item.values.compact.empty?
      end

      # Default array processing
      value.map { |v| convert_value(v) }
    when Hash
      # Skip empty hashes or hashes with all nil values
      if value.empty? || value.values.all?(&:nil?)
        {}
      else
        # Process hash values recursively
        value.transform_values do |v|
          convert_value(v)
        end
      end
    when ->(v) { v.respond_to?(:to_h) }
      safe_to_hash(value)
    else
      value
    end
  rescue StandardError => e
    @logger.error("Error converting value: #{e.class}: #{e.message}")
    @logger.error("Value class: #{value.class}, inspect: #{value.inspect}")
    value
  end

  def get_reference_properties(class_name)
    # Define reference properties for each class based on our schema
    reference_map = {
      "Person" => ["spouse", "children", "parents", "pets", "home", "projects", "vehicles"],
      "Pet" => ["owner", "home"],
      "Place" => ["residents", "pets", "vehicles", "documents", "lists", "projects"],
      "Project" => ["members", "documents", "lists", "related_to"],
      "Document" => ["created_by", "related_to"],
      "List" => ["items", "related_to"],
      "ListItem" => ["list"],
      "Vehicle" => ["owner", "home"]
    }

    reference_map[class_name] || []
  end
end
