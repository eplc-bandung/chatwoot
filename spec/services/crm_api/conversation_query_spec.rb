require 'rails_helper'

RSpec.describe CrmApi::ConversationQuery do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:wa_inbox) do
    create(:channel_whatsapp, account: account, phone_number: "+1#{SecureRandom.random_number(10**10)}",
                              validate_provider_config: false, sync_templates: false).inbox
  end

  def query(user: admin, **filters)
    described_class.new(account: account, user: user, params: filters.with_indifferent_access).conversations
  end

  describe 'status filter' do
    let!(:open_conversation) { create(:conversation, account: account, inbox: wa_inbox, status: :open) }
    let!(:pending_conversation) { create(:conversation, account: account, inbox: wa_inbox, status: :pending) }

    it 'filters by a single status' do
      expect(query(status: 'open').to_a).to contain_exactly(open_conversation)
    end

    it 'accepts a comma-separated list of statuses' do
      expect(query(status: 'open,pending').to_a).to contain_exactly(open_conversation, pending_conversation)
    end

    it 'accepts array-style status params' do
      expect(query(status: %w[open pending]).to_a).to contain_exactly(open_conversation, pending_conversation)
    end

    it 'raises CrmApi::InvalidFilterError for an unknown status' do
      expect { query(status: 'bogus') }.to raise_error(CrmApi::InvalidFilterError, /invalid status/)
    end
  end

  describe 'channel filter' do
    let(:ig_inbox) { create(:channel_instagram, account: account).inbox }
    let(:twilio_whatsapp_inbox) do
      create(:channel_twilio_sms, :whatsapp, :with_phone_number, account: account,
                                                                 phone_number: "+1#{SecureRandom.random_number(10**10)}").inbox
    end
    let(:twilio_sms_inbox) do
      create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: "+1#{SecureRandom.random_number(10**10)}").inbox
    end

    let!(:wa_conversation) { create(:conversation, account: account, inbox: wa_inbox) }
    let!(:ig_conversation) { create(:conversation, account: account, inbox: ig_inbox) }
    let!(:twilio_wa_conversation) { create(:conversation, account: account, inbox: twilio_whatsapp_inbox) }
    let!(:twilio_sms_conversation) { create(:conversation, account: account, inbox: twilio_sms_inbox) }

    it 'maps the whatsapp slug to both native and Twilio-WhatsApp inboxes' do
      expect(query(channel: 'whatsapp').to_a).to contain_exactly(wa_conversation, twilio_wa_conversation)
    end

    it 'maps the sms slug to Twilio-SMS inboxes only' do
      expect(query(channel: 'sms').to_a).to contain_exactly(twilio_sms_conversation)
    end

    it 'filters by instagram' do
      expect(query(channel: 'instagram').to_a).to contain_exactly(ig_conversation)
    end

    it 'raises CrmApi::InvalidFilterError for an unknown channel slug' do
      expect { query(channel: 'carrier_pigeon') }.to raise_error(CrmApi::InvalidFilterError, /invalid channel/)
    end
  end

  describe 'labels filter' do
    let!(:hot_conversation) { create(:conversation, account: account, inbox: wa_inbox) }

    before do
      hot_conversation.update!(label_list: ['hot'])
      create(:conversation, account: account, inbox: wa_inbox) # cold_conversation, should not match
    end

    it 'filters conversations tagged with any of the given labels' do
      expect(query(labels: 'hot').to_a).to contain_exactly(hot_conversation)
    end
  end

  describe 'assignee filter' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:assigned_conversation) { create(:conversation, account: account, inbox: wa_inbox, assignee: agent) }
    let!(:unassigned_conversation) { create(:conversation, account: account, inbox: wa_inbox) }

    it 'filters by assignee_id' do
      expect(query(assignee_id: agent.id.to_s).to_a).to contain_exactly(assigned_conversation)
    end

    it 'filters unassigned conversations' do
      expect(query(unassigned: 'true').to_a).to contain_exactly(unassigned_conversation)
    end
  end

  describe 'priority filter' do
    let!(:high) { create(:conversation, account: account, inbox: wa_inbox, priority: :high) }
    let!(:low) { create(:conversation, account: account, inbox: wa_inbox, priority: :low) }

    it 'accepts a comma-separated list' do
      expect(query(priority: 'high,low').to_a).to contain_exactly(high, low)
    end

    it 'raises CrmApi::InvalidFilterError for an unknown priority' do
      expect { query(priority: 'critical') }.to raise_error(CrmApi::InvalidFilterError, /invalid priority/)
    end
  end

  describe 'meta ad attribution filters (source, ad_id, ctwa_clid)' do
    let!(:ad_conversation) do
      create(:conversation, account: account, inbox: wa_inbox,
                            additional_attributes: { 'ctwa_referral' => { 'source' => 'meta_ads', 'ad_id' => 'ad-1', 'ctwa_clid' => 'clid-1' } })
    end
    let!(:plain_conversation) { create(:conversation, account: account, inbox: wa_inbox) }

    before do
      # organic_meta_conversation: should never match source=meta_ads / ad_id / ctwa_clid filters
      create(:conversation, account: account, inbox: wa_inbox, additional_attributes: { 'ctwa_referral' => { 'source' => 'meta_organic' } })
    end

    it 'filters by source=meta_ads' do
      expect(query(source: 'meta_ads').to_a).to contain_exactly(ad_conversation)
    end

    it 'filters by source=organic (no ctwa_referral at all)' do
      expect(query(source: 'organic').to_a).to contain_exactly(plain_conversation)
    end

    it 'filters by ad_id' do
      expect(query(ad_id: 'ad-1').to_a).to contain_exactly(ad_conversation)
    end

    it 'filters by ctwa_clid' do
      expect(query(ctwa_clid: 'clid-1').to_a).to contain_exactly(ad_conversation)
    end

    it 'raises CrmApi::InvalidFilterError for an unknown source' do
      expect { query(source: 'tiktok_ads') }.to raise_error(CrmApi::InvalidFilterError, /invalid source/)
    end
  end

  describe 'date filters' do
    let!(:old_conversation) { create(:conversation, account: account, inbox: wa_inbox, created_at: 10.days.ago) }
    let!(:new_conversation) { create(:conversation, account: account, inbox: wa_inbox, created_at: 1.day.ago) }

    it 'filters by created_after' do
      expect(query(created_after: 5.days.ago.iso8601).to_a).to contain_exactly(new_conversation)
    end

    it 'filters by created_before' do
      expect(query(created_before: 5.days.ago.iso8601).to_a).to contain_exactly(old_conversation)
    end

    it 'filters by updated_since using last_activity_at' do
      new_conversation.update_columns(last_activity_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      old_conversation.update_columns(last_activity_at: 30.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(query(updated_since: 1.day.ago.iso8601).to_a).to contain_exactly(new_conversation)
    end

    it 'raises CrmApi::InvalidFilterError for an unparsable date' do
      expect { query(created_after: 'not-a-date') }.to raise_error(CrmApi::InvalidFilterError, /invalid created_after/)
    end
  end

  describe 'search (q)' do
    let!(:conversation) do
      create(:conversation, account: account, inbox: wa_inbox, contact: create(:contact, account: account, name: 'Budi Santoso'))
    end

    before { create(:conversation, account: account, inbox: wa_inbox, contact: create(:contact, account: account, name: 'Ani Wijaya')) }

    it 'matches by contact name, case-insensitively' do
      expect(query(q: 'budi').to_a).to contain_exactly(conversation)
    end
  end

  describe 'sorting' do
    let!(:first) { create(:conversation, account: account, inbox: wa_inbox, created_at: 3.days.ago) }
    let!(:second) { create(:conversation, account: account, inbox: wa_inbox, created_at: 1.day.ago) }

    it 'defaults to last_activity_at descending' do
      first.update_columns(last_activity_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
      second.update_columns(last_activity_at: 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(query.to_a.first).to eq(first)
    end

    it 'sorts ascending by created_at when requested' do
      expect(query(sort: 'created_at').to_a.first).to eq(first)
    end

    it 'raises CrmApi::InvalidFilterError for an unknown sort column' do
      expect { query(sort: 'contact_name') }.to raise_error(CrmApi::InvalidFilterError, /invalid sort/)
    end
  end

  describe 'pagination' do
    before { create_list(:conversation, 3, account: account, inbox: wa_inbox) }

    it 'defaults to 25 per page' do
      expect(query.limit_value).to eq(25)
    end

    it 'respects a valid per_page' do
      result = query(per_page: '2')
      expect(result.limit_value).to eq(2)
      expect(result.total_pages).to eq(2)
    end

    it 'clamps per_page to the maximum of 100' do
      expect(query(per_page: '9999').limit_value).to eq(100)
    end
  end

  describe 'permission scoping' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:other_inbox) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
    let!(:accessible_conversation) { create(:conversation, account: account, inbox: wa_inbox) }
    let!(:inaccessible_conversation) { create(:conversation, account: account, inbox: other_inbox) }

    before { create(:inbox_member, inbox: wa_inbox, user: agent) }

    it "restricts a non-administrator to their own inboxes' conversations" do
      expect(query(user: agent).to_a).to contain_exactly(accessible_conversation)
    end

    it 'lets an administrator see every conversation' do
      expect(query(user: admin).to_a).to contain_exactly(accessible_conversation, inaccessible_conversation)
    end
  end
end
