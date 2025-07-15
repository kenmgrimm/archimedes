module Neo4j
  module Chat
    module Utils
      def self.clean_embeddings(str)
        str.gsub(/embedding: \[[^\]]*\]/, "embedding: <REMOVED>")
      end
    end
  end
end
