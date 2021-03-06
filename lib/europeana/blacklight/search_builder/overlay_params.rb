# frozen_string_literal: true

module Europeana
  module Blacklight
    class SearchBuilder
      ##
      # "Overlay" params do not replace others, but are combined with them, into
      # multiple values for those param keys
      module OverlayParams
        extend ActiveSupport::Concern

        included do
          default_processor_chain << :add_overlay_params_to_api
        end

        def with_overlay_params(overlay_params = {})
          @overlay_params ||= []
          @overlay_params << overlay_params
          self
        end

        def add_overlay_params_to_api(api_parameters)
          return unless @overlay_params

          @overlay_params.each do |param_set|
            param_set.each_pair do |k, v|
              k = k.to_sym
              api_parameters[k] = if api_parameters.key?(k)
                                    [api_parameters[k]].flatten # in case it's not an Array
                                  else
                                    []
                                  end
              api_parameters[k] += [v]
              api_parameters[k] = api_parameters[k].flatten.uniq
            end
          end
        end
      end
    end
  end
end
