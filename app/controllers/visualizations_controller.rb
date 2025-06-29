class VisualizationsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def knowledge_graph
    weaviate_service = WeaviateService.new

    respond_to do |format|
      format.html # Renders knowledge_graph.html.erb
      format.json do
        # Get the graph data directly without writing to a file
        graph_data = weaviate_service.send(:build_knowledge_graph_data)

        # Initialize data structures
        nodes = []
        node_id_map = {}  # Maps original ID to array index
        id_to_index = {}  # Maps original ID to node index

        # First pass: process all nodes and build the mapping
        graph_data[:nodes].each_with_index do |node, index|
          # Ensure ID is a string and not empty
          node_id = node[:id].to_s.presence || "node_#{index}"

          # Create a unique ID for this node
          unique_id = "node_#{index}"

          # Store the mapping from original ID to index
          node_id_map[node_id] = index
          id_to_index[node_id] = index

          # Add the node to our collection
          nodes << {
            id: unique_id,
            original_id: node_id,
            name: node[:name] || "Unnamed Node",
            class: node[:class] || "unknown",
            group: node[:group] || 1,
            connections: node[:connections] || 0,
            properties: node.except(:id, :name, :class, :group, :connections)
          }
        end

        # Second pass: process links with proper node references
        links = []
        graph_data[:links].each do |link|
          source_id = link[:source].to_s
          target_id = link[:target].to_s

          # Only include links where both source and target exist in our nodes
          next unless node_id_map.key?(source_id) && node_id_map.key?(target_id)

          source_index = node_id_map[source_id]
          target_index = node_id_map[target_id]

          # Create the link with array indices for D3
          links << {
            source: source_index,
            target: target_index,
            type: link[:type] || "related_to",
            value: link[:value] || 1
          }

          # Increment connection counts for both nodes
          nodes[source_index][:connections] += 1
          nodes[target_index][:connections] += 1
        end

        Rails.logger.info "\n📊 Generated graph with #{nodes.size} nodes and #{links.size} links"

        render json: {
          nodes: nodes,
          links: links,
          metadata: {
            node_count: nodes.size,
            link_count: links.size,
            generated_at: Time.current.iso8601
          }
        }
      rescue StandardError => e
        Rails.logger.error "Error generating knowledge graph data: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: {
          error: "Failed to generate knowledge graph: #{e.message}",
          backtrace: Rails.env.development? ? e.backtrace : nil
        }, status: :internal_server_error
      end
    end
  end

  def connection_stats
    weaviate_service = WeaviateService.new

    respond_to do |format|
      format.json do
        # Get the graph data
        graph_data = weaviate_service.build_knowledge_graph_data

        # Initialize data structures
        connection_counts = Hash.new { |h, k| h[k] = Hash.new(0) }
        node_names = {}

        # First pass: collect node names
        graph_data[:nodes].each do |node|
          node_id = node[:id].to_s
          node_names[node_id] = node[:name] || "Unnamed #{node[:class] || 'Node'}"
        end

        # Second pass: count connections
        graph_data[:links].each do |link|
          source_id = link[:source].to_s
          target_id = link[:target].to_s

          next unless node_names.key?(source_id) && node_names.key?(target_id)

          source_name = node_names[source_id]
          target_name = node_names[target_id]

          # Count the connection in both directions
          connection_counts[source_name][target_name] += 1
          # Only count the reverse if it's a different pair
          connection_counts[target_name][source_name] += 1 unless source_name == target_name
        end

        # Convert to a sorted array of results
        results = connection_counts.map do |source, targets|
          total_connections = targets.values.sum
          {
            entity: source,
            total_connections: total_connections,
            connections: targets.sort_by { |_, count| -count }.map do |target, count|
              { connected_to: target, count: count }
            end
          }
        end.sort_by { |r| -r[:total_connections] }

        render json: { connection_stats: results }
      rescue StandardError => e
        Rails.logger.error "Error generating connection stats: #{e.message}"
        render json: { error: "Failed to generate connection stats: #{e.message}" }, status: :internal_server_error
      end
    end
  end
end
