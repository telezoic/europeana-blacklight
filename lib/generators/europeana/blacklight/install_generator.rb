# frozen_string_literal: true

module Europeana
  module Blacklight
    class Install < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      argument :europeana_api_key, type: :string
      argument :controller_name, type: :string, default: 'catalog'

      def disable_solr_gems
        comment_lines('Gemfile', /gem 'solr_wrapper'/)
        comment_lines('Gemfile', /gem 'rsolr'/)
      end

      def bundle_install
        Bundler.with_clean_env do
          run 'bundle install'
        end
      end

      def create_configuration_files
        template 'config/blacklight.yml', 'config/blacklight.yml'
      end

      def generate_controller
        template 'catalog_controller.rb', "app/controllers/#{controller_name}_controller.rb"
      end
    end
  end
end
