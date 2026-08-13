# Raised by CrmApi::ConversationQuery when a filter param is malformed. Rescued by
# Api::V1::Accounts::Crm::BaseController and rendered as a 422.
class CrmApi::InvalidFilterError < StandardError; end
