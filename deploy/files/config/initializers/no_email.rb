# frozen_string_literal: true

# This instance sends no e-mail: accounts are created by an administrator
# (deploy/create_user.rb) and passwords are handed out directly. Without this,
# notifications, invitations and password resets would try to reach an SMTP
# server that does not exist.
ActiveSupport.on_load(:action_mailer) do
  self.perform_deliveries = false
end
