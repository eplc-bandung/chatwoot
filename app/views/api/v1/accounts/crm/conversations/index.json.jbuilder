json.data do
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/accounts/crm/conversations/conversation', formats: [:json], conversation: conversation
  end
end

json.meta do
  json.partial! 'api/v1/accounts/crm/pagination_meta', formats: [:json], paginated: @conversations
end
