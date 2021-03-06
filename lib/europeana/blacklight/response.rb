# frozen_string_literal: true

module Europeana
  module Blacklight
    ##
    # Europeana API response for BL
    class Response < HashWithIndifferentAccess
      require 'europeana/blacklight/response/pagination'
      require 'europeana/blacklight/response/facets'
      require 'europeana/blacklight/response/more_like_this'

      include Pagination
      include Facets
      include MoreLikeThis

      attr_reader :request_params
      attr_accessor :document_model, :blacklight_config

      def initialize(data, request_params, options = {})
        super(data)
        @request_params = request_params
        self.document_model = options[:document_model] || Document
        self.blacklight_config = options[:blacklight_config]
      end

      def update(other_hash)
        other_hash.each_pair { |key, value| self[key] = value }
        self
      end

      def params
        self['params'] ? self['params'] : request_params
      end

      def rows
        params[:rows].to_i
      end

      def sort
        params[:sort]
      end

      def documents
        @documents ||= (key?('object') ? [self['object']] : (self['items'] || [])).map do |doc|
          document_model.new(doc, self)
        end
      end
      alias_method :docs, :documents

      def grouped
        []
      end

      def group(_key)
        nil
      end

      def grouped?
        false
      end

      def export_formats
        documents.map { |x| x.export_formats.keys }.flatten.uniq
      end

      def total
        self[:totalResults].to_s.to_i
      end

      def start
        params[:start].to_s.to_i - 1
      end

      def empty?
        total == 0
      end
    end
  end
end
