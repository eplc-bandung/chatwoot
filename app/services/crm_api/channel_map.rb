# Maps Chatwoot's internal channel_type class names to the short, stable slugs
# the CRM integration API exposes (see docs/crm_integration_api.md).
#
# Twilio-backed WhatsApp inboxes are a special case: Channel::TwilioSms is used
# for both plain SMS and WhatsApp depending on Channel::TwilioSms#medium, so it
# cannot be mapped by class name alone (see Inbox#twilio_whatsapp?).
class CrmApi::ChannelMap
  SLUG_BY_CLASS = {
    'Channel::Whatsapp' => 'whatsapp',
    'Channel::Instagram' => 'instagram',
    'Channel::FacebookPage' => 'facebook',
    'Channel::WebWidget' => 'website',
    'Channel::Email' => 'email',
    'Channel::Sms' => 'sms',
    'Channel::Telegram' => 'telegram',
    'Channel::Line' => 'line',
    'Channel::TwitterProfile' => 'twitter',
    'Channel::Tiktok' => 'tiktok',
    'Channel::Api' => 'api'
  }.freeze

  # All slugs a CRM developer can pass to ?channel=
  SLUGS = (SLUG_BY_CLASS.values + %w[whatsapp sms]).uniq.freeze

  class << self
    # Inbox -> CRM slug
    def slug_for(inbox)
      return 'whatsapp' if inbox.twilio_whatsapp?
      return 'sms' if inbox.channel_type == 'Channel::TwilioSms'

      SLUG_BY_CLASS.fetch(inbox.channel_type, inbox.channel_type)
    end

    # CRM slugs -> inbox ids, for filtering. Resolves the Twilio/WhatsApp ambiguity
    # by inspecting Channel::TwilioSms#medium on matching inboxes.
    def inbox_ids_for_slugs(account, slugs)
      slugs = Array(slugs).map(&:to_s).map(&:downcase)
      return account.inboxes.pluck(:id) if slugs.empty?

      class_names = SLUG_BY_CLASS.select { |_klass, slug| slugs.include?(slug) }.keys
      scope = account.inboxes.where(channel_type: class_names)
      ids = scope.pluck(:id)

      ids += twilio_inbox_ids(account, slugs)
      ids.uniq
    end

    private

    def twilio_inbox_ids(account, slugs)
      wanted_media = %w[whatsapp sms] & slugs
      return [] if wanted_media.empty?

      account.inboxes.where(channel_type: 'Channel::TwilioSms')
             .includes(:channel)
             .select { |inbox| wanted_media.include?(inbox.channel.try(:medium) || 'sms') }
             .map(&:id)
    end
  end
end
