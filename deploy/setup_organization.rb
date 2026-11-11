# frozen_string_literal: true

# First-time setup of an instance without e-mail: a system administrator, one
# organization, its first administrator, and optionally a participatory
# process with a causal loop diagram.
#
#   bin/rails runner ../decidim-module-causal_loop/deploy/setup_organization.rb \
#     HOST [SECONDARY_HOST ...]
#
# Environment:
#   ORG_NAME            organization name (default "Decidim")
#   SYSTEM_ADMIN_EMAIL  system administrator (/system), required
#   ADMIN_EMAIL         first organization administrator, required
#   ADMIN_NAME          their name (default "Administrator")
#   PUBLIC=1            let visitors read without logging in (default: private)
#   PROCESS_TITLE       also create a participatory process with this title and
#                       a published causal loop component in it
#
# Registration is limited to existing users, and no welcome e-mail is sent.
# Passwords are generated and printed once. Re-running is safe: whatever
# already exists is left alone.

require_relative "lib/deploy_accounts"

host, *secondary_hosts = ARGV
abort "Usage: setup_organization.rb HOST [SECONDARY_HOST ...]" unless host
system_admin_email = ENV.fetch("SYSTEM_ADMIN_EMAIL") { abort "SYSTEM_ADMIN_EMAIL is required" }
admin_email = ENV.fetch("ADMIN_EMAIL") { abort "ADMIN_EMAIL is required" }
org_name = ENV.fetch("ORG_NAME", "Decidim")
locale = Decidim.default_locale.to_s

if Decidim::System::Admin.exists?(email: system_admin_email)
  puts "System administrator #{system_admin_email} exists."
else
  password = DeployAccounts.generate_password
  Decidim::System::Admin.create!(email: system_admin_email, password:, password_confirmation: password)
  DeployAccounts.print_credentials("System administrator (/system)", system_admin_email, password)
end

organization = Decidim::Organization.find_by(host:)
if organization
  puts "Organization #{host} exists."
else
  organization = Decidim::Organization.create!(
    name: { locale => org_name },
    short_name: { locale => org_name },
    host:,
    secondary_hosts:,
    reference_prefix: org_name.gsub(/[^A-Za-z]/, "").first(4).upcase.presence || "DEC",
    available_locales: Decidim.available_locales.map(&:to_s),
    default_locale: locale,
    users_registration_mode: :existing,
    force_users_to_authenticate_before_access_organization: ENV["PUBLIC"] != "1",
    badges_enabled: false,
    send_welcome_notification: false,
    file_upload_settings: Decidim::OrganizationSettings.default(:upload),
    colors: { primary: "#53bf40", secondary: "#4053bf", tertiary: "#bf4053" }
  )
  Decidim::System::CreateDefaultPages.call(organization)
  Decidim::System::CreateDefaultHelpPages.call(organization)
  Decidim::System::CreateDefaultContentBlocks.call(organization)
  puts "Organization #{host} created#{" (also #{secondary_hosts.join(", ")})" if secondary_hosts.any?}."
end

if Decidim::User.exists?(organization:, email: admin_email)
  puts "Administrator #{admin_email} exists."
else
  admin, password = DeployAccounts.create_or_reset_user(
    organization:, email: admin_email, name: ENV.fetch("ADMIN_NAME", "Administrator"), admin: true
  )
  DeployAccounts.print_credentials("Organization administrator", admin.email, password)
end

if (title = ENV.fetch("PROCESS_TITLE", nil))
  process = Decidim::ParticipatoryProcess.where(organization:).find { |p| p.title[locale] == title }
  process ||= Decidim::ParticipatoryProcess.create!(
    organization:,
    title: { locale => title },
    subtitle: { locale => title },
    slug: title.parameterize.presence || "causal-loop",
    description: { locale => "" },
    short_description: { locale => "" },
    published_at: Time.current
  )
  component = Decidim::Component.find_by(participatory_space: process, manifest_name: "causal_loop")
  component ||= Decidim::Component.create!(
    participatory_space: process,
    manifest_name: "causal_loop",
    name: { locale => title },
    published_at: Time.current
  )
  puts "Process #{process.slug}, causal loop component #{component.id}: " \
       "https://#{host}/processes/#{process.slug}/f/#{component.id}/"
end
