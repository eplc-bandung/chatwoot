require 'rails_helper'

RSpec.describe Conversations::CtwaAttributionService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def create_incoming_message(referral:, conversation: self.conversation)
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox,
                     message_type: :incoming, content_attributes: { referral: referral })
  end

  describe '#perform' do
    context 'when the referral is a Meta ad (Cloud API shape)' do
      let(:referral) do
        {
          source_id: '52558118838064',
          source_type: 'ad',
          source_url: 'https://fb.me/3TYpooaRT',
          headline: 'Diana Digital',
          body: 'washa data tu',
          media_type: 'video',
          thumbnail_url: 'https://scontent.xx.fbcdn.net/sample.jpg',
          ctwa_clid: 'AfhcQdP2E4A8wWpeb1FqUzUi',
          welcome_message: { text: 'Hi! Please let us know how we can help you.' }
        }
      end

      it 'denormalises the referral onto the conversation as meta_ads with ad_id set' do
        message = create_incoming_message(referral: referral)

        described_class.new(message).perform
        conversation.reload

        expect(conversation.additional_attributes['ctwa_referral']).to include(
          'source' => 'meta_ads',
          'ad_id' => '52558118838064',
          'ctwa_clid' => 'AfhcQdP2E4A8wWpeb1FqUzUi',
          'headline' => 'Diana Digital',
          'welcome_message' => 'Hi! Please let us know how we can help you.',
          'message_id' => message.id
        )
        expect(conversation.additional_attributes['ctwa_referral']).not_to have_key('post_id')
      end
    end

    context 'when the referral is organic (source_type post)' do
      let(:referral) { { source_id: '999999', source_type: 'post' } }

      it 'stores it as meta_organic with post_id, not ad_id' do
        create_incoming_message(referral: referral)

        conversation.reload
        attrs = conversation.additional_attributes['ctwa_referral']
        expect(attrs['source']).to eq('meta_organic')
        expect(attrs['post_id']).to eq('999999')
        expect(attrs).not_to have_key('ad_id')
      end
    end

    context 'when a conversation already has first-touch attribution' do
      it 'does not overwrite an existing ctwa_referral when a later message carries a different one' do
        create_incoming_message(referral: { source_id: 'first-ad', source_type: 'ad' })
        create_incoming_message(referral: { source_id: 'second-ad', source_type: 'ad' })

        conversation.reload
        expect(conversation.additional_attributes.dig('ctwa_referral', 'ad_id')).to eq('first-ad')
      end
    end

    context 'when the message is outgoing' do
      it 'does not attribute the conversation' do
        create(:message, account: account, conversation: conversation, inbox: conversation.inbox,
                         message_type: :outgoing, content_attributes: { referral: { source_id: 'x', source_type: 'ad' } })

        conversation.reload
        expect(conversation.additional_attributes['ctwa_referral']).to be_nil
      end
    end

    context 'when the message has no referral' do
      it 'does not touch additional_attributes' do
        create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming)

        conversation.reload
        expect(conversation.additional_attributes['ctwa_referral']).to be_nil
      end
    end

    context 'when called directly (not via the model callback)' do
      it 'is idempotent and safe to call twice' do
        message = create_incoming_message(referral: { source_id: 'ad-1', source_type: 'ad' })

        described_class.new(message).perform
        described_class.new(message).perform
        conversation.reload

        expect(conversation.additional_attributes.dig('ctwa_referral', 'ad_id')).to eq('ad-1')
      end
    end
  end
end
