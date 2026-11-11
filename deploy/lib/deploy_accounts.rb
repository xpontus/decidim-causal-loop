# frozen_string_literal: true

require "securerandom"

# Keep the printed passwords readable when RAILS_LOG_TO_STDOUT is set.
Rails.logger.level = Logger::WARN

# Helpers shared by deploy/create_user.rb and deploy/setup_organization.rb.
# Accounts on an instance without e-mail: created confirmed, with the terms of
# service accepted and a generated password that is printed once.
module DeployAccounts
  module_function

  def generate_password(length = 20)
    SecureRandom.alphanumeric(length)
  end

  def organization(host)
    return Decidim::Organization.find_by!(host:) if host

    orgs = Decidim::Organization.all.to_a
    abort "No organization yet: run deploy/setup_organization.rb first." if orgs.empty?
    abort "Several organizations: pass --host (#{orgs.map(&:host).join(", ")})." if orgs.size > 1
    orgs.first
  end

  # Creates the user, or with reset: true gives an existing one a new password.
  # Returns [user, password].
  def create_or_reset_user(organization:, email:, name:, admin: false, reset: false)
    user = Decidim::User.find_by(organization:, email:)
    abort "#{email} already exists; pass --reset to give it a new password." if user && !reset
    abort "#{email} does not exist; --reset only applies to existing users." if !user && reset

    user ||= Decidim::User.new(
      organization:,
      email:,
      name:,
      nickname: Decidim::UserBaseEntity.nicknamize(name, organization.id),
      locale: organization.default_locale,
      tos_agreement: true
    )
    password = generate_password
    user.password = password
    user.password_confirmation = password
    user.password_updated_at = Time.current
    user.admin = true if admin
    user.confirmed_at ||= Time.current
    user.accepted_tos_version = organization.tos_version
    user.save!
    [user, password]
  end

  def print_credentials(label, email, password)
    puts "#{label}: #{email}"
    puts "  password: #{password}"
    puts "  (shown only now; hand it over directly)"
  end
end
