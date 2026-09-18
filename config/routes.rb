Rails.application.routes.draw do
  root "board#show"
  get  "/history", to: "epic_history#show"
  post "/sync", to: "syncs#create"
  patch "/column_order", to: "column_orders#update"
  patch "/column_collapse", to: "column_collapses#update"
  get  "/login",  to: "sessions#new"
  get  "/auth/:provider/callback", to: "sessions#create"
  get  "/auth/failure",            to: "sessions#failure"
  delete "/logout", to: "sessions#destroy"
end
