require "httparty"

module WeaviateCleanup
  def delete_all_objects
    classes = fetch_schema_classes
    return if classes.nil?  # Error already logged in fetch_schema_classes

    if classes.empty?
      @logger.info "ℹ️  No classes found in the schema. Nothing to delete."
      return
    end

    @logger.info "🧹 Starting cleanup: deleting all objects from #{classes.size} classes..."

    classes.each do |class_name|
      @logger.info "Deleting all #{class_name} objects..."

      # Get all objects of this class
      response = @client.objects.list(class_name: class_name)
      objects = response.is_a?(Array) ? response : (response["objects"] || [])

      if objects.empty?
        @logger.info "  No #{class_name} objects found to delete."
        next
      end

      # Delete each object individually
      deleted_count = 0
      objects.each do |obj|
        obj_id = obj.is_a?(String) ? obj : (obj["id"] || obj[:id])
        next unless obj_id

        @client.objects.delete(class_name: class_name, id: obj_id)
        @logger.debug "  ✓ Deleted #{class_name} #{obj_id.to_s[0..7]}..."
        deleted_count += 1
      rescue StandardError => e
        @logger.error "  ✗ Failed to delete #{obj_id}: #{e.message}"
      end

      @logger.info "  Finished cleaning #{class_name} (#{deleted_count}/#{objects.length} objects deleted)"
    rescue StandardError => e
      @logger.error "  ✗ Error processing #{class_name}: #{e.message}"
    end

    @logger.info "✅ Cleanup complete. Schema structure preserved."
  end

  def delete_schema_classes
    base_url = @client.url.to_s
    @logger.info "💥 Starting nuclear cleanup: deleting all schema classes..."

    classes = fetch_schema_classes
    return if classes.nil?  # Error already logged in fetch_schema_classes

    if classes.empty?
      @logger.info "ℹ️  No classes found in the schema. Nothing to delete."
      return
    end

    begin
      # Get current schema directly from the API
      response = HTTParty.get("#{base_url}/v1/schema")

      raise "Failed to get schema: #{response.code} - #{response.body}" unless response.success?

      # Parse the response to get existing classes
      schema_data = response.parsed_response

      existing_classes =
        if schema_data.is_a?(Array)
          schema_data.map { |c| c.is_a?(Hash) ? c["class"] : c.class_name }.compact
        elsif schema_data.is_a?(Hash) && schema_data["classes"]
          schema_data["classes"].map { |c| c.is_a?(Hash) ? c["class"] : c.class_name }.compact
        else
          []
        end

      @logger.debug "Found existing classes: #{existing_classes.inspect}"

      # Determine which classes actually need to be deleted
      classes_to_delete = classes & existing_classes

      if classes_to_delete.empty?
        @logger.info "No schema classes to delete."
        return
      end

      # Delete each class using direct HTTP requests
      classes_to_delete.each do |class_name|
        @logger.info "Deleting schema class: #{class_name}"

        # Use direct HTTP request to delete the class
        delete_response = HTTParty.delete("#{base_url}/v1/schema/#{class_name}")

        if delete_response.success?
          @logger.info "  ✓ Deleted #{class_name} schema"
        else
          raise "API returned #{delete_response.code}: #{delete_response.body}" unless delete_response.code == 404

          @logger.warn "  Class #{class_name} not found (may have been already deleted)"

        end
      rescue StandardError => e
        @logger.error "  ✗ Failed to delete #{class_name} schema: #{e.message}"
      end

      # Verify all classes were deleted
      begin
        verify_response = HTTParty.get("#{base_url}/v1/schema")

        if verify_response.success?
          remaining_schema = verify_response.parsed_response
          remaining_classes =
            if remaining_schema.is_a?(Array)
              remaining_schema.map { |c| c.is_a?(Hash) ? c["class"] : c.class_name }.compact
            elsif remaining_schema.is_a?(Hash) && remaining_schema["classes"]
              remaining_schema["classes"].map { |c| c.is_a?(Hash) ? c["class"] : c.class_name }.compact
            else
              []
            end

          remaining_count = (remaining_classes & classes_to_delete).count

          if remaining_count == 0
            @logger.info "✅ All requested schema classes were deleted."
          else
            @logger.warn "⚠️  Some schema classes remain: #{(remaining_classes & classes_to_delete).join(', ')}"
          end
        else
          @logger.error "❌ Failed to verify schema deletion: #{verify_response.code} - #{verify_response.body}"
        end
      rescue StandardError => e
        @logger.error "❌ Error verifying schema deletion: #{e.message}"
      end
    rescue StandardError => e
      @logger.error "❌ Error during schema cleanup: #{e.message}"
      @logger.error e.backtrace.join("\n") if @logger.debug?
      raise
    end
  end

  def cleanup_interactive
    # Interactive cleanup method that prompts user for choice
    puts "\n🧹 Weaviate Database Cleanup"
    puts "Choose cleanup method:"
    puts "1. Delete all objects (keeps schema structure)"
    puts "2. Delete entire schema classes (nuclear option)"
    print "Enter choice (1 or 2): "

    choice = gets.chomp

    case choice
    when "1"
      delete_all_objects
    when "2"
      delete_schema_classes
    else
      @logger.error "Invalid choice: #{choice}. Exiting."
      return false
    end

    puts "\n🎉 Weaviate cleanup complete!"
    true
  end

  private

  def fetch_schema_classes
    response = HTTParty.get("#{@client.url}/v1/schema")
    unless response.success?
      @logger.error "❌ Failed to fetch schema: #{response.code} - #{response.body}"
      return nil
    end
    
    schema_data = response.parsed_response
    if schema_data.is_a?(Array)
      schema_data.map { |c| c.is_a?(Hash) ? c['class'] : c.class_name }.compact
    elsif schema_data.is_a?(Hash) && schema_data['classes']
      schema_data['classes'].map { |c| c.is_a?(Hash) ? c['class'] : c.class_name }.compact
    else
      []
    end
  end
end
