require Rails.root.join("app/lib/laser_focus/config").to_s

env_path     = Rails.root.join("config", "laserfocus.#{Rails.env}.yml")
default_path = Rails.root.join("config", "laserfocus.yml")

LASER_FOCUS_CONFIG = LaserFocus::Config.load_from_path(
  File.exist?(env_path) ? env_path : default_path
)
