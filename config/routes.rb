Rails.application.routes.draw do
  root "board#show"
  post "/sync", to: "syncs#create"
  get  "/login",  to: "sessions#new"
  get  "/auth/:provider/callback", to: "sessions#create"
  get  "/auth/failure",            to: "sessions#failure"
  delete "/logout", to: "sessions#destroy"
end
