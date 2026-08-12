# Copies the Meta "Click to WhatsApp" (CTWA) referral payload that arrives on an
# incoming message into the parent conversation's additional_attributes.
#
# Chatwoot stores the raw Meta referral on messages.content_attributes['referral']
# (see Whatsapp::IncomingMessageServiceHelpers and Twilio::ReferralParamsHelper).
# That is fine for chat display, but it is unusable for lead reporting because
# filtering conversations by ad would require scanning the messages table.
#
# We denormalise a normalised copy onto the conversation so that:
#   - the CRM API can filter "leads from a Meta ad" with an indexed jsonb lookup
#   - attribution survives even if the originating message is later deleted
#
# Attribution is first-touch: once a conversation has ctwa_referral we never
# overwrite it. Per-message referrals remain available on the message payload
# for anyone who needs multi-touch history.
class Conversations::CtwaAttributionService
  KEY = 'ctwa_referral'.freeze

  # Meta referral keys we carry over verbatim when present.
  PASSTHROUGH_KEYS = %w[
    source_type source_url headline body media_type image_url video_url thumbnail_url
    media_id media_content_type num_media
  ].freeze

  def initialize(message)
    @message = message
  end

  def perform
    return if referral.blank?
    return unless @message.incoming?

    conversation = @message.conversation
    return if conversation.blank?
    return if conversation.additional_attributes[KEY].present?

    updated_attributes = conversation.additional_attributes.merge(KEY => attribution)
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_columns(additional_attributes: updated_attributes)
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  def referral
    @referral ||= @message.content_attributes.presence&.with_indifferent_access&.dig(:referral)
  end

  def attribution
    payload = {
      'source' => normalised_source,
      'ad_id' => ad_id,
      'post_id' => post_id,
      'ctwa_clid' => referral[:ctwa_clid].presence,
      'welcome_message' => referral.dig(:welcome_message, :text).presence,
      'captured_at' => @message.created_at.utc.iso8601,
      'message_id' => @message.id
    }

    PASSTHROUGH_KEYS.each { |key| payload[key] = referral[key].presence }
    payload.compact
  end

  # Meta reuses `source_id` for both ads and organic posts, discriminated by
  # `source_type`. Split them so consumers never have to branch on source_type.
  def ad_id
    return nil unless source_type == 'ad'

    referral[:source_id].presence
  end

  def post_id
    return nil if source_type == 'ad'

    referral[:source_id].presence
  end

  def source_type
    referral[:source_type].to_s.downcase
  end

  def normalised_source
    source_type == 'ad' ? 'meta_ads' : 'meta_organic'
  end
end
