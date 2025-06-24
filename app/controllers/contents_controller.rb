class ContentsController < ApplicationController
  before_action :set_content, only: [:show, :edit, :update, :destroy, :analyze]

  # GET /contents
  def index
    @contents = Content.order(created_at: :desc)
    Rails.logger.debug { "[ContentsController] Listing all contents. Count: #{@contents.size}" }
  end

  # GET /contents/1
  def show
    Rails.logger.debug { "[ContentsController] Showing content ##{@content.id}" }

    # Load entities for display
    return unless @content.entities.any?

    Rails.logger.debug { "[ContentsController] Content has #{@content.entities.count} entities" }

    # If there are entities but no analysis results loaded, create a simple result structure
    # This allows the analysis results section to display on the show page without requiring
    # the user to click the Analyze button first
    @analysis_results = []

    # Group entities by type for display
    entity_groups = @content.entities.group_by(&:entity_type)

    # Create a simulated analysis result with the entities
    return unless entity_groups.any?

    # Create an annotated description from the entities
    annotated_description = "This content contains: "
    entity_groups.each do |type, entities|
      entities.each do |entity|
        annotated_description += "[#{type}: #{entity.value}] "
      end
    end

    # Create a simple result hash that matches the format expected by the view
    @analysis_results << {
      file: nil,
      result: {
        "description" => "Content with #{@content.entities.count} extracted entities.",
        "annotated_description" => annotated_description,
        "rating" => 1.0
      }
    }

    Rails.logger.debug { "[ContentsController] Created analysis results from #{@content.entities.count} existing entities" }
  end

  # GET /contents/new
  def new
    @content = Content.new
    Rails.logger.debug("[ContentsController] Rendering new content form.")
  end

  # GET /contents/1/edit
  def edit
    Rails.logger.debug { "[ContentsController] Editing content ##{@content.id}" }
  end

  # POST /contents
  def create
    @content = Content.new(content_params)
    if @content.save
      Rails.logger.debug { "[ContentsController] Created content ##{@content.id} with params: #{content_params.inspect}" }
      redirect_to @content, notice: "Content was successfully created."
    else
      Rails.logger.debug { "[ContentsController] Failed to create content. Errors: #{@content.errors.full_messages.join(', ')}" }
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /contents/1
  def update
    if @content.update(content_params)
      Rails.logger.debug { "[ContentsController] Updated content ##{@content.id} with params: #{content_params.inspect}" }
      redirect_to @content, notice: "Content was successfully updated."
    else
      Rails.logger.debug do
        "[ContentsController] Failed to update content ##{@content.id}. Errors: #{@content.errors.full_messages.join(', ')}"
      end
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /contents/1
  def destroy
    @content.destroy
    Rails.logger.debug { "[ContentsController] Destroyed content ##{@content.id}" }
    redirect_to contents_url, notice: "Content was successfully destroyed."
  end

  # POST /contents/1/analyze
  def analyze
    Rails.logger.debug { "[ContentsController] Analyzing content ##{@content.id}" }

    begin
      service = ContentAnalysisService.new
      notes = [@content.note].compact
      files = []

      # Prepare files for analysis
      @content.files.attachments.each do |attachment|
        data = attachment.download
        files << { filename: attachment.filename.to_s, data: data }
        Rails.logger.debug { "[ContentsController] Prepared file #{attachment.filename} (#{data.size} bytes) for analysis" }
      rescue StandardError => e
        Rails.logger.error { "[ContentsController] Error downloading attachment: #{e.message}" }
      end

      # Perform analysis
      results = service.analyze(notes: notes, files: files)

      # Detailed debug logging of raw results
      results.each_with_index do |result, index|
        Rails.logger.debug { "[ContentsController] Analysis result ##{index + 1}:" }
        Rails.logger.debug { "  - File: #{result[:file] || 'No file (note only)'}" }

        if result[:result].present? && result[:result].is_a?(Hash)
          Rails.logger.debug { "  - Description: #{result[:result]['description']}" }
          Rails.logger.debug { "  - Annotated Description: #{result[:result]['annotated_description']}" }
          Rails.logger.debug { "  - Confidence Rating: #{result[:result]['rating']}" }

          # Extract and log entities from annotated_description
          entities = result[:result]["annotated_description"].to_s.scan(/\[([^\]:]+):\s*([^\]]+)\]/).map do |type, value|
            { "entity_type" => type.strip, "value" => value.strip }
          end

          Rails.logger.debug { "  - Extracted #{entities.size} entities from annotated_description:" }
          entities.each do |entity|
            Rails.logger.debug { "    * #{entity['entity_type']}: #{entity['value']}" }
          end
        else
          Rails.logger.debug { "  - No valid result data" }
        end
      end

      # Process results and extract entities
      results.each do |result|
        # Extract entities from the OpenAI result and associate with content
        next unless result[:result].present? && result[:result].is_a?(Hash)

        created_entities = service.extract_and_create_entities(@content, result[:result])
        Rails.logger.debug { "[ContentsController] Processed and created #{created_entities.size} entities for content ##{@content.id}" }

        # Log each created entity
        created_entities.each do |entity|
          Rails.logger.debug { "[ContentsController] Created entity: #{entity.entity_type} - #{entity.value}" }
        end
      end

      # Store results for rendering
      @analysis_results = results

      # Save the OpenAI response to the database if we have valid results
      if results.any? && results.last[:result].present?
        @last_openai_response = results.last[:result]

        # Save the OpenAI response to the content record
        Rails.logger.debug { "[ContentsController] Saving OpenAI response to content ##{@content.id}" }
        @content.update(openai_response: @last_openai_response)
      end

      # Add detailed flash messages for the successful analysis
      entity_count = @content.entities.reload.count

      # Check if any files were skipped
      skipped_files = results.select { |r| r[:skipped] }.pluck(:file)

      flash.now[:warning] = "Some files were skipped during analysis: #{skipped_files.join(', ')}" if skipped_files.any?

      if entity_count.positive?
        flash.now[:notice] = "Content was successfully analyzed. Found #{entity_count} entities."
      else
        flash.now[:info] = "Analysis completed, but no entities were found."
      end

      # Add debug logging
      Rails.logger.debug { "[ContentsController] Analysis completed with #{entity_count} entities extracted" }

      respond_to do |format|
        format.html { render :show }
        format.json { render json: { content: @content, analysis: @analysis_results } }
        format.turbo_stream do
          # Add detailed debug logging for Turbo Stream response
          Rails.logger.debug do
            "[ContentsController] Rendering Turbo Stream response for content ##{@content.id} with #{@analysis_results&.size || 0} results"
          end

          # Render multiple Turbo Stream actions
          render turbo_stream: [
            # Replace the content
            turbo_stream.replace(
              @content,
              partial: "contents/content",
              locals: { content: @content, analysis_results: @analysis_results }
            ),
            # Add flash messages at the top of the page
            turbo_stream.update(
              "flash_messages",
              partial: "shared/flash_messages"
            )
          ]
        end
      end
    rescue StandardError => e
      Rails.logger.error { "[ContentsController] Analysis failed: #{e.message}\n#{e.backtrace.join('\n')}" }
      redirect_to @content, alert: "Analysis failed: #{e.message}"
    end
  end

  private

  def set_content
    @content = Content.find(params[:id])
  end

  def content_params
    params.require(:content).permit(:note, files: [])
  end
end
