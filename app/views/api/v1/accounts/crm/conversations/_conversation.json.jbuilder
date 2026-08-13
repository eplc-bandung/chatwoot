json.id conversation.display_id
json.uuid conversation.uuid
json.status conversation.status
json.priority conversation.priority

json.lead do
  contact = conversation.contact
  json.id contact.id
  json.name contact.name
  json.phone_number contact.phone_number
  json.email contact.email
  json.thumbnail contact.avatar_url
end

json.channel CrmApi::ChannelMap.slug_for(conversation.inbox)
json.inbox do
  json.id conversation.inbox.id
  json.name conversation.inbox.name
end

json.labels conversation.cached_label_list_array

if conversation.assignee.present?
  json.assignee do
    json.id conversation.assignee.id
    json.name conversation.assignee.name
  end
else
  json.assignee nil
end

if conversation.team.present?
  json.team do
    json.id conversation.team.id
    json.name conversation.team.name
  end
else
  json.team nil
end

last_message = conversation.messages.where(account_id: conversation.account_id).non_activity_messages.first
if last_message.present?
  json.last_message do
    json.id last_message.id
    json.content last_message.content
    json.direction last_message.message_type
    json.content_type last_message.content_type
    json.created_at last_message.created_at.utc.iso8601
  end
else
  json.last_message nil
end

json.unread_count conversation.unread_incoming_messages.count
json.created_at conversation.created_at.utc.iso8601
json.last_activity_at conversation.last_activity_at.utc.iso8601
json.first_reply_created_at conversation.first_reply_created_at&.utc&.iso8601

ctwa_referral = conversation.additional_attributes['ctwa_referral']
if ctwa_referral.present?
  json.meta_ads do
    json.source ctwa_referral['source']
    json.ad_id ctwa_referral['ad_id']
    json.ctwa_clid ctwa_referral['ctwa_clid']
    json.headline ctwa_referral['headline']
    json.source_url ctwa_referral['source_url']
    json.captured_at ctwa_referral['captured_at']
  end
else
  json.meta_ads nil
end
