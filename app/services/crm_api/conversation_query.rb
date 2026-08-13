# Builds the conversation relation served by the CRM integration API
# (Api::V1::Accounts::Crm::ConversationsController). Reuses the same
# permission scoping, sort helpers and tagging lookups as the rest of the
# app rather than reinventing them:
#   - Conversations::PermissionFilterService for visibility
#   - SortHandler (via ActiveRecord `reorder`) for ordering
#   - acts-as-taggable-on's `tagged_with` for label filtering
#
# Every filter is optional and AND-ed together. Malformed input raises
# CrmApi::InvalidFilterError, which the controller turns into a 422.
class CrmApi::ConversationQuery
  VALID_SOURCES = %w[meta_ads meta_organic organic].freeze
  VALID_SORT_COLUMNS = %w[last_activity_at created_at].freeze
  CTWA_REFERRAL_SQL = "(additional_attributes -> 'ctwa_referral')".freeze
  CTWA_SOURCE_SQL = "(additional_attributes -> 'ctwa_referral' ->> 'source')".freeze
  CTWA_AD_ID_SQL = "(additional_attributes -> 'ctwa_referral' ->> 'ad_id')".freeze
  CTWA_CLID_SQL = "(additional_attributes -> 'ctwa_referral' ->> 'ctwa_clid')".freeze

  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params
  end

  # Returns a Kaminari-paginated ActiveRecord::Relation. Callers can use
  # #total_count, #total_pages, #current_page, #limit_value directly on it.
  def conversations
    filtered_scope
      .reorder(sort_clause)
      .page(CrmApi::PaginationParams.page(params))
      .per(CrmApi::PaginationParams.per_page(params))
  end

  private

  attr_reader :account, :user, :params

  def filtered_scope
    @filtered_scope ||= [
      :filter_by_status, :filter_by_inbox, :filter_by_channel, :filter_by_labels,
      :filter_by_assignee, :filter_by_team, :filter_by_priority, :filter_by_source,
      :filter_by_ad_id, :filter_by_ctwa_clid, :filter_by_created_range,
      :filter_by_updated_since, :filter_by_search
    ].reduce(base_scope) { |scope, method_name| send(method_name, scope) }
  end

  def base_scope
    scope = account.conversations.includes(
      :taggings,
      :inbox,
      { assignee: { avatar_attachment: [:blob] } },
      { contact: { avatar_attachment: [:blob] } },
      :team,
      :contact_inbox
    )

    Conversations::PermissionFilterService.new(scope, user, account).perform
  end

  def filter_by_status(scope)
    statuses = list_param(:status)
    return scope if statuses.empty?

    validate_inclusion!(statuses, Conversation.statuses.keys, :status)
    scope.where(status: statuses)
  end

  def filter_by_inbox(scope)
    ids = integer_list_param(:inbox_id)
    return scope if ids.empty?

    scope.where(inbox_id: ids)
  end

  def filter_by_channel(scope)
    slugs = list_param(:channel).map(&:downcase)
    return scope if slugs.empty?

    validate_inclusion!(slugs, CrmApi::ChannelMap::SLUGS, :channel)
    scope.where(inbox_id: CrmApi::ChannelMap.inbox_ids_for_slugs(account, slugs))
  end

  def filter_by_labels(scope)
    labels = list_param(:labels)
    return scope if labels.empty?

    scope.tagged_with(labels, any: true)
  end

  def filter_by_assignee(scope)
    return scope.unassigned if truthy?(params[:unassigned])

    ids = integer_list_param(:assignee_id)
    return scope if ids.empty?

    scope.where(assignee_id: ids)
  end

  def filter_by_team(scope)
    ids = integer_list_param(:team_id)
    return scope if ids.empty?

    scope.where(team_id: ids)
  end

  def filter_by_priority(scope)
    priorities = list_param(:priority)
    return scope if priorities.empty?

    validate_inclusion!(priorities, Conversation.priorities.keys, :priority)
    scope.where(priority: priorities)
  end

  def filter_by_source(scope)
    source = params[:source].presence
    return scope if source.blank?

    validate_inclusion!([source], VALID_SOURCES, :source)
    return scope.where("#{CTWA_REFERRAL_SQL} IS NULL") if source == 'organic'

    scope.where("#{CTWA_SOURCE_SQL} = ?", source)
  end

  def filter_by_ad_id(scope)
    ad_id = params[:ad_id].presence
    return scope if ad_id.blank?

    scope.where("#{CTWA_AD_ID_SQL} = ?", ad_id)
  end

  def filter_by_ctwa_clid(scope)
    clid = params[:ctwa_clid].presence
    return scope if clid.blank?

    scope.where("#{CTWA_CLID_SQL} = ?", clid)
  end

  def filter_by_created_range(scope)
    scope = scope.where('conversations.created_at >= ?', parse_time(params[:created_after], :created_after)) if params[:created_after].present?
    scope = scope.where('conversations.created_at <= ?', parse_time(params[:created_before], :created_before)) if params[:created_before].present?
    scope
  end

  def filter_by_updated_since(scope)
    return scope if params[:updated_since].blank?

    scope.where('conversations.last_activity_at >= ?', parse_time(params[:updated_since], :updated_since))
  end

  def filter_by_search(scope)
    q = params[:q].presence
    return scope if q.blank?

    scope.joins(:contact).where(
      'contacts.name ILIKE :q OR contacts.phone_number ILIKE :q OR contacts.email ILIKE :q', q: "%#{q}%"
    )
  end

  def sort_clause
    raw = params[:sort].presence || '-last_activity_at'
    direction = raw.start_with?('-') ? :desc : :asc
    column = raw.delete_prefix('-')

    validate_inclusion!([column], VALID_SORT_COLUMNS, :sort)
    { column => direction }
  end

  def list_param(key)
    value = params[key]
    return [] if value.blank?
    return value.map(&:to_s) if value.is_a?(Array)

    value.to_s.split(',').map(&:strip).reject(&:blank?)
  end

  def integer_list_param(key)
    list_param(key).map { |value| parse_integer(value, key) }
  end

  def parse_integer(value, field)
    Integer(value)
  rescue ArgumentError, TypeError
    raise CrmApi::InvalidFilterError, "invalid #{field}: #{value}"
  end

  def parse_time(value, field)
    parsed = Time.zone.parse(value.to_s)
    raise CrmApi::InvalidFilterError, "invalid #{field}: #{value}" if parsed.nil?

    parsed
  rescue ArgumentError, TypeError
    raise CrmApi::InvalidFilterError, "invalid #{field}: #{value}"
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def validate_inclusion!(values, allowed, field)
    invalid = values - allowed
    return if invalid.empty?

    raise CrmApi::InvalidFilterError, "invalid #{field}: #{invalid.join(', ')}"
  end
end
