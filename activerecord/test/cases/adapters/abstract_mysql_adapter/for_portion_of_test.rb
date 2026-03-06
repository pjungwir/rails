# frozen_string_literal: true

require "cases/helper"

# +FOR PORTION OF+ operates on application-time periods, which are a
# MariaDB extension (MySQL does not support them).
if ActiveRecord::Base.lease_connection.mariadb? &&
    ActiveRecord::Base.lease_connection.database_version >= "10.4.3"
  class ForPortionOfTest < ActiveRecord::AbstractMysqlTestCase
    class Room < ActiveRecord::Base
      self.table_name = "for_portion_of_rooms"
    end

    # Used for the default-bound cases: +now()+ and the maximum-timestamp upper
    # bound require datetime period columns.
    class DatetimeRoom < ActiveRecord::Base
      self.table_name = "for_portion_of_datetime_rooms"
    end

    def setup
      @connection = ActiveRecord::Base.lease_connection
      @connection.execute(<<~SQL)
        CREATE TABLE for_portion_of_rooms (
          id int,
          name varchar(255),
          valid_from date,
          valid_to date,
          PERIOD FOR valid_at(valid_from, valid_to)
        )
      SQL
      @connection.execute(<<~SQL)
        INSERT INTO for_portion_of_rooms (id, name, valid_from, valid_to)
        VALUES (1, 'original', '2018-01-01', '2022-01-01')
      SQL
      @connection.execute(<<~SQL)
        CREATE TABLE for_portion_of_datetime_rooms (
          id int,
          name varchar(255),
          valid_from datetime,
          valid_to datetime,
          PERIOD FOR valid_at(valid_from, valid_to)
        )
      SQL
      @connection.execute(<<~SQL)
        INSERT INTO for_portion_of_datetime_rooms (id, name, valid_from, valid_to)
        VALUES (1, 'original', '2018-01-01 00:00:00', '9999-12-31 23:59:59')
      SQL
      Room.reset_column_information
      DatetimeRoom.reset_column_information
    end

    def teardown
      @connection.drop_table "for_portion_of_rooms", if_exists: true
      @connection.drop_table "for_portion_of_datetime_rooms", if_exists: true
      Room.reset_column_information
      DatetimeRoom.reset_column_information
    end

    def test_update_for_portion_of_splits_the_row
      table = Arel::Table.new("for_portion_of_rooms")
      manager = Arel::UpdateManager.new(table)
      manager.set([[table[:name], Arel::Nodes.build_quoted("updated")]])
      manager.for_portion_of("valid_at", Arel::Nodes.build_quoted("2019-01-01"), Arel::Nodes.build_quoted("2020-01-01"))
      manager.where(table[:id].eq(1))

      @connection.update(manager)

      assert_equal(
        [
          ["original", "2018-01-01", "2019-01-01"],
          ["updated",  "2019-01-01", "2020-01-01"],
          ["original", "2020-01-01", "2022-01-01"],
        ],
        current_rows
      )
    end

    def test_delete_for_portion_of_removes_only_the_portion
      table = Arel::Table.new("for_portion_of_rooms")
      manager = Arel::DeleteManager.new(table)
      manager.for_portion_of("valid_at", Arel::Nodes.build_quoted("2019-01-01"), Arel::Nodes.build_quoted("2020-01-01"))
      manager.where(table[:id].eq(1))

      @connection.delete(manager)

      assert_equal(
        [
          ["original", "2018-01-01", "2019-01-01"],
          ["original", "2020-01-01", "2022-01-01"],
        ],
        current_rows
      )
    end

    # With no bounds the lower bound defaults to now() and the upper bound to
    # the maximum timestamp, so the row is split at the current time into a
    # closed past portion and a present portion running to the end of time.
    def test_update_for_portion_of_defaults_lower_to_now_and_upper_to_max
      table = Arel::Table.new("for_portion_of_datetime_rooms")
      manager = Arel::UpdateManager.new(table)
      manager.set([[table[:name], Arel::Nodes.build_quoted("current")]])
      manager.for_portion_of("valid_at")
      manager.where(table[:id].eq(1))

      @connection.update(manager)

      past, present = DatetimeRoom.order(:valid_from).to_a
      assert_equal ["original", "current"], [past.name, present.name]
      # lower defaulted to now(): the split happened at the current time
      assert_equal past.valid_to, present.valid_from
      assert_operator present.valid_from, :<=, Time.now
      # upper defaulted to the maximum timestamp
      assert_equal "9999-12-31 23:59:59", present.valid_to.strftime("%Y-%m-%d %H:%M:%S")
    end

    # Passing only the lower bound leaves the upper bound defaulting to the
    # maximum timestamp, so everything from the given instant onward is removed.
    def test_delete_for_portion_of_defaults_upper_to_max
      table = Arel::Table.new("for_portion_of_datetime_rooms")
      manager = Arel::DeleteManager.new(table)
      manager.for_portion_of("valid_at", Arel::Nodes.build_quoted("2020-01-01 00:00:00"))
      manager.where(table[:id].eq(1))

      @connection.delete(manager)

      rooms = DatetimeRoom.all.to_a
      assert_equal ["original"], rooms.map(&:name)
      # the portion from 2020 to the maximum timestamp was removed
      assert_equal "2020-01-01 00:00:00", rooms.first.valid_to.strftime("%Y-%m-%d %H:%M:%S")
    end

    private
      def current_rows
        @connection.select_rows(<<~SQL)
          SELECT name, valid_from, valid_to FROM for_portion_of_rooms ORDER BY valid_from
        SQL
      end
  end
end
