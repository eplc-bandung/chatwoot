class AddCtwaAttributionIndexesToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # Supports "which conversations came from a Meta ad / this specific ad" lookups
    # used by the CRM integration API (see CrmApi::ConversationQuery).
    add_index :conversations,
              "(additional_attributes -> 'ctwa_referral' ->> 'ad_id')",
              name: 'index_conversations_on_ctwa_ad_id',
              where: "(additional_attributes -> 'ctwa_referral') IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :conversations,
              "(additional_attributes -> 'ctwa_referral' ->> 'source')",
              name: 'index_conversations_on_ctwa_source',
              where: "(additional_attributes -> 'ctwa_referral') IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true

    # Incremental sync (updated_since cursor + default sort) for the CRM API.
    add_index :conversations,
              [:account_id, :last_activity_at],
              name: 'index_conversations_on_account_id_and_last_activity_at',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :conversations, name: 'index_conversations_on_ctwa_ad_id', algorithm: :concurrently, if_exists: true
    remove_index :conversations, name: 'index_conversations_on_ctwa_source', algorithm: :concurrently, if_exists: true
    remove_index :conversations, name: 'index_conversations_on_account_id_and_last_activity_at', algorithm: :concurrently,
                                 if_exists: true
  end
end
