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

      # Decidim's router still finds components in the admin's trash, and
      # leaves hiding them to each component. A diagram in the trash is gone
      # for everyone until it is restored.
      before_action :not_found_if_trashed

      private

      def not_found_if_trashed
        raise ActionController::RoutingError, "Not Found" if current_component.deleted?
      end

      def json_request?
        request.content_type&.include?("application/json")
      end
    end
  end
end
