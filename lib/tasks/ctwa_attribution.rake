# Backfills Meta CTWA ad attribution onto conversations for messages that were
# received before Conversations::CtwaAttributionService existed.
#
# Usage:
#   bundle exec rails ctwa:backfill                # all accounts
#   bundle exec rails ctwa:backfill ACCOUNT_ID=1    # single account
#   bundle exec rails ctwa:backfill DRY_RUN=true
namespace :ctwa do
  desc 'Backfill conversations.additional_attributes.ctwa_referral from message content_attributes'
  task backfill: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', false))
    account_id = ENV.fetch('ACCOUNT_ID', nil)

    scope = Message.where(message_type: :incoming).where("content_attributes -> 'referral' IS NOT NULL").order(:id)
    scope = scope.where(account_id: account_id) if account_id.present?

    total = scope.count
    puts "Found #{total} incoming messages carrying a referral payload#{dry_run ? ' (dry run)' : ''}"

    processed = 0
    attributed = 0

    scope.includes(:conversation).find_each(batch_size: 500) do |message|
      processed += 1
      conversation = message.conversation
      next if conversation.blank?
      next if conversation.additional_attributes['ctwa_referral'].present?

      attributed += 1 if dry_run || Conversations::CtwaAttributionService.new(message).perform

      puts "  processed #{processed}/#{total}" if (processed % 1000).zero?
    end

    puts "Done. #{attributed} conversations attributed out of #{processed} messages scanned."
  end

  desc 'Report CTWA attribution coverage per account'
  task report: :environment do
    Account.find_each do |account|
      total = account.conversations.count
      attributed = account.conversations.where("additional_attributes -> 'ctwa_referral' IS NOT NULL").count
      next if attributed.zero?

      puts "Account #{account.id} (#{account.name}): #{attributed}/#{total} conversations attributed to Meta"
    end
  end
end
