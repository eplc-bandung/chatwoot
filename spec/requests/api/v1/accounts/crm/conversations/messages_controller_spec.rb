require 'rails_helper'

RSpec.describe 'CRM Conversation Messages API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, phone_number: "+1#{SecureRandom.random_number(10**10)}",
                              validate_provider_config: false, sync_templates: false).inbox
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe 'GET /api/v1/accounts/:account_id/crm/conversations/:conversation_id/messages' do
    it 'returns unauthorized when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/crm/conversations/#{conversation.display_id}/messages"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the transcript newest first, including the raw referral payload' do
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'first',
                       created_at: 1.minute.ago)
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'second',
                       content_attributes: { referral: { source_id: 'ad-9', source_type: 'ad' } })

      get "/api/v1/accounts/#{account.id}/crm/conversations/#{conversation.display_id}/messages",
          headers: { api_access_token: admin.access_token.token },
          as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['data'].size).to eq(2)
      expect(body['data'].first['content']).to eq('second')
      expect(body['data'].first['content_attributes']['referral']).to include('source_id' => 'ad-9')
      expect(body['meta']).to include('total_count' => 2)
    end

    it 'returns not_found for a conversation the caller cannot access' do
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      other_conversation = create(:conversation, account: other_account, inbox: other_inbox)

      get "/api/v1/accounts/#{account.id}/crm/conversations/#{other_conversation.display_id}/messages",
          headers: { api_access_token: admin.access_token.token },
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
