# frozen_string_literal: true

# Controller for managing entities in the knowledge graph
class EntitiesController < ApplicationController
  before_action :set_entity, only: [:show, :edit, :update, :destroy, :merge]

  # GET /entities
  def index
    @entities = Entity.order(:name)

    # Filter by name if provided
    @entities = @entities.where("name ILIKE ?", "%#{params[:query]}%") if params[:query].present?

    # Paginate results
    @entities = @entities.page(params[:page]).per(20)

    # Debug logging
    Rails.logger.debug { "Found #{@entities.total_count} entities matching query: #{params[:query]}" } if ENV["DEBUG"]
  end

  # GET /entities/1
  def show
    # Load associated statements
    @subject_statements = @entity.statements.includes(:object_entity, :content).order(confidence: :desc)
    @object_statements = Statement.where(object_entity: @entity).includes(:entity, :content).order(confidence: :desc)

    # Get similar entities for potential merging
    @similar_entities = find_similar_entities(@entity)

    # Debug logging
    Rails.logger.debug { "Viewing entity ##{@entity.id}: #{@entity.name} with #{@subject_statements.size} statements" } if ENV["DEBUG"]
  end

  # GET /entities/new
  def new
    @entity = Entity.new
  end

  # GET /entities/1/edit
  def edit; end

  # POST /entities
  def create
    @entity = Entity.new(entity_params)

    if @entity.save
      # Generate embedding in background
      OpenAI::EmbeddingJob.perform_later(@entity, :name) if @entity.persisted?

      redirect_to @entity, notice: "Entity was successfully created."
    else
      render :new
    end
  end

  # PATCH/PUT /entities/1
  def update
    if @entity.update(entity_params)
      # Regenerate embedding if name changed
      if @entity.saved_change_to_name?
        OpenAI::EmbeddingJob.perform_later(@entity, :name)
        Rails.logger.debug { "Regenerating embedding for entity ##{@entity.id} after name change" } if ENV["DEBUG"]
      end

      redirect_to @entity, notice: "Entity was successfully updated."
    else
      render :edit
    end
  end

  # DELETE /entities/1
  def destroy
    @entity.destroy
    redirect_to entities_url, notice: "Entity was successfully destroyed."
  end

  # POST /entities/verify
  def verify
    # Handle entity verification from content analysis
    entity_name = params[:entity_name]
    content_id = params[:content_id]
    action = params[:verification_action] # "use_existing", "create_new", or "merge"

    Rails.logger.debug { "Entity verification: #{action} for '#{entity_name}' in content ##{content_id}" } if ENV["DEBUG"]

    case action
    when "use_existing"
      # Use an existing entity
      existing_entity_id = params[:existing_entity_id]
      entity = Entity.find(existing_entity_id)

      # Process pending statements for this entity
      process_pending_statements(entity_name, entity, content_id)

      redirect_to entity, notice: "Used existing entity '#{entity.name}'"

    when "create_new"
      # Create a new entity
      entity = Entity.create(name: entity_name, content_id: content_id)

      if entity.persisted?
        # Generate embedding
        OpenAI::EmbeddingJob.perform_later(entity, :name)

        # Process pending statements
        process_pending_statements(entity_name, entity, content_id)

        redirect_to entity, notice: "Created new entity '#{entity.name}'"
      else
        redirect_to content_path(content_id), alert: "Failed to create entity: #{entity.errors.full_messages.join(', ')}"
      end

    when "merge"
      # Merge entities - handled by separate action
      redirect_to merge_entities_path(source_id: params[:source_entity_id], target_id: params[:target_entity_id])
    else
      redirect_to content_path(content_id), alert: "Invalid verification action"
    end
  end

  # GET /entities/merge_form
  def merge_form
    @source_entity = Entity.find(params[:source_id])
    @target_entity = Entity.find(params[:target_id])

    # Preview the merge
    @subject_statements = @source_entity.statements.includes(:object_entity, :content)
    @object_statements = Statement.where(object_entity: @source_entity).includes(:entity, :content)
  end

  # POST /entities/merge
  def merge
    target_entity_id = params[:target_entity_id]

    # Validate target entity
    target_entity = Entity.find(target_entity_id)

    # Use the entity management service to perform the merge
    service = EntityManagementService.new
    result = service.merge_entities(@entity.id, target_entity.id)

    if result[:success]
      redirect_to target_entity,
                  notice: "Successfully merged '#{@entity.name}' into '#{target_entity.name}'. Transferred #{result[:transferred_statements]} statements."
    else
      redirect_to @entity, alert: "Failed to merge entities: #{result[:error]}"
    end
  end

  private

  # Find similar entities based on name similarity
  def find_similar_entities(entity, limit: 5)
    service = EntityManagementService.new
    service.find_similar_entities(entity.name, limit: limit)
  end

  # Process pending statements for a verified entity
  def process_pending_statements(candidate_name, entity, content_id)
    # This would typically be stored in a temporary table or cache
    # For now, we'll assume the pending statements are passed in the session
    pending_statements = session[:pending_statements]&.select { |s| s["entity_name"] == candidate_name } || []

    content = Content.find(content_id)

    pending_statements.each do |statement_data|
      # Create the statement with the verified entity
      statement_params = {
        entity: entity,
        text: "#{entity.name} #{statement_data['predicate']} #{statement_data['object']}",
        predicate: statement_data["predicate"],
        object: statement_data["object"],
        object_type: statement_data["object_type"] || "literal",
        confidence: statement_data["confidence"] || 0.7,
        content: content
      }

      # Handle object entity if it's an entity type
      if statement_params[:object_type] == "entity"
        object_entity = Entity.find_by(name: statement_data["object"])
        statement_params[:object_entity] = object_entity if object_entity
      end

      # Create the statement
      statement = Statement.create(statement_params)

      # Generate embedding
      OpenAI::EmbeddingJob.perform_later(statement, :text) if statement.persisted?
    end

    # Clear processed statements from session
    session[:pending_statements] = (session[:pending_statements] || []).reject { |s| s["entity_name"] == candidate_name }
  end

  # Set entity from params
  def set_entity
    @entity = Entity.find(params[:id])
  end

  # Only allow a list of trusted parameters through
  def entity_params
    params.require(:entity).permit(:name, :content_id)
  end
end
