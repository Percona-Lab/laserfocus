class JiraSync
  EPIC_FIELDS  = %w[summary status priority assignee].freeze
  ISSUE_FIELDS = %w[summary status issuetype assignee priority created parent labels components].freeze

  def initialize(epic_query: LASER_FOCUS_CONFIG.board.epic_query,
                 unplanned_query: LASER_FOCUS_CONFIG.board.unplanned_query,
                 client: JiraClient.new)
    @epic_query = epic_query
    @unplanned_query = unplanned_query
    @client = client
  end

  def run!
    run = SyncRun.create!(started_at: Time.current, ok: false, fetched_count: 0)
    fetched = 0
    now = Time.current

    epics_jira = @client.search_all(@epic_query, fields: EPIC_FIELDS)
    epics_by_key = {}
    epics_jira.each do |je|
      epic = upsert_epic(je, now)
      epics_by_key[epic.jira_key] = epic
    end

    all_assigned_keys = Set.new
    if epics_by_key.any?
      keys_list = jira_key_list(epics_by_key.keys)
      child_jql = "parent in (#{keys_list})"
      children = @client.search_all(child_jql, fields: ISSUE_FIELDS, expand: "changelog")
      subtasks = []

      if children.any?
        subtask_jql = "parent in (#{jira_key_list(children.map(&:key))})"
        subtasks = @client.search_all(subtask_jql, fields: ISSUE_FIELDS, expand: "changelog")
      end

      children_by_epic = Hash.new { |h, k| h[k] = [] }
      children.each do |ji|
        parent_key = ji.fields.dig("parent", "key")
        children_by_epic[parent_key] << ji
      end
      subtasks_by_parent = Hash.new { |h, k| h[k] = [] }
      subtasks.each do |ji|
        parent_key = ji.fields.dig("parent", "key")
        subtasks_by_parent[parent_key] << ji
      end

      epics_by_key.each do |epic_key, epic|
        epic_children = children_by_epic[epic_key]
        seen_issue_keys = []
        epic_children.each do |ji|
          upsert_issue(ji, epic, now)
          seen_issue_keys << ji.key
          subtasks_by_parent[ji.key].each do |subtask|
            upsert_issue(subtask, epic, now)
            seen_issue_keys << subtask.key
          end
        end
        all_assigned_keys.merge(seen_issue_keys)
        epic.issues.active.where.not(jira_key: seen_issue_keys).update_all(removed_at: now)
      end
      fetched += children.size + subtasks.size
    end

    Epic.active.where.not(jira_key: epics_by_key.keys).update_all(removed_at: now)

    seen_orphan_keys = []
    if @unplanned_query.present?
      orphans = @client.search_all(@unplanned_query, fields: ISSUE_FIELDS, expand: "changelog")
      orphans = orphans.reject { |ji| all_assigned_keys.include?(ji.key) }
      orphans.each do |ji|
        if (clashing_epic = epics_by_key.delete(ji.key))
          clashing_epic.update!(removed_at: now)
        end
        upsert_issue(ji, nil, now)
        seen_orphan_keys << ji.key
      end
      Issue.active.orphan.where.not(jira_key: seen_orphan_keys).update_all(removed_at: now)
      fetched += orphans.size
    end

    sync_pull_requests!(all_assigned_keys.to_a + seen_orphan_keys)

    run.update!(finished_at: Time.current, ok: true, fetched_count: fetched)
    BoardSnapshot.bump!
    BoardBroadcasts.board
    Turbo::StreamsChannel.broadcast_replace_to(
      "sync_status",
      target: "kb-sync-status",
      partial: "board/stale_banner",
      locals: { last_sync: run }
    )
    run
  rescue => e
    run.update!(finished_at: Time.current, ok: false, error_message: e.message)
    Rails.logger.error("[JiraSync] #{e.class}: #{e.message}")
    run
  end

  private

  def upsert_epic(je, now)
    epic = Epic.find_or_initialize_by(jira_key: je.key)
    epic.assign_attributes(
      name: je.fields["summary"],
      jira_status: je.fields.dig("status", "name"),
      priority: priority_int(je.fields["priority"]),
      raw_fields: je.fields,
      last_seen_in_query_at: now,
      removed_at: nil
    )
    epic.save!
    epic
  end

  def upsert_issue(ji, epic, now)
    issue = Issue.find_or_initialize_by(jira_key: ji.key)
    new_status = ji.fields.dig("status", "name")

    issue.assign_attributes(
      jira_id: ji.id,
      epic: epic,
      summary: ji.fields["summary"],
      jira_status: new_status,
      issue_type: ji.fields.dig("issuetype", "name"),
      assignee_username: ji.fields.dig("assignee", "displayName") || ji.fields.dig("assignee", "name"),
      priority: priority_int(ji.fields["priority"]),
      created_at_jira: parse_time(ji.fields["created"]) || issue.created_at_jira || now,
      status_changed_at_jira: last_status_change_at(ji),
      raw_fields: ji.fields,
      last_seen_in_query_at: now,
      removed_at: nil
    )
    issue.save!
    issue
  end

  def jira_key_list(keys)
    keys.map { |k| %Q("#{k}") }.join(",")
  end

  def last_status_change_at(ji)
    histories = ji.attrs.dig("changelog", "histories") || []
    times = histories.flat_map do |h|
      next [] unless h["items"]&.any? { |it| it["field"] == "status" }
      t = parse_time(h["created"])
      t ? [ t ] : []
    end
    times.max
  end

  def priority_int(p)
    return nil if p.blank?
    Integer(p["id"]) rescue nil
  end

  def parse_time(s)
    Time.parse(s) rescue nil
  end

  def sync_pull_requests!(issue_keys)
    return if issue_keys.empty?

    id_map = Issue.where(jira_key: issue_keys).pluck(:jira_key, :jira_id)
                  .each_with_object({}) { |(k, id), h| h[k] = id if id.present? }
    return if id_map.empty?

    app_types = discover_pr_app_types(id_map.values)
    return if app_types.empty?

    id_map.each do |key, jira_id|
      raw_prs = @client.dev_status_prs(jira_id, app_types)
      prs = extract_prs(raw_prs)
      Issue.where(jira_key: key).update_all(pull_requests: prs)
    rescue => e
      Rails.logger.warn("[JiraSync] PR sync failed for #{key}: #{e.message}")
    end
  rescue => e
    Rails.logger.warn("[JiraSync] PR sync skipped: #{e.message}")
  end

  def discover_pr_app_types(jira_ids)
    jira_ids.each do |jira_id|
      types = @client.pr_app_types(jira_id)
      return types if types.any?
    end
    []
  end

  def extract_prs(raw_prs)
    raw_prs.filter_map do |pr|
      url = pr["url"].to_s
      next if url.empty?
      {
        "url"    => url,
        "title"  => (pr["name"] || pr["id"]).to_s,
        "merged" => pr["status"] == "MERGED",
        "closed" => pr["status"] == "DECLINED"
      }
    end
  end
end
