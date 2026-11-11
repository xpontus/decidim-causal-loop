# frozen_string_literal: true

# Puma listens on the loopback interface only; the reverse proxy (Caddy)
# terminates TLS and forwards to it. BIND_ADDRESS=0.0.0.0 to change that.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
threads threads_count, threads_count

bind "tcp://#{ENV.fetch("BIND_ADDRESS", "127.0.0.1")}:#{ENV.fetch("PORT", 3000)}"

plugin :tmp_restart
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
