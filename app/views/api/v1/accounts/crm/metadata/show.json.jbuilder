json.channels CrmApi::ChannelMap::SLUGS

json.statuses Conversation.statuses.keys
json.priorities Conversation.priorities.keys

json.inboxes @inboxes do |inbox|
  json.id inbox.id
  json.name inbox.name
  json.channel CrmApi::ChannelMap.slug_for(inbox)
end

json.labels @labels do |label|
  json.id label.id
  json.title label.title
  json.color label.color
end

json.agents @agents do |agent|
  json.id agent.id
  json.name agent.name
  json.email agent.email
end

json.teams @teams do |team|
  json.id team.id
  json.name team.name
end

json.meta_ads @meta_ads
