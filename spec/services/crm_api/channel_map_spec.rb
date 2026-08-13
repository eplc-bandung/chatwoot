require 'rails_helper'

RSpec.describe CrmApi::ChannelMap do
  let(:account) { create(:account) }

  def unique_phone_number
    "+1#{SecureRandom.random_number(10**10)}"
  end

  describe '.slug_for' do
    it 'maps a native WhatsApp inbox to whatsapp' do
      inbox = create(:channel_whatsapp, account: account, phone_number: unique_phone_number,
                                        validate_provider_config: false, sync_templates: false).inbox
      expect(described_class.slug_for(inbox)).to eq('whatsapp')
    end

    it 'maps a Twilio inbox in whatsapp medium to whatsapp' do
      inbox = create(:channel_twilio_sms, :whatsapp, :with_phone_number, account: account, phone_number: unique_phone_number).inbox
      expect(described_class.slug_for(inbox)).to eq('whatsapp')
    end

    it 'maps a Twilio inbox in sms medium to sms' do
      inbox = create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: unique_phone_number).inbox
      expect(described_class.slug_for(inbox)).to eq('sms')
    end

    it 'maps an Instagram inbox to instagram' do
      inbox = create(:channel_instagram, account: account).inbox
      expect(described_class.slug_for(inbox)).to eq('instagram')
    end

    it 'maps a web widget inbox to website' do
      inbox = create(:inbox, account: account)
      expect(described_class.slug_for(inbox)).to eq('website')
    end
  end

  describe '.inbox_ids_for_slugs' do
    it 'returns all account inbox ids when slugs is empty' do
      inbox = create(:inbox, account: account)
      expect(described_class.inbox_ids_for_slugs(account, [])).to contain_exactly(inbox.id)
    end

    it 'resolves the whatsapp slug to both native and Twilio-WhatsApp inboxes, excluding Twilio-SMS' do
      wa_inbox = create(:channel_whatsapp, account: account, phone_number: unique_phone_number,
                                           validate_provider_config: false, sync_templates: false).inbox
      twilio_wa_inbox = create(:channel_twilio_sms, :whatsapp, :with_phone_number, account: account, phone_number: unique_phone_number).inbox
      create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: unique_phone_number)

      expect(described_class.inbox_ids_for_slugs(account, ['whatsapp'])).to contain_exactly(wa_inbox.id, twilio_wa_inbox.id)
    end
  end
end
