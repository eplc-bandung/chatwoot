require 'rails_helper'

RSpec.describe 'CRM Metadata API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/:account_id/crm/metadata' do
    it 'returns unauthorized when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/crm/metadata"

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when authenticated' do
      let(:inbox) do
        create(:channel_whatsapp, account: account, phone_number: "+1#{SecureRandom.random_number(10**10)}",
                                  validate_provider_config: false, sync_templates: false).inbox
      end
      let!(:team) { create(:team, account: account) }

      before do
        create(:label, account: account, title: 'hot')
        create(:conversation, account: account, inbox: inbox,
                              additional_attributes: { 'ctwa_referral' => { 'source' => 'meta_ads', 'ad_id' => 'ad-1', 'headline' => 'Promo' } })

        get "/api/v1/accounts/#{account.id}/crm/metadata",
            headers: { api_access_token: admin.access_token.token },
            as: :json
      end

      it 'lists the fixed enums for filter dropdowns' do
        body = response.parsed_body
        expect(body['channels']).to include('whatsapp', 'instagram', 'facebook')
        expect(body['statuses']).to match_array(%w[open resolved pending snoozed])
        expect(body['priorities']).to match_array(%w[low medium high urgent])
      end

      it 'lists the account-specific inboxes, labels, teams and agents' do
        body = response.parsed_body
        expect(body['inboxes']).to contain_exactly(a_hash_including('id' => inbox.id, 'channel' => 'whatsapp'))
        expect(body['labels'].map { |l| l['title'] }).to include('hot')
        expect(body['teams'].map { |t| t['id'] }).to include(team.id)
        expect(body['agents'].map { |a| a['id'] }).to include(admin.id)
      end

      it 'lists the distinct Meta ads observed on the account' do
        expect(response.parsed_body['meta_ads']).to include('ad_id' => 'ad-1', 'headline' => 'Promo')
      end
    end
  end
end
