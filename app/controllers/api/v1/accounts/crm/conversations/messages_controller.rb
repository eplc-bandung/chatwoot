# GET /api/v1/accounts/:account_id/crm/conversations/:conversation_id/messages
#
# Paginated transcript for a single conversation, newest first. Powers the
# CRM's chat-history view. Per-message content_attributes (including the raw
# Meta referral payload, when present) are exposed for multi-touch attribution.
class Api::V1::Accounts::Crm::Conversations::MessagesController < Api::V1::Accounts::Crm::BaseController
  before_action :conversation

  def index
    @messages = @conversation.messages
                             .chat
                             .includes(:attachments, :sender)
                             .reorder(created_at: :desc, id: :desc)
                             .page(CrmApi::PaginationParams.page(params))
                             .per(CrmApi::PaginationParams.per_page(params))
  end

  private

  def conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end
end
