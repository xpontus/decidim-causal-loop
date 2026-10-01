# frozen_string_literal: true

module Decidim
  module CausalLoop
    module Admin
      class EditorsController < ApplicationController
        def index
          @editors = Editor.where(decidim_component_id: current_component.id)
                           .includes(:user)
                           .order(:created_at)
          @participants = current_organization.users
                                              .confirmed
                                              .where.not(id: @editors.select(:decidim_user_id))
                                              .order(:name)
        end

        def create
          user = current_organization.users.find(params[:decidim_user_id])
          Editor.find_or_create_by!(decidim_component_id: current_component.id,
                                    decidim_user_id: user.id)
          redirect_to editors_path, notice: t(".created")
        end

        def destroy
          editor = Editor.find_by!(decidim_component_id: current_component.id,
                                   id: params[:id])
          editor.destroy!
          redirect_to editors_path, notice: t(".destroyed")
        end
      end
    end
  end
end
