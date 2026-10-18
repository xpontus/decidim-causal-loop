# frozen_string_literal: true

require "spec_helper"

# What a site admin does to set up a diagram on a Decidim site: add the
# component to a space, publish it, and choose who may edit it. Driven
# through Decidim's own admin screens, to catch integration problems.
describe "Admin manages a diagram" do # rubocop:disable RSpec/DescribeClass -- a system spec of the admin screens
  let(:organization) { create(:organization, available_locales: [:en]) }
  let(:participatory_process) { create(:participatory_process, :with_steps, :published, organization:) }
  let(:admin) { create(:user, :admin, :confirmed, organization:) }
  let!(:participant) { create(:user, :confirmed, organization:, name: "Rickard Participant") }
  let(:component) { participatory_process.components.find_by!(manifest_name: "causal_loop") }

  def open_actions(component)
    find("button[aria-label='Actions for causal_loop'][data-target='actions-component-#{component.id}']").click
  end

  before do
    switch_to_host(organization.host)
    login_as admin, scope: :user
  end

  it "adds and publishes the component, and grants and revokes edit access" do
    visit decidim_admin_participatory_processes.components_path(participatory_process)
    click_on "Add component"
    click_on "RUSIF Causal Loop Diagram"
    fill_in "component_name_en", with: "Island tourism"
    within("form.new_component") { click_on "Add component" }
    expect(page).to have_content("Component created successfully")

    open_actions(component)
    find("a[href$='/components/#{component.id}/publish']").click
    expect(page).to have_content("successfully published")
    expect(component.reload).to be_published

    open_actions(component)
    find("a.dropdown__button[href$='/components/#{component.id}/manage/']").click
    expect(page).to have_content("Diagram editors")
    expect(page).to have_link("open the diagram", href: Decidim::EngineRouter.main_proxy(component).root_path)

    select "Rickard Participant", from: "decidim_user_id"
    click_on "Add editor"
    expect(page).to have_content("Editor added.")
    within("table") { expect(page).to have_content("Rickard Participant") }

    login_as participant, scope: :user
    visit Decidim::EngineRouter.main_proxy(component).root_path
    expect(page).to have_content("Island tourism")
    expect(page).to have_button("+ Add node")

    login_as admin, scope: :user
    visit Decidim::EngineRouter.admin_proxy(component).root_path
    accept_confirm { click_on "Remove" }
    expect(page).to have_content("Editor removed.")

    login_as participant, scope: :user
    visit Decidim::EngineRouter.main_proxy(component).root_path
    expect(page).to have_content("You do not have edit access to this diagram")
  end
end
