# A Jira ticket a discovery idea says it is delivered by. Stored by key because
# the target may be an Epic this board tracks, an Epic it does not, or a Story.
class IdeaDelivery < ApplicationRecord
  belongs_to :discovery_idea
end
