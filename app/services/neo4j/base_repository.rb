# frozen_string_literal: true

module Neo4j
  class BaseRepository
    class << self
      def query(cypher, parameters = {})
        Neo4j::DriverWrapper.query(cypher, parameters)
      end

      def read_transaction(&)
        Neo4j::DriverWrapper.read_transaction(&)
      end

      def write_transaction(&)
        Neo4j::DriverWrapper.write_transaction(&)
      end

      def execute_write(cypher, parameters = {})
        write_transaction do |tx|
          tx.run(cypher, parameters)
        end
      end

      def execute_read(cypher, parameters = {})
        read_transaction do |tx|
          tx.run(cypher, parameters)
        end
      end

      def find_nodes(label, properties = {})
        where_clause = properties.map { |k, _v| "n.#{k} = $#{k}" }.join(" AND ")
        cypher = "MATCH (n:#{label})"
        cypher += " WHERE #{where_clause}" unless properties.empty?
        cypher += " RETURN n"

        execute_read(cypher, properties).map(&:first)
      end

      def create_node(label, properties = {})
        cypher = "CREATE (n:#{label} $props) RETURN n"
        execute_write(cypher, props: properties).first&.first
      end

      def update_node(label, id_properties, update_properties)
        set_clause = update_properties.keys.map { |k| "n.#{k} = $props.#{k}" }.join(", ")
        where_clause = id_properties.map { |k, _v| "n.#{k} = $id.#{k}" }.join(" AND ")

        cypher = "MATCH (n:#{label}) WHERE #{where_clause} SET #{set_clause} RETURN n"

        execute_write(cypher, { id: id_properties, props: update_properties }).first&.first
      end

      def delete_node(label, properties)
        where_clause = properties.map { |k, _| "n.#{k} = $#{k}" }.join(" AND ")
        cypher = "MATCH (n:#{label}) WHERE #{where_clause} DETACH DELETE n"

        execute_write(cypher, properties)
      end
    end
  end
end
