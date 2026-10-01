# frozen_string_literal: true

module Decidim
  module CausalLoop
    # This controller is the abstract class from which all other controllers of
    # this engine inherit.
    #
    # Note that it inherits from `Decidim::Components::BaseController`, which
    # override its layout and provide all kinds of useful methods.
    class ApplicationController < Decidim::Components::BaseController
      # Our JSON endpoints are protected by authenticate_user! — skip the
      # cookie-based CSRF check which can stale out for long-lived AJAX sessions.
      skip_before_action :verify_authenticity_token, if: :json_request?

      private

      def json_request?
        request.content_type&.include?("application/json")
      end
    end
  end
end
