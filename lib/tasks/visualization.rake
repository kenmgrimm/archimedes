namespace :weaviate do
  desc "Generate and display the knowledge graph visualization"
  task visualize: :environment do
    require_relative "../../app/services/weaviate_service"

    puts "🚀 Initializing Weaviate service..."
    weaviate = WeaviateService.new

    puts "🔄 Generating knowledge graph visualization..."
    weaviate.display_knowledge_graph

    puts "✅ Done! The visualization has been saved as 'kaiser_soze_knowledge_graph.html' in your project root."
    puts "   Open it in your browser to view the interactive graph!"
  rescue StandardError => e
    puts "❌ Error generating visualization: #{e.message}"
    puts e.backtrace.join("\n") if ENV["DEBUG"]
    exit 1
  end
end
