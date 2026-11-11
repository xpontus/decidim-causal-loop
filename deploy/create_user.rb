# frozen_string_literal: true

# Creates a participant on an instance without e-mail: confirmed, terms of
# service accepted, with a generated password printed once.
#
#   bin/rails runner ../decidim-module-causal_loop/deploy/create_user.rb \
#     EMAIL "Full Name" [--admin] [--editor COMPONENT_ID] [--reset] [--host HOST]
#
#   --admin       organization administrator (can edit every diagram)
#   --editor ID   may edit the diagram of causal loop component ID
#   --reset       the user exists: generate a new password instead
#   --host HOST   which organization, if there are several

require_relative "lib/deploy_accounts"

args = ARGV.dup
flag = ->(name) { !args.delete(name).nil? }
option = lambda do |name|
  i = args.index(name)
  next nil unless i

  value = args.delete_at(i + 1) || abort("#{name} needs a value")
  args.delete_at(i)
  value
end

admin = flag.call("--admin")
reset = flag.call("--reset")
editor = option.call("--editor")
host = option.call("--host")
email, name = args
usage = "Usage: create_user.rb EMAIL \"Full Name\" [--admin] [--editor COMPONENT_ID] [--reset] [--host HOST]"
abort usage unless email && (name || reset) && args.size <= 2

organization = DeployAccounts.organization(host)
user, password = DeployAccounts.create_or_reset_user(
  organization:, email:, name: name.to_s, admin:, reset:
)

if editor
  component = Decidim::Component.find_by!(id: editor, manifest_name: "causal_loop")
  abort "Component #{editor} belongs to another organization." unless component.organization == organization
  Decidim::CausalLoop::Editor.find_or_create_by!(decidim_component_id: component.id, decidim_user_id: user.id)
  puts "Editor of component #{component.id}."
end

DeployAccounts.print_credentials(admin ? "Administrator" : "User", user.email, password)
