json.data do
  json.array! @messages do |message|
    json.id message.id
    json.content message.content
    json.direction message.message_type
    json.content_type message.content_type
    json.private message.private
    json.status message.status
    if message.sender.present?
      json.sender do
        json.id message.sender.id
        json.name message.sender.name
        json.type message.sender_type
      end
    else
      json.sender nil
    end
    json.attachments message.attachments.map(&:push_event_data) if message.attachments.present?
    json.content_attributes message.content_attributes
    json.created_at message.created_at.utc.iso8601
  end
end

json.meta do
  json.partial! 'api/v1/accounts/crm/pagination_meta', formats: [:json], paginated: @messages
end
