# GET /api/v1/accounts/:account_id/crm/conversations
# GET /api/v1/accounts/:account_id/crm/conversations/:id
#
# Lead-shaped, paginated conversation listing for the CRM integration.
# See docs/crm_integration_api.md for the full filter and payload reference.
class Api::V1::Accounts::Crm::ConversationsController < Api::V1::Accounts::Crm::BaseController
  def index
    @conversations = query.conversations
  end

  def show
    @conversation = Current.account.conversations.find_by!(display_id: params[:id])
    authorize @conversation, :show?
  end

  private

  def query
    CrmApi::ConversationQuery.new(account: Current.account, user: Current.user, params: filter_params)
  end

  def filter_params
    params.permit(
      :status, :channel, :labels, :assignee_id, :unassigned, :team_id, :priority,
      :source, :ad_id, :ctwa_clid, :created_after, :created_before, :updated_since,
      :q, :sort, :page, :per_page,
      inbox_id: [], status: [], channel: [], labels: [], assignee_id: [], team_id: [], priority: []
    )
  end
end
