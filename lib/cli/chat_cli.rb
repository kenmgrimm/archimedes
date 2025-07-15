require "thor"
require "tty-prompt"
require "tty-markdown"
require "tty-box"

module CLI
  class Chat < Thor
    desc "start", "Start an interactive chat session with Neo4j knowledge graph"
    def start
      prompt = TTY::Prompt.new
      Rails.logger.debug TTY::Box.frame("Neo4j Knowledge Graph Chat", padding: 1)

      loop do
        query = prompt.ask("Ask me anything (or type 'exit' to quit):") do |q|
          q.modify :strip
        end

        break if query&.downcase == "exit"

        begin
          response = Neo4j::ChatService.new(query).execute
          Rails.logger.debug TTY::Markdown.parse(response)
        rescue StandardError => e
          Rails.logger.debug TTY::Box.error("Error: #{e.message}")
        end
      end
    end
  end
end
