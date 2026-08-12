# GET /api/v1/accounts/:account_id/crm/metadata
#
# Everything the CRM needs to build its filter dropdowns in a single call:
# inboxes (with their CRM channel slug), labels, agents, teams, the valid
# status/priority enums, and the distinct Meta ads observed so far. Without
# this, the CRM team would have to hardcode filter options that drift from
# the account's actual configuration.
class Api::V1::Accounts::Crm::MetadataController < Api::V1::Accounts::Crm::BaseController
  def show
    @inboxes = Current.account.inboxes.order(:name)
    @labels = Current.account.labels.order(:title)
    @agents = Current.account.users.order(:name)
    @teams = Current.account.teams.order(:name)
    @meta_ads = meta_ads
  end

  private

  # Distinct (ad_id, headline) pairs observed across this account's conversations.
  # Capped to keep the response bounded on accounts with a long ad history.
  def meta_ads
    Current.account.conversations
           .where("(additional_attributes -> 'ctwa_referral' ->> 'ad_id') IS NOT NULL")
           .distinct
           .limit(200)
           .pluck(
             Arel.sql("additional_attributes -> 'ctwa_referral' ->> 'ad_id'"),
             Arel.sql("additional_attributes -> 'ctwa_referral' ->> 'headline'")
           )
           .map { |ad_id, headline| { ad_id: ad_id, headline: headline } }
  end
end
