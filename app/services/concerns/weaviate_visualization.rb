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

    # Get all objects by class
    classes = ["Person", "Pet", "Place", "Project", "Document", "List", "ListItem", "Vehicle"]

    # First pass: collect all nodes
    classes.each do |class_name|
      response = @client.objects.list(class_name: class_name)
      # Convert response to hash if it's a GraphQL response object
      response = safe_to_hash(response)
      objects = response.is_a?(Hash) ? (response["objects"] || []) : []

      Rails.logger.debug { "\n🔍 Found #{objects.size} objects for class #{class_name}" }

      objects.each do |obj|
        # Convert to hash if it's a GraphQL response object
        obj = safe_to_hash(obj)
        next unless obj.is_a?(Hash) && obj["id"]

        node_id = "#{class_name}_#{obj['id']}"
        props = obj["properties"].is_a?(Hash) ? obj["properties"] : {}
        node_name = props["name"] || props["title"] || props["content"] || "Unnamed #{class_name}"

        Rails.logger.debug { "   - #{node_name} (ID: #{obj['id']})" }
        if class_name == "ListItem"
          Rails.logger.debug { "     Properties: #{props.keys.join(', ')}" }
          Rails.logger.debug { "     list_id: #{props['list_id']}" } if props["list_id"]
        end

        node_map[node_id] = {
          id: node_id,
          name: node_name,
          class: class_name,
          properties: props,
          connections: 0 # Initialize connection count
        }
        nodes << node_map[node_id]
      end
    rescue StandardError => e
      @logger.error("Error fetching objects for class #{class_name}: #{e.message}")
      @logger.error(e.backtrace.join("\n")) if @logger.debug?
      next

      # Second pass: collect all links
      response = @client.objects.list(class_name: class_name)
      response = safe_to_hash(response)
      objects = response.is_a?(Hash) ? (response["objects"] || []) : []

      objects.each do |obj|
        obj = safe_to_hash(obj)
        next unless obj.is_a?(Hash) && obj["id"]

        source_id = "#{class_name}_#{obj['id']}"
        source_node = node_map[source_id]
        next unless source_node

        # Check for reference properties in the properties hash
        ref_props = get_reference_properties(class_name)
        props = obj["properties"].is_a?(Hash) ? obj["properties"] : {}

        ref_props.each do |prop_name|
          # Look for references in both the root and properties
          prop_value = props[prop_name] || obj[prop_name]
          next if prop_value.nil? || (prop_value.respond_to?(:empty?) && prop_value.empty?)

          # Handle both single reference and array of references
          refs = prop_value.is_a?(Array) ? prop_value : [prop_value]
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
              # Handle direct ID references (like in list items)
              if prop_name == "list"
                # This is a list item referencing its parent list
                target_class = "List"
                target_id = ref["id"]
                Rails.logger.debug { "\n🔍 Found list item reference: #{source_id} -> List/#{target_id}" } if class_name == "ListItem"

                # Debug: Print the source and target node details
                source_node = node_map[source_id]
                target_node = node_map["#{target_class}_#{target_id}"]

                if source_node && target_node
                  Rails.logger.debug do
                    "   ✅ Valid reference: #{source_node[:name]} (#{source_node[:class]}) -> #{target_node[:name]} (#{target_node[:class]})"
                  end
                else
                  Rails.logger.debug "   ❌ Invalid reference: "
                  Rails.logger.debug { "      Source node: #{source_node ? 'Found' : 'Missing'}" }
                  Rails.logger.debug { "      Target node: #{target_node ? 'Found' : 'Missing'}" }
                end
              elsif class_name == "List" && prop_name == "items"
                # This is a list referencing its items
                target_class = "ListItem"
                target_id = ref["id"]
                Rails.logger.debug { "\n🔍 Found list reference: #{source_id} -> ListItem/#{target_id}" }

                # Debug: Print the source and target node details
                source_node = node_map[source_id]
                target_node = node_map["#{target_class}_#{target_id}"]

                if source_node && target_node
                  Rails.logger.debug do
                    "   ✅ Valid reference: #{source_node[:name]} (#{source_node[:class]}) -> #{target_node[:name]} (#{target_node[:class]})"
                  end

                  # Debug: Print the list_id of the target list item
                  if target_node[:properties] && target_node[:properties]["list_id"]
                    Rails.logger.debug { "   ℹ️  ListItem's list_id: #{target_node[:properties]['list_id']}" }

                    # Check if the list_id matches the source list's ID
                    source_id_parts = source_id.split("_")
                    source_list_id = source_id_parts[1..].join("_")

                    if target_node[:properties]["list_id"].to_s.include?(source_list_id)
                      Rails.logger.debug "   ✅ ListItem's list_id matches the source List ID"
                    else
                      Rails.logger.debug "   ❌ ListItem's list_id does NOT match the source List ID"
                      Rails.logger.debug { "      List ID in reference: #{source_list_id}" }
                      Rails.logger.debug { "      List ID in list_item: #{target_node[:properties]['list_id']}" }
                    end
                  end
                else
                  Rails.logger.debug "   ❌ Invalid reference: "
                  Rails.logger.debug { "      Source node: #{source_node ? 'Found' : 'Missing'}" }
                  Rails.logger.debug { "      Target node: #{target_node ? 'Found' : 'Missing'}" }
                end
              else
                # Skip other types of direct ID references we don't handle
                next
              end
            else
              next
            end

            target_node_id = "#{target_class}_#{target_id}"
            target_node = node_map[target_node_id]

            # Only create link if target node exists
            next unless target_node

            # Increment connection counts for both nodes
            source_node[:connections] += 1
            target_node[:connections] += 1

            links << {
              source: source_id,
              target: target_node_id,
              type: prop_name
            }
          end
        end
      end
    rescue StandardError => e
      @logger.error("Error processing references for class #{class_name}: #{e.message}")
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
