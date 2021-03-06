# frozen_string_literal: true

module Europeana
  module Blacklight
    ##
    # Core search builder for {Europeana::Blacklight::ApiRepository}
    class SearchBuilder < ::Blacklight::SearchBuilder
      require 'europeana/blacklight/search_builder/facet_pagination'
      require 'europeana/blacklight/search_builder/more_like_this'
      require 'europeana/blacklight/search_builder/overlay_params'
      require 'europeana/blacklight/search_builder/ranges'

      self.default_processor_chain = %i(
        default_api_parameters add_profile_to_api
        add_query_to_api add_qf_to_api add_facet_qf_to_api add_query_facet_to_api
        add_standalone_facets_to_api add_facetting_to_api add_paging_to_api
        add_sorting_to_api add_api_url_to_api
      )

      include FacetPagination
      include MoreLikeThis
      include Ranges
      include OverlayParams

      delegate :to_query, :delete, to: :to_hash

      STANDALONE_FACETS = %w(COLOURPALETTE MEDIA REUSABILITY THUMBNAIL).freeze

      MEDIA_FACETS = %w(COLOURPALETTE IMAGE_ASPECTRATIO IMAGE_COLOR IMAGE_COLOUR
                        IMAGE_GRAYSCALE IMAGE_GREYSCALE IMAGE_SIZE MEDIA MIME_TYPE
                        SOUND_DURATION SOUND_HQ TEXT_FULLTEXT VIDEO_DURATION
                        VIDEO_HD).freeze

      ##
      # Start with general defaults from BL config. Need to use custom
      # merge to dup values, to avoid later mutating the original by mistake.
      #
      # @todo Rename default_solr_params to default_params upstream
      def default_api_parameters(api_parameters)
        blacklight_config.default_solr_params.each do |key, value|
          api_parameters[key] = if value.respond_to?(:deep_dup)
                                  value.deep_dup
                                elsif value.respond_to?(:dup) && value.duplicable?
                                  value.dup
                                else
                                  value
                                end
        end
      end

      ##
      # Set the profile type
      #
      # @see http://labs.europeana.eu/api/search/#profile-parameter
      def add_profile_to_api(api_parameters)
        api_parameters[:profile] = 'params rich'
        api_parameters[:profile] = api_parameters[:profile] + ' facets' if blacklight_config.facet_fields
      end

      ##
      # Take the user-entered query, and put it in the API params,
      # including config's "search field" params for current search field.
      #
      # @see http://labs.europeana.eu/api/query/
      def add_query_to_api(api_parameters)
        if [blacklight_params[:q]].flatten.reject(&:blank?).blank?
          query = '*:*'
        elsif search_field && search_field.field.present?
          query = "#{search_field.field}:#{blacklight_params[:q]}"
        elsif blacklight_params[:q].is_a?(Hash)
          # @todo when would it be a Hash?
          query = nil
        elsif blacklight_params[:q]
          query = blacklight_params[:q]
        end
        append_to_query_param(api_parameters, query)
      end

      ##
      # Add the user's query filter terms
      def add_qf_to_api(api_parameters)
        return unless blacklight_params[:qf]
        api_parameters[:qf] ||= []
        api_parameters[:qf] = api_parameters[:qf] + blacklight_params[:qf]
      end

      ##
      # Facet *filtering* of results
      #
      # Maps Blacklight's :f param to API's :qf param.
      #
      # @see http://labs.europeana.eu/api/query/#faceted-search
      # @todo Handle different types of value, like
      #   {Blacklight::Solr::SearchBuilder#facet_value_to_fq_string} does
      def add_facet_qf_to_api(api_parameters)
        return unless blacklight_params[:f]

        salient_facets_for_api_facet_qf.each_pair do |facet_field, values|
          [values].flatten.compact.each do |value|
            api_parameters[:qf] ||= []
            api_parameters[:qf] << "#{facet_field}:" + quote_facet_value(facet_field, value)
          end
        end
      end

      def salient_facets_for_api_facet_qf
        blacklight_params[:f].select do |k, _v|
          !STANDALONE_FACETS.include?(k) && api_request_facet_fields.keys.include?(k)
        end
      end

      def quote_facet_value(facet_field, value)
        return value if MEDIA_FACETS.include?(facet_field)
        return value if value.include?('*')
        '"' + value.gsub('"', '\"') + '"'
      end

      ##
      # Filter results by a query facet
      def add_query_facet_to_api(_api_parameters)
        return unless blacklight_params[:f]

        salient_facets = blacklight_params[:f].select do |k, _v|
          facet = blacklight_config.facet_fields[k]
          facet.present? && facet.query && (facet.include_in_request || (facet.include_in_request.nil? && blacklight_config.add_facet_fields_to_solr_request))
        end

        salient_facets.each_pair do |facet_field, value_list|
          Array(value_list).reject(&:blank?).each do |value|
            with_overlay_params(blacklight_config.facet_fields[facet_field].query[value][:fq])
          end
        end
      end

      ##
      # Some facets need to be filtered as distinct API params, even though
      # they are returned with the facets in a search response
      def add_standalone_facets_to_api(api_parameters)
        STANDALONE_FACETS.each do |field|
          if blacklight_params[:f] && blacklight_params[:f][field]
            api_parameters[field.downcase.to_sym] = blacklight_params[:f][field].join(',')
          end
        end
      end

      ##
      # Request facet data in results, respecting configured limits
      #
      # @todo Handle facet settings like query, sort, pivot, etc, like
      #  {Blacklight::Solr::SearchBuilder#add_facetting_to_solr} does
      # @see http://labs.europeana.eu/api/search/#individual-facets
      # @see http://labs.europeana.eu/api/search/#offset-and-limit-of-facets
      def add_facetting_to_api(api_parameters)
        api_parameters[:facet] = api_request_facet_fields.keys.uniq.join(',')

        api_request_facet_fields.each do |field_name, facet|
          api_parameters[:"f.#{facet.field}.facet.limit"] = facet_limit_for(field_name) if facet_limit_for(field_name)
        end
      end

      ##
      # copy paging params from BL app over to API, changing
      # app level per_page and page to API rows and start.
      def add_paging_to_api(api_parameters)
        rows(api_parameters[:rows] || 10) if rows.nil?
        api_parameters[:rows] = rows

        api_parameters[:start] = start unless start == 0
      end

      def add_sorting_to_api(api_parameters)
        api_parameters[:sort] = sort
      end

      def add_api_url_to_api(api_parameters)
        return unless blacklight_params[:api_url]
        api_parameters[:api_url] = blacklight_params[:api_url]
      end

      ##
      # Europeana API start param counts from 1
      def start(start = nil)
        if start
          params_will_change!
          @start = start.to_i
          self
        else
          @start ||= (page - 1) * (rows || 10) + 1

          val = @start || 1
          val = 1 if @start < 1
          val
        end
      end

      protected

      # Look up facet limit for given facet_field. Will look at config, and
      # if config is 'true' will look up from Solr @response if available. If
      # no limit is avaialble, returns nil. Used from #add_facetting_to_solr
      # to supply f.fieldname.facet.limit values in solr request (no @response
      # available), and used in display (with @response available) to create
      # a facet paginator with the right limit.
      def facet_limit_for(facet_field)
        facet = blacklight_config.facet_fields[facet_field]
        return if facet.blank? || !facet.limit

        if facet.limit == true
          blacklight_config.default_facet_limit
        else
          facet.limit
        end
      end

      def api_request_facet_fields
        @api_request_facet_fields ||= blacklight_config.facet_fields.select do |_field_name, facet|
          requestable_facet?(facet)
        end
      end

      def requestable_facet?(facet)
        if facet.query
          false
        elsif facet.include_in_request == false
          false
        else
          blacklight_config.add_facet_fields_to_solr_request
        end
      end

      def append_to_query_param(api_parameters, query)
        return if query.blank?
        return if query == '*:*' && api_parameters[:query].present?
        api_parameters[:query] ||= ''
        api_parameters[:query] = api_parameters[:query] + ' ' unless api_parameters[:query].blank?
        api_parameters[:query] = api_parameters[:query] + query
      end
    end
  end
end
