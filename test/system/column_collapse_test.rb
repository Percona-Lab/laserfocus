require "application_system_test_case"

class ColumnCollapseTest < ApplicationSystemTestCase
  fixtures :epics, :issues, :sync_runs

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    BoardOrder.delete_all
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector "main.kb-board#board-root"
  end

  # PG-1 column: PG-10 (In Progress), PG-11 (In Review, stale), PG-12 (To Do), PG-13 (Done)

  test "collapsing a column renders the narrow strip with counts and persists" do
    fold("PG-1")

    assert_selector ".kb-col[data-epic-key='PG-1'][data-collapsed='1']"
    within ".kb-col[data-epic-key='PG-1']" do
      assert_no_selector ".kb-card"
      assert_equal %w[1 2 1], all(".kb-col-fold-count").map { |c| c.text.strip }
      assert_selector ".kb-col-fold-stale"
    end
    wait_for_collapsed %w[PG-1]
  end

  test "expanding a collapsed column restores the cards" do
    fold("PG-1")
    wait_for_collapsed %w[PG-1]
    assert_selector ".kb-col[data-epic-key='PG-1'][data-collapsed='1']"

    fold("PG-1")
    assert_selector ".kb-col[data-epic-key='PG-1']:not([data-collapsed='1']) .kb-card"
    wait_for_collapsed []
  end

  test "adjacent collapsed columns share one stack" do
    fold("PG-1")
    wait_for_collapsed %w[PG-1]
    fold("PG-2")
    wait_for_collapsed %w[PG-1 PG-2]

    assert_selector ".kb-col-stack .kb-col[data-collapsed='1']", count: 2
    assert_selector ".kb-col-stack", count: 1
  end

  test "expand_all shows collapsed columns open with a chip and still writes the stored state" do
    BoardOrder.instance.update!(collapsed_columns: %w[PG-1])
    visit "/?expand_all=1"

    assert_selector ".kb-expand-all-hint"
    assert_selector ".kb-col[data-epic-key='PG-1'] .kb-card"
    assert_selector ".kb-col[data-epic-key='PG-1'] .kb-col-collapsed-chip"
    assert_no_selector ".kb-col-stack"

    fold("PG-2")
    wait_for_collapsed %w[PG-1 PG-2]
    assert_selector ".kb-col[data-epic-key='PG-2'] .kb-col-collapsed-chip"
    assert_selector ".kb-col[data-epic-key='PG-2'] .kb-card"

    visit "/"
    assert_selector ".kb-col-stack .kb-col[data-collapsed='1']", count: 2
  end

  test "dragging an expanded column before a collapsed one saves the flat order" do
    fold("PG-1")
    wait_for_collapsed %w[PG-1]
    assert_selector ".kb-col[data-epic-key='PG-1'][data-collapsed='1']"

    drag_col("PG-2", "PG-1", side: :top)

    wait_for_saved_order %w[PG-2 PG-1]
    assert_selector ".kb-col[data-epic-key='PG-2']:not([data-collapsed='1'])"
    assert_equal %w[PG-2 PG-1], column_keys
  end

  test "another session sees the collapsed column" do
    fold("PG-1")
    wait_for_collapsed %w[PG-1]

    Capybara.using_session("second-user") do
      visit "/auth/google_oauth2/callback"
      visit "/"
      assert_selector ".kb-col[data-epic-key='PG-1'][data-collapsed='1']"
    end
  end

  private

  def fold(key)
    find(".kb-col[data-epic-key='#{key}'] .kb-col-fold-btn").click
  end

  def column_keys
    all(".kb-col").map { |c| c["data-epic-key"] }
  end

  def wait_for_collapsed(expected)
    deadline = Time.current + 5
    until BoardOrder.instance.reload.collapsed_columns.sort == expected.sort
      raise "collapse not persisted, got #{BoardOrder.instance.collapsed_columns.inspect}" if Time.current > deadline
      sleep 0.1
    end
  end

  def wait_for_saved_order(expected)
    deadline = Time.current + 5
    until BoardOrder.instance.reload.column_order == expected
      raise "order not persisted, got #{BoardOrder.instance.column_order.inspect}" if Time.current > deadline
      sleep 0.1
    end
  end

  def drag_col(from_key, to_key, side:)
    page.execute_script(<<~JS, from_key, to_key, side.to_s)
      const [fromKey, toKey, side] = arguments;
      const source = document.querySelector(`.kb-col[data-epic-key='${fromKey}'] .kb-col-head`);
      const targetCol = document.querySelector(`.kb-col[data-epic-key='${toKey}']`);
      const rect = targetCol.getBoundingClientRect();
      const clientX = side === 'left' ? rect.left + 5 : side === 'right' ? rect.right - 5 : rect.left + rect.width / 2;
      const clientY = side === 'top' ? rect.top + 5 : side === 'bottom' ? rect.bottom - 5 : rect.top + 5;
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
end
