# Shared page/per_page parsing for the CRM integration API. Used by both
# CrmApi::ConversationQuery and Api::V1::Accounts::Crm::Conversations::MessagesController
# so the pagination contract (defaults, max page size) stays identical everywhere.
class CrmApi::PaginationParams
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  def self.page(params)
    value = params[:page].to_i
    value.positive? ? value : 1
  end

  def self.per_page(params)
    requested = params[:per_page].to_i
    return DEFAULT_PER_PAGE unless requested.positive?

    [requested, MAX_PER_PAGE].min
  end
end
