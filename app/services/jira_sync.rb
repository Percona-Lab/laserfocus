class JiraSync
  EPIC_FIELDS  = %w[summary status priority assignee created labels].freeze
  ISSUE_FIELDS = %w[summary status issuetype assignee priority created parent labels components description].freeze

  def initialize(epic_query: LASER_FOCUS_CONFIG.board.epic_query,
                 unplanned_query: LASER_FOCUS_CONFIG.board.unplanned_query,
                 new_unplanned_query: LASER_FOCUS_CONFIG.board.new_unplanned_query,
                 new_unplanned_days: LASER_FOCUS_CONFIG.board.new_unplanned_days,
                 status_map: LASER_FOCUS_CONFIG.board.status_map,
                 new_statuses: LASER_FOCUS_CONFIG.board.new_statuses,
                 discovery: LASER_FOCUS_CONFIG.discovery,
                 client: JiraClient.new)
    @epic_query = epic_query
    @unplanned_query = unplanned_query
    @new_unplanned_query = new_unplanned_query
    @new_unplanned_days = new_unplanned_days
    @status_map = status_map
    @new_statuses = new_statuses
    @discovery = discovery
    @client = client
  end

  def run!
    run = SyncRun.create!(started_at: Time.current, ok: false, fetched_count: 0)
    fetched = 0
    now = Time.current

    now_delivery_keys = sync_discovery!(now)

    epics_jira = @client.search_all(@epic_query, fields: EPIC_FIELDS, expand: "changelog")
    # A roadmap commitment earns a column on its own, so the team never has to
    # notice that somebody forgot the Priority label.
    epics_jira += fetch_roadmap_epics(now_delivery_keys, epics_jira.map(&:key))
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

    dropped_epics = Epic.active.where.not(jira_key: epics_by_key.keys).pluck(:id, :jira_key, :name)
    Epic.active.where.not(jira_key: epics_by_key.keys).update_all(removed_at: now)
    dropped_times = epic_removal_times(dropped_epics.map { |(_, jira_key, _)| jira_key }, now)
    record_epic_events(dropped_epics, "removed", now, times_by_key: dropped_times)

    seen_orphan_keys = []
    if @unplanned_query.present?
      orphans = @client.search_all(@unplanned_query, fields: ISSUE_FIELDS, expand: "changelog")
      orphans = orphans.reject { |ji| all_assigned_keys.include?(ji.key) }
      orphans.each do |ji|
        if (clashing_epic = epics_by_key.delete(ji.key))
          clashing_epic.update!(removed_at: now)
          occurred_at = epic_removed_at(ji) || now
          record_epic_events([ [ clashing_epic.id, clashing_epic.jira_key, clashing_epic.name ] ], "removed", now,
                              times_by_key: { clashing_epic.jira_key => occurred_at })
        end
        upsert_issue(ji, nil, now)
        seen_orphan_keys << ji.key
      end
      fetched += orphans.size
    end

    seen_provisional_keys = []
    if @new_unplanned_query.present?
      candidates = @client.search_all(@new_unplanned_query, fields: ISSUE_FIELDS, expand: "changelog")
      cutoff = now - @new_unplanned_days.to_i.days
      candidates.each do |ji|
        next if all_assigned_keys.include?(ji.key)
        next if seen_orphan_keys.include?(ji.key)

        display = @status_map[ji.fields.dig("status", "name")]
        next unless @new_statuses.include?(display)

        created = parse_time(ji.fields["created"])
        next if created.nil? || created < cutoff

        upsert_issue(ji, nil, now, provisional: true)
        seen_provisional_keys << ji.key
      end
      fetched += candidates.size
    end

    if @unplanned_query.present? || @new_unplanned_query.present?
      Issue.active.orphan
           .where.not(jira_key: seen_orphan_keys + seen_provisional_keys)
           .update_all(removed_at: now)
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

  # One-time (re-runnable) backfill for EpicEvent rows created before we
  # started deriving occurred_at from Jira's changelog — they were stamped
  # with the sync time they happened to be discovered at instead of the real
  # label/status change time. Safe to run repeatedly; only touches rows whose
  # timestamp actually changes, and skips any jira_key with more than one
  # event since we can't tell which one a single changelog lookup applies to.
  # A key deleted from Jira makes the whole `key in (...)` query fail, so a
  # failed lookup is logged and leaves every row untouched instead of raising.
  def backfill_event_times!
    jira_keys = EpicEvent.distinct.pluck(:jira_key)
    return 0 if jira_keys.empty?

    updated = 0
    results = begin
      @client.search_all("key in (#{jira_key_list(jira_keys)})", fields: EPIC_FIELDS, expand: "changelog")
    rescue => e
      Rails.logger.warn("[JiraSync] backfill changelog lookup failed: #{e.message}")
      return 0
    end
    results.each do |ji|
      events = EpicEvent.where(jira_key: ji.key).to_a
      if events.size > 1
        Rails.logger.warn("[JiraSync] backfill skipped #{ji.key}: #{events.size} events, ambiguous which to update")
        next
      end

      event = events.first
      next if event.nil?

      changed_at = event.event_type == "added" ? epic_added_at(ji) : epic_removed_at(ji)
      next if changed_at.nil? || event.occurred_at == changed_at

      event.update!(occurred_at: changed_at)
      updated += 1
    end
    updated
  end

  # One-time discovery for epics that hit a terminal status (SUCCESS, FAILURE,
  # REJECTED, "GONE BAD", ...) *before* this app ever synced them — they never
  # matched epic_query, so the normal add/remove diffing in `run!` never saw
  # them and has no baseline to log a removal against. `jql` should select
  # exactly those already-closed epics (mirror epic_query but flip the status
  # filter, e.g. `status IN (SUCCESS, FAILURE, REJECTED, "GONE BAD")`).
  # Backfills both the "added" and "removed" EpicEvent for each one found,
  # skipping any jira_key we already have a row for.
  def discover_closed_epics!(jql)
    created = 0
    results = @client.search_all(jql, fields: EPIC_FIELDS, expand: "changelog")
    results.each do |je|
      next if Epic.exists?(jira_key: je.key)

      added_at = last_field_change_at(je, %w[labels], label_direction: :added) ||
                 parse_time(je.fields["created"]) || Time.current
      removed_at = epic_removed_at(je) || Time.current

      epic = Epic.create!(
        jira_key: je.key,
        name: je.fields["summary"],
        jira_status: je.fields.dig("status", "name"),
        priority: priority_int(je.fields["priority"]) || 0,
        raw_fields: je.fields,
        last_seen_in_query_at: Time.current,
        removed_at: removed_at
      )
      EpicEvent.create!(epic: epic, jira_key: epic.jira_key, name: epic.name,
                         event_type: "added", occurred_at: added_at)
      EpicEvent.create!(epic: epic, jira_key: epic.jira_key, name: epic.name,
                         event_type: "removed", occurred_at: removed_at)
      created += 1
    end
    created
  end

  private

  # Reads the Jira Product Discovery roadmap and returns the delivery ticket
  # keys of everything sitting in "Now". A failure here must not take the board
  # sync with it, so it degrades to an empty list.
  def sync_discovery!(now)
    return [] if @discovery.nil? || @discovery.queries.empty?

    seen = []
    @discovery.queries.each do |horizon, jql|
      ideas = @client.search_all(jql, fields: @discovery.issue_fields)
      # Jira hands back an empty result rather than an error for a project the
      # credential cannot browse, so a configured query returning nothing is
      # worth saying out loud -- it usually means the API token cannot see the
      # discovery project, not that the roadmap is empty.
      if ideas.empty?
        Rails.logger.warn("[JiraSync] discovery '#{horizon}' matched no ideas. " \
                          "Check the API token can browse the project: #{jql}")
      end
      ideas.each { |ji| seen << upsert_idea(ji, horizon, now).jira_key }
    end
    DiscoveryIdea.active.where.not(jira_key: seen).update_all(removed_at: now)

    DiscoveryIdea.now.joins(:idea_deliveries).pluck("idea_deliveries.jira_key").uniq
  rescue => e
    Rails.logger.warn("[JiraSync] discovery sync failed: #{e.class}: #{e.message}")
    []
  end

  def upsert_idea(ji, horizon, now)
    idea = DiscoveryIdea.find_or_initialize_by(jira_key: ji.key)
    idea.assign_attributes(
      summary: ji.fields["summary"].to_s,
      horizon: horizon,
      incubator_status: select_field_value(ji.fields[@discovery.incubator_field]),
      rank: ji.fields[@discovery.rank_field].presence,
      raw_fields: ji.fields,
      last_seen_in_query_at: now,
      removed_at: nil
    )
    idea.save!
    sync_idea_deliveries!(idea, ji)
    idea
  end

  # JPD's delivery tickets ride on ordinary issue links of one dedicated type.
  # The idea is the outward side, so the ticket arrives as inwardIssue.
  def sync_idea_deliveries!(idea, ji)
    seen = []
    Array(ji.fields["issuelinks"]).each do |link|
      next unless link.dig("type", "id").to_s == @discovery.delivery_link_type_id

      target = link["inwardIssue"] || link["outwardIssue"]
      key = target && target["key"]
      next if key.blank?

      delivery = idea.idea_deliveries.find_or_initialize_by(jira_key: key)
      delivery.issue_type = target.dig("fields", "issuetype", "name")
      delivery.save!
      seen << key
    end
    idea.idea_deliveries.where.not(jira_key: seen).destroy_all
  end

  def select_field_value(raw)
    return nil if raw.blank?
    raw.is_a?(Hash) ? raw["value"] : raw.to_s
  end

  # Epics behind a "Now" idea that epic_query did not already return.
  def fetch_roadmap_epics(delivery_keys, already_fetched)
    missing = delivery_keys - already_fetched
    return [] if missing.empty?

    @client.search_all(
      "key in (#{jira_key_list(missing)}) AND issuetype = Epic AND statusCategory != Done",
      fields: EPIC_FIELDS, expand: "changelog"
    )
  rescue => e
    Rails.logger.warn("[JiraSync] roadmap epic fetch failed: #{e.class}: #{e.message}")
    []
  end

  def upsert_epic(je, now)
    epic = Epic.find_or_initialize_by(jira_key: je.key)
    was_new = epic.new_record?
    was_removed = epic.removed_at.present?

    epic.assign_attributes(
      name: je.fields["summary"],
      jira_status: je.fields.dig("status", "name"),
      priority: priority_int(je.fields["priority"]) || 0,
      raw_fields: je.fields,
      last_seen_in_query_at: now,
      removed_at: nil
    )
    epic.save!

    if was_new || was_removed
      floor = EpicEvent.where(jira_key: epic.jira_key).maximum(:occurred_at)
      EpicEvent.create!(
        epic: epic,
        jira_key: epic.jira_key,
        name: epic.name,
        event_type: "added",
        occurred_at: epic_added_at(je, floor: floor) || now
      )
      collapse_by_default(epic)
    end

    epic
  end

  # Epics entering the query in a "new" status start collapsed on the board.
  # Only applied when the epic enters, later status changes leave the stored
  # setting alone.
  def collapse_by_default(epic)
    return unless @new_statuses.include?(@status_map[epic.jira_status])

    order = BoardOrder.instance
    return if order.collapsed_columns.include?(epic.jira_key)

    order.update!(collapsed_columns: order.collapsed_columns + [ epic.jira_key ])
  rescue => e
    Rails.logger.warn("[JiraSync] collapse default failed for #{epic.jira_key}: #{e.message}")
  end

  def record_epic_events(epics, event_type, now, times_by_key: {})
    return if epics.empty?

    EpicEvent.insert_all(
      epics.map do |id, jira_key, name|
        { epic_id: id, jira_key: jira_key, name: name, event_type: event_type,
          occurred_at: times_by_key.fetch(jira_key, now), created_at: now, updated_at: now }
      end
    )
  end

  # Looks up the current changelog for epics that just dropped out of the
  # epic_query result set (e.g. lost the Priority label, or hit a terminal
  # status) so the "removed" event can be timestamped at the real Jira field
  # change instead of "whenever this sync happened to run".
  def epic_removal_times(jira_keys, now)
    return {} if jira_keys.empty?

    results = @client.search_all("key in (#{jira_key_list(jira_keys)})", fields: EPIC_FIELDS, expand: "changelog")
    results.each_with_object({}) do |ji, times|
      times[ji.key] = epic_removed_at(ji) || now
    end
  rescue => e
    Rails.logger.warn("[JiraSync] epic removal time lookup failed: #{e.message}")
    {}
  end

  def upsert_issue(ji, epic, now, provisional: false)
    issue = Issue.find_or_initialize_by(jira_key: ji.key)
    new_status = ji.fields.dig("status", "name")

    issue.assign_attributes(
      jira_id: ji.id,
      epic: epic,
      provisional: provisional,
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
    last_field_change_at(ji, %w[status])
  end

  # Most recent changelog entry touching any of `fields`. For "labels" we only
  # count entries where the "Priority" label actually changed hands in the
  # given direction (:added / :removed, nil for either), so an unrelated label
  # edit on the same epic doesn't get credited as an add/remove trigger.
  def last_field_change_at(ji, fields, label_direction: nil)
    histories = ji.attrs.dig("changelog", "histories") || []
    times = histories.flat_map do |h|
      relevant = (h["items"] || []).any? { |it| relevant_change?(it, fields, label_direction) }
      next [] unless relevant
      t = parse_time(h["created"])
      t ? [ t ] : []
    end
    times.max
  end

  def relevant_change?(item, fields, label_direction)
    return false unless fields.include?(item["field"])
    return true unless item["field"] == "labels"

    had = item["fromString"].to_s.include?("Priority")
    has = item["toString"].to_s.include?("Priority")
    case label_direction
    when :added   then has && !had
    when :removed then had && !has
    else had || has
    end
  end

  # When an epic entered the query. The Priority label being added is the
  # entering signal on this board, so it wins over status changes; the status
  # fallback covers epics that re-enter by being reopened. `floor` drops
  # candidates at or before the epic's previous event, so a stale label add
  # can't backdate a re-add to before its own removal.
  def epic_added_at(je, floor: nil)
    candidates = [
      last_field_change_at(je, %w[labels], label_direction: :added),
      last_status_change_at(je)
    ].compact
    candidates.reject! { |t| t <= floor } if floor
    candidates.first
  end

  # When an epic left the query: the Priority label being removed or a status
  # transition (to a terminal state), whichever happened last.
  def epic_removed_at(ji)
    [
      last_field_change_at(ji, %w[labels], label_direction: :removed),
      last_status_change_at(ji)
    ].compact.max
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
