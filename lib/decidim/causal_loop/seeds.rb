# frozen_string_literal: true

require "decidim/seeds"
require "decidim/components/namer"

module Decidim
  module CausalLoop
    # Seeds a small but complete example diagram, so a freshly seeded
    # installation shows what the component is for instead of an empty canvas.
    #
    # The example deliberately contains one reinforcing and one balancing loop,
    # which is the smallest diagram that demonstrates why polarity matters:
    #
    #   R:  Participation -(+)-> Trust in the process -(+)-> Participation
    #       no negative links, so the loop amplifies itself
    #
    #   B:  Participation -(+)-> Moderation workload -(-)-> Response speed
    #                      -(+)-> Trust in the process -(+)-> Participation
    #       one negative link, so the loop is self-limiting
    class Seeds < Decidim::Seeds
      attr_reader :participatory_space

      # Laid out by hand rather than by a layout algorithm, so the two loops
      # read clearly on first view.
      NODES = [
        { key: :participation, title: "Participation", x: 420, y: 120 },
        { key: :trust, title: "Trust in the process", x: 180, y: 300 },
        { key: :workload, title: "Moderation workload", x: 680, y: 300 },
        { key: :speed, title: "Response speed", x: 420, y: 470 }
      ].freeze

      LINKS = [
        { from: :participation, to: :trust, polarity: "positive" },
        { from: :trust, to: :participation, polarity: "positive" },
        { from: :participation, to: :workload, polarity: "positive" },
        { from: :workload, to: :speed, polarity: "negative" },
        { from: :speed, to: :trust, polarity: "positive" }
      ].freeze

      def initialize(participatory_space:)
        @participatory_space = participatory_space
      end

      def call
        component = create_component!
        nodes = create_nodes!(component)
        create_links!(component, nodes)
        grant_example_editor!(component)

        component
      end

      private

      def create_component!
        params = {
          name: Decidim::Components::Namer.new(
            participatory_space.organization.available_locales, :causal_loop
          ).i18n_name,
          manifest_name: :causal_loop,
          published_at: Time.current,
          participatory_space:
        }

        Decidim.traceability.perform_action!(
          "publish",
          Decidim::Component,
          admin_user,
          visibility: "all"
        ) do
          Decidim::Component.create!(params)
        end
      end

      def create_nodes!(component)
        NODES.each_with_object({}) do |attrs, acc|
          acc[attrs[:key]] = Decidim::CausalLoop::Node.create!(
            decidim_component_id: component.id,
            title: attrs[:title],
            position_x: attrs[:x],
            position_y: attrs[:y]
          )
        end
      end

      def create_links!(component, nodes)
        LINKS.each do |attrs|
          Decidim::CausalLoop::Link.create!(
            decidim_component_id: component.id,
            source_node_id: nodes.fetch(attrs[:from]).id,
            target_node_id: nodes.fetch(attrs[:to]).id,
            polarity: attrs[:polarity]
          )
        end
      end

      # Give the regular seeded participant edit access, so the Editors feature
      # is visible in a seeded installation rather than having to be discovered.
      def grant_example_editor!(component)
        user = Decidim::User.find_by(
          organization: participatory_space.organization,
          email: "user@example.org"
        )
        return if user.blank?

        Decidim::CausalLoop::Editor.find_or_create_by!(
          decidim_component_id: component.id,
          decidim_user_id: user.id
        )
      end
    end
  end
end
