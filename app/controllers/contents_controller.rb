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

    # Group entities by their statements for display
    # In V2 model, entities don't have types, they have statements
    Rails.logger.debug { "[ContentsController] Preparing entities for display" } if ENV["DEBUG"]

    # Create a simulated analysis result with the entities
    return unless @content.entities.any?

    # Create an annotated description from the entities and their statements
    annotated_description = "This content contains: "
    @content.entities.each do |entity|
      annotated_description += "[#{entity.name}] "
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

  # POST /contents/:id/analyze
  # Analyze the content using OpenAI and extract entities
  def analyze
    # Find the content
    @content = Content.find(params[:id])

    # Create the service
    service = ContentAnalysisService.new

    begin
      # Prepare files for analysis
      files = prepare_files_for_analysis(@content)

      # Get the notes
      notes = [@content.note]

      # Perform analysis
      Rails.logger.debug { "[ContentsController] Starting analysis for content ##{@content.id}" }
      results = service.analyze(notes: notes, files: files)

      # Process results and extract entities
      Rails.logger.debug { "[ContentsController] Processing analysis results" }
      processing_result = service.process_analysis_results(@content, results)

      if processing_result[:success]
        # Store results for rendering
        @analysis_results = processing_result[:results]

        # Set flash messages based on processing results
        set_analysis_flash_messages(processing_result)

        # Add debug logging
        Rails.logger.debug { "[ContentsController] Analysis completed with #{processing_result[:entity_count]} entities extracted" }

        # Render appropriate response
        respond_to do |format|
          format.html { render :show }
          format.json { render json: { content: @content, analysis: @analysis_results } }
          format.turbo_stream { render_turbo_stream_response }
        end
      else
        # Handle processing failure
        flash[:alert] = processing_result[:message]
        redirect_to @content
      end
    rescue StandardError => e
      Rails.logger.error { "[ContentsController] Analysis failed: #{e.message}\n#{e.backtrace.join("\n")}" }
      redirect_to @content, alert: "Analysis failed: #{e.message}"
    end
  end

  private

  # Prepare files for analysis from content attachments
  # @param content [Content] The content with attachments
  # @return [Array<Hash>] Array of file hashes with filename and data
  def prepare_files_for_analysis(content)
    files = []

    content.files.attachments.each do |attachment|
      data = attachment.download
      files << { filename: attachment.filename.to_s, data: data }
      Rails.logger.debug { "[ContentsController] Prepared file #{attachment.filename} (#{data.size} bytes) for analysis" }
    rescue StandardError => e
      Rails.logger.error { "[ContentsController] Error downloading attachment: #{e.message}" }
    end

    files
  end

  # Set flash messages based on analysis results
  # @param processing_result [Hash] The result from process_analysis_results
  def set_analysis_flash_messages(processing_result)
    # Check if any files were skipped
    if processing_result[:skipped_files].any?
      flash.now[:warning] = "Some files were skipped during analysis: #{processing_result[:skipped_files].join(', ')}"
    end

    # Set success or info message based on entity count
    if processing_result[:entity_count].positive?
      flash.now[:notice] = "Content was successfully analyzed. Found #{processing_result[:entity_count]} entities."
    else
      flash.now[:info] = "Analysis completed, but no entities were found."
    end
  end

  # Render Turbo Stream response for analysis results
  def render_turbo_stream_response
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

  def set_content
    @content = Content.find(params[:id])
  end

  def content_params
    params.require(:content).permit(:note, files: [])
  end
end
