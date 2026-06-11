require "application_system_test_case"

class ColumnReorderTest < ApplicationSystemTestCase
  fixtures :epics, :issues, :sync_runs

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector "main.kb-board#board-root"
  end

  test "dragging a column header reorders columns" do
    assert_equal %w[PG-1 PG-2], column_keys

    drag_col("PG-2", "PG-1", side: :left)

    assert_selector ".kb-col:first-child[data-epic-key='PG-2']"
    assert_equal %w[PG-2 PG-1], column_keys
  end

  test "column order is restored from localStorage after page reload" do
    drag_col("PG-2", "PG-1", side: :left)
    assert_selector ".kb-col:first-child[data-epic-key='PG-2']"

    visit "/"

    assert_selector ".kb-col:first-child[data-epic-key='PG-2']"
    assert_equal %w[PG-2 PG-1], column_keys
  end

  test "column order is preserved after a live broadcast" do
    drag_col("PG-2", "PG-1", side: :left)
    assert_selector ".kb-col:first-child[data-epic-key='PG-2']"

    broadcast_board

    assert_selector ".kb-col:first-child[data-epic-key='PG-2']"
    assert_equal %w[PG-2 PG-1], column_keys
  end

  private

  def column_keys
    all(".kb-col").map { |c| c["data-epic-key"] }
  end

  def drag_col(from_key, to_key, side:)
    # Capybara 3.40's drag_to drops at the target's center, which doesn't
    # satisfy the controller's strict `clientX < rect.left + width/2` check
    # for "insert before". Dispatch HTML5 drag events directly so we can
    # pick a clientX clearly inside the left or right half of the target column.
    page.execute_script(<<~JS, from_key, to_key, side.to_s)
      const [fromKey, toKey, side] = arguments;
      const source = document.querySelector(`.kb-col[data-epic-key='${fromKey}'] .kb-col-head`);
      const targetCol = document.querySelector(`.kb-col[data-epic-key='${toKey}']`);
      const rect = targetCol.getBoundingClientRect();
      const clientX = side === 'left' ? rect.left + 5 : rect.right - 5;
      const clientY = rect.top + 5;
      const dt = new DataTransfer();
      const fire = (el, type, extra = {}) => {
        const ev = new DragEvent(type, Object.assign(
          { bubbles: true, cancelable: true, dataTransfer: dt, clientX, clientY },
          extra
        ));
        el.dispatchEvent(ev);
      };
      fire(source, 'dragstart');
      fire(targetCol, 'dragenter');
      fire(targetCol, 'dragover');
      fire(targetCol, 'drop');
      fire(source, 'dragend');
    JS
  end

  def broadcast_board
    Turbo::StreamsChannel.broadcast_render_to(
      "board",
      partial: "board/board_morph",
      locals: { presenter: build_presenter, last_sync: SyncRun.ok.most_recent.first }
    )
  end

  def build_presenter
    BoardPresenter.new(
      epics: Epic.active.ordered.includes(:issues),
      orphan_issues: Issue.active.orphan,
      status_map: LASER_FOCUS_CONFIG.board.status_map,
      new_statuses: LASER_FOCUS_CONFIG.board.new_statuses,
      done_statuses: LASER_FOCUS_CONFIG.board.done_statuses,
      staleness: StalenessCalculator.new(
        now: Time.current,
        somewhat_days: LASER_FOCUS_CONFIG.board.staleness.somewhat_days,
        really_days: LASER_FOCUS_CONFIG.board.staleness.really_days,
        ignore_for_new: LASER_FOCUS_CONFIG.board.ignore_staleness_for_new_issues,
        new_display_statuses: LASER_FOCUS_CONFIG.board.new_statuses,
        done_display_statuses: LASER_FOCUS_CONFIG.board.done_statuses
      )
    )
  end
end
