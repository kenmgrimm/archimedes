# frozen_string_literal: true

class SearchController < ApplicationController
  # GET /search
  def index
    @query = params[:query]

    if @query.present?
      Rails.logger.debug { "[SearchController] Performing search with query: #{@query}" }

      # Find similar entities
      @entities = Entity.find_similar(@query, limit: 10)
      Rails.logger.debug { "[SearchController] Found #{@entities.size} similar entities" }

      # Find similar statements (V2 data model)
      @statements = Statement.find_similar(@query, limit: 10)
      Rails.logger.debug { "[SearchController] Found #{@statements.size} similar statements" } if ENV["DEBUG"]

      # Find entities by statement (V2 data model)
      @entities_by_statement = Entity.find_by_statement(@query, limit: 10)
      Rails.logger.debug { "[SearchController] Found #{@entities_by_statement.size} entities by statement" } if ENV["DEBUG"]

      # Find similar content
      @contents = Content.find_similar(@query, limit: 10)
      Rails.logger.debug { "[SearchController] Found #{@contents.size} similar content items" }

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    else
      @entities = []
      @statements = []
      @entities_by_statement = []
      @contents = []
    end
  end
end
