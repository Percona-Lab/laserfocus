Rails.application.routes.draw do
  root "board#show"
  get  "/community", to: "board#show", defaults: { view: "community" }
  get  "/next",    to: "next#show"
  get  "/history", to: "epic_history#show"
  post "/sync", to: "syncs#create"
  patch "/column_order", to: "column_orders#update"
  patch "/column_collapse", to: "column_collapses#update"
  patch  "/stale_snooze", to: "stale_snoozes#update"
  delete "/stale_snooze", to: "stale_snoozes#destroy"
  get  "/login",  to: "sessions#new"
  get  "/auth/:provider/callback", to: "sessions#create"
  get  "/auth/failure",            to: "sessions#failure"
  delete "/logout", to: "sessions#destroy"
end
