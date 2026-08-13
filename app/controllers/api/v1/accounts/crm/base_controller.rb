# Read-only API consumed by external CRM systems (see docs/crm_integration_api.md).
#
# Auth reuses the existing api_access_token mechanism (Api::BaseController /
# AccessTokenAuthHelper) — no new auth code. Bot tokens are already rejected
# for any controller not listed in AccessTokenAuthHelper::BOT_ACCESSIBLE_ENDPOINTS,
# which this namespace deliberately never joins: it is a read-only integration
# surface, not something agent bots should drive.
#
# Visibility is delegated to Conversations::PermissionFilterService, same as
# the dashboard: administrators see the whole account, other users see only
# their own inboxes. The intended caller is a dedicated "CRM Integration"
# administrator user's access token.
class Api::V1::Accounts::Crm::BaseController < Api::V1::Accounts::BaseController
  rescue_from CrmApi::InvalidFilterError, with: :render_invalid_filter

  private

  def render_invalid_filter(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end
