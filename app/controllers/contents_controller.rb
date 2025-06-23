class ContentsController < ApplicationController
  before_action :set_content, only: [:show, :edit, :update, :destroy]

  # GET /contents
  def index
    @contents = Content.order(created_at: :desc)
    Rails.logger.debug { "[ContentsController] Listing all contents. Count: #{@contents.size}" }
  end

  # GET /contents/1
  def show
    Rails.logger.debug { "[ContentsController] Showing content ##{@content.id}" }
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

  private

  def set_content
    @content = Content.find(params[:id])
  end

  def content_params
    params.require(:content).permit(:note, files: [])
  end
end
