# frozen_string_literal: true

require "decidim/components/namer"

Decidim.register_component(:causal_loop) do |component|
  component.engine = Decidim::CausalLoop::Engine
  component.admin_engine = Decidim::CausalLoop::AdminEngine
  component.icon = "decidim/causal_loop/icon.svg"
  component.permissions_class_name = "Decidim::CausalLoop::Permissions"

  # component.on(:before_destroy) do |instance|
  #   # Code executed before removing the component
  # end

  component.actions = %w(edit)

  # component.settings(:global) do |settings|
  #   # Add your global settings
  #   # Available types: :integer, :boolean
  #   # settings.attribute :vote_limit, type: :integer, default: 0
  # end

  # component.settings(:step) do |settings|
  #   # Add your settings per step
  # end

  # component.register_resource(:some_resource) do |resource|
  #   # Register a optional resource that can be references from other resources.
  #   resource.model_class_name = "Decidim::CausalLoop::SomeResource"
  #   resource.template = "decidim/causal_loop/some_resources/linked_some_resources"
  # end

  # component.register_stat :some_stat do |context, start_at, end_at|
  #   # Register some stat number to the application
  # end

  component.seeds do |participatory_space|
    require "decidim/causal_loop/seeds"

    Decidim::CausalLoop::Seeds.new(participatory_space:).call
  end
end
