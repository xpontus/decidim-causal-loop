# frozen_string_literal: true

namespace :decidim_causal_loop do
  desc "Removes nodes and links deleted more than 30 days ago (DAYS=n to change)"
  task purge_deleted: :environment do
    before = ENV.fetch("DAYS", Decidim::CausalLoop::DeletedRecords::PURGE_AFTER.in_days).to_i.days.ago
    counts = Decidim::CausalLoop::DeletedRecords.purge!(before:)
    puts "Purged #{counts[:nodes]} nodes and #{counts[:links]} links deleted before #{before}"
  end
end
