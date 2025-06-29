#!/usr/bin/env ruby
# Debug script to analyze content and catch errors with detailed logging

begin
  # Find the content
  content = Content.find(9)
  puts "Found content: #{content.id}"

  # Create the service
  service = ContentAnalysisService.new

  # Prepare files for analysis
  files = []
  content.files.attachments.each do |attachment|
    data = attachment.download
    files << { filename: attachment.filename.to_s, data: data }
    puts "Prepared file #{attachment.filename} (#{data.size} bytes) for analysis"
  rescue StandardError => e
    puts "Error downloading attachment: #{e.message}"
  end

  # Get the notes
  notes = [content.note]
  puts "Content note: #{content.note.inspect}"

  # Enable debug logging
  ENV["DEBUG"] = "true"

  # Run the analysis
  puts "Starting analysis..."
  results = service.analyze(notes: notes, files: files)
  puts "Analysis completed successfully with #{results.size} results"

  # Debug the results structure
  puts "\nDEBUG: Results structure:"
  results.each_with_index do |result, index|
    puts "Result ##{index + 1}:"
    puts "  File: #{result[:file] || 'No file (note only)'}"
    puts "  Skipped: #{result[:skipped] || false}"

    if result[:result].present?
      puts "  Result type: #{result[:result].class.name}"

      if result[:result].is_a?(Hash)
        puts "  Result keys: #{result[:result].keys.inspect}"

        # Check for arrays in the result
        result[:result].each do |key, value|
          next unless value.is_a?(Array)

          puts "  Found array key: #{key}"
          puts "  Array type: #{value.class.name}"
          puts "  Array size: #{value.size}"
          puts "  Array sample: #{value[0..2].inspect}"
        end
      end
    else
      puts "  No result data"
    end
  end

  # Try to save the last result directly to debug the issue
  if results.any? && results.last[:result].present?
    puts "\nDEBUG: Attempting to save the last result directly"
    begin
      # Try to save the raw result first
      puts "Attempting to save raw result..."

      # Clone the content to avoid modifying the original
      cloned_content = Content.find(content.id)
      cloned_content.openai_response = results.last[:result]

      if cloned_content.save
        puts "Successfully saved raw result!"
        puts "Saved response class: #{cloned_content.openai_response.class.name}"
        puts "Saved response keys: #{cloned_content.openai_response.keys.inspect}"
      else
        puts "Failed to save raw result: #{cloned_content.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      puts "Error saving raw result: #{e.class.name}: #{e.message}"
      puts "#{e.backtrace.join("\n")[0..500]}..." # Show first part of backtrace
    end
  end

  # Process results and extract entities using the service
  puts "\nDEBUG: Now trying the service's process_analysis_result method"
  puts "Creating a fresh content instance to avoid any state issues"
  fresh_content = Content.find(content.id)

  # Monkey patch the process_analysis_result method to add more debugging
  original_method = ContentAnalysisService.instance_method(:process_analysis_result)

  ContentAnalysisService.define_method(:process_analysis_result) do |content, result|
    puts "\nINTERCEPTED: Inside process_analysis_result"

    if result.any? && result[:result].present?
      puts "Result type: #{result[:result].class.name}"
      puts "Result object_id: #{result[:result].object_id}"

      # Check for arrays in the result
      result[:result].each do |key, value|
        if value.is_a?(Array)
          puts "Found array key in service method: #{key}"
          puts "Array size: #{value.size}"
        end
      end

      # Try to save directly from inside the intercepted method
      begin
        puts "\nTrying direct save from inside intercepted method:"
        content.openai_response = results.last[:result]
        if content.save
          puts "SUCCESS: Direct save from intercepted method worked!"
        else
          puts "FAILED: Direct save from intercepted method failed: #{content.errors.full_messages.join(', ')}"
        end
      rescue StandardError => e
        puts "ERROR in intercepted direct save: #{e.class.name}: #{e.message}"
      end
    end

    # Call the original method
    original_method.bind_call(self, content, results)
  end

  # Now call the process_analysis_result method
  puts "\nProcessing analysis results..."
  processing_result = service.process_analysis_result(fresh_content, results)
  puts "Processing completed with status: #{processing_result[:success]}"

  if processing_result[:success]
    puts "Entity count: #{processing_result[:entity_count]}"
    puts "Created entities: #{processing_result[:created_entities].size}"
    puts "Skipped files: #{processing_result[:skipped_files].inspect}"
  else
    puts "Processing failed: #{processing_result[:message]}"
  end

  # Restore the original method
  ContentAnalysisService.define_method(:process_analysis_result, original_method)
rescue StandardError => e
  puts "ERROR: #{e.class.name}: #{e.message}"
  puts "#{e.backtrace.join("\n")[0..500]}..." # Show first part of backtrace
end
