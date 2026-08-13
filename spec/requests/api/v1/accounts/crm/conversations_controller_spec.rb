require 'rails_helper'

RSpec.describe 'CRM Conversations API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, phone_number: unique_phone_number,
                              validate_provider_config: false, sync_templates: false).inbox
  end

  def unique_phone_number
    "+1#{SecureRandom.random_number(10**10)}"
  end

  describe 'GET /api/v1/accounts/:account_id/crm/conversations' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/conversations"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated with a valid access token' do
      let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

      it 'returns the lead-shaped conversation payload' do
        get "/api/v1/accounts/#{account.id}/crm/conversations",
            headers: { api_access_token: admin.access_token.token },
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['data'].size).to eq(1)

        payload = body['data'].first
        expect(payload['id']).to eq(conversation.display_id)
        expect(payload['channel']).to eq('whatsapp')
        expect(payload['lead']['id']).to eq(conversation.contact_id)
        expect(payload['meta_ads']).to be_nil
        expect(body['meta']).to include('page' => 1, 'total_count' => 1)
      end

      it 'surfaces meta ad attribution when present' do
        conversation.update!(additional_attributes: { 'ctwa_referral' => { 'source' => 'meta_ads', 'ad_id' => 'ad-42', 'ctwa_clid' => 'clid-42' } })

        get "/api/v1/accounts/#{account.id}/crm/conversations",
            headers: { api_access_token: admin.access_token.token },
            as: :json

        payload = response.parsed_body['data'].first
        expect(payload['meta_ads']).to include('source' => 'meta_ads', 'ad_id' => 'ad-42', 'ctwa_clid' => 'clid-42')
      end

      it 'returns 422 for an invalid filter value' do
        get "/api/v1/accounts/#{account.id}/crm/conversations?status=bogus",
            headers: { api_access_token: admin.access_token.token },
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to match(/invalid status/)
      end
    end

    context 'when authenticated as a non-administrator agent' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:other_inbox) do
        create(:channel_whatsapp, account: account, phone_number: unique_phone_number,
                                  validate_provider_config: false, sync_templates: false).inbox
      end
      let!(:own_conversation) { create(:conversation, account: account, inbox: inbox) }

      before do
        create(:conversation, account: account, inbox: other_inbox) # other_conversation, agent must not see this
        create(:inbox_member, inbox: inbox, user: agent)
      end

      it 'only returns conversations from inboxes the agent belongs to' do
        get "/api/v1/accounts/#{account.id}/crm/conversations",
            headers: { api_access_token: agent.access_token.token },
            as: :json

        ids = response.parsed_body['data'].pluck('id')
        expect(ids).to contain_exactly(own_conversation.display_id)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/crm/conversations/:id' do
    let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

    it 'returns the conversation by display_id' do
      get "/api/v1/accounts/#{account.id}/crm/conversations/#{conversation.display_id}",
          headers: { api_access_token: admin.access_token.token },
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(conversation.display_id)
    end

    it 'returns not_found for a non-existent display_id' do
      get "/api/v1/accounts/#{account.id}/crm/conversations/999999",
          headers: { api_access_token: admin.access_token.token },
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
