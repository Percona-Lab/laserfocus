require Rails.root.join("app/lib/korkban/config").to_s

env_path     = Rails.root.join("config", "korkban.#{Rails.env}.yml")
default_path = Rails.root.join("config", "korkban.yml")

KORKBAN_CONFIG = Korkban::Config.load_from_path(
  File.exist?(env_path) ? env_path : default_path
)
