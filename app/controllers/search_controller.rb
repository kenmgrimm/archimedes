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

      # Find similar content
      @contents = Content.find_similar(@query, limit: 10)
      Rails.logger.debug { "[SearchController] Found #{@contents.size} similar content items" }

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    else
      @entities = []
      @contents = []
    end
  end
end
