# frozen_string_literal: true

require "cases/helper"
require "support/connection_helper"

# +FOR PORTION OF+ (SQL:2011 temporal update/delete) is supported by
# PostgreSQL 19 and later.
if ActiveRecord::Base.lease_connection.database_version >= 19_00_00
  class PostgresqlForPortionOfTest < ActiveRecord::PostgreSQLTestCase
    include ConnectionHelper

    class Room < ActiveRecord::Base
      self.table_name = "postgresql_for_portion_of"
    end

    # Used for the default-bound cases: +now()+ and the open (+NULL+) upper
    # bound require a timestamp-based range.
    class TstzRoom < ActiveRecord::Base
      self.table_name = "postgresql_for_portion_of_tstz"
    end

    def setup
      @connection = ActiveRecord::Base.lease_connection
      enable_extension!("btree_gist", @connection)
      @connection.execute(<<~SQL)
        CREATE TABLE postgresql_for_portion_of (
          id integer,
          name character varying(255),
          valid_at daterange,
          PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
        )
      SQL
      @connection.execute(<<~SQL)
        INSERT INTO postgresql_for_portion_of (id, name, valid_at)
        VALUES (1, 'original', daterange('2018-01-01', '2022-01-01'))
      SQL
      @connection.execute(<<~SQL)
        CREATE TABLE postgresql_for_portion_of_tstz (
          id integer,
          name character varying(255),
          valid_at tstzrange,
          PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
        )
      SQL
      @connection.execute(<<~SQL)
        INSERT INTO postgresql_for_portion_of_tstz (id, name, valid_at)
        VALUES (1, 'original', tstzrange('2018-01-01 00:00:00+00', NULL))
      SQL
      Room.reset_column_information
      TstzRoom.reset_column_information
    end

    def teardown
      @connection.drop_table "postgresql_for_portion_of", if_exists: true
      @connection.drop_table "postgresql_for_portion_of_tstz", if_exists: true
      disable_extension!("btree_gist", @connection)
      Room.reset_column_information
      TstzRoom.reset_column_information
    end

    def test_update_for_portion_of_splits_the_row
      table = Arel::Table.new("postgresql_for_portion_of")
      manager = Arel::UpdateManager.new(table)
      manager.set([[table[:name], Arel::Nodes.build_quoted("updated")]])
      manager.for_portion_of("valid_at", Arel::Nodes.build_quoted("2019-01-01"), Arel::Nodes.build_quoted("2020-01-01"))
      manager.where(table[:id].eq(1))

      @connection.update(manager)

      assert_equal(
        [
          ["original", "[2018-01-01,2019-01-01)"],
          ["updated",  "[2019-01-01,2020-01-01)"],
          ["original", "[2020-01-01,2022-01-01)"],
        ],
        current_rows
      )
    end

    def test_delete_for_portion_of_removes_only_the_portion
      table = Arel::Table.new("postgresql_for_portion_of")
      manager = Arel::DeleteManager.new(table)
      manager.for_portion_of("valid_at", Arel::Nodes.build_quoted("2019-01-01"), Arel::Nodes.build_quoted("2020-01-01"))
      manager.where(table[:id].eq(1))

      @connection.delete(manager)

      assert_equal(
        [
          ["original", "[2018-01-01,2019-01-01)"],
          ["original", "[2020-01-01,2022-01-01)"],
        ],
        current_rows
      )
    end

    # With no bounds the lower bound defaults to now() and the upper bound to
    # NULL, so the row is split at the current time into a closed past portion
    # and an open-ended present portion.
    def test_update_for_portion_of_defaults_lower_to_now_and_upper_to_open
      table = Arel::Table.new("postgresql_for_portion_of_tstz")
      manager = Arel::UpdateManager.new(table)
      manager.set([[table[:name], Arel::Nodes.build_quoted("current")]])
      manager.for_portion_of("valid_at")
      manager.where(table[:id].eq(1))

      @connection.update(manager)

      past, present = TstzRoom.order(Arel.sql("lower(valid_at)")).to_a
      assert_equal ["original", "current"], [past.name, present.name]
      # upper defaulted to NULL: the present portion is open-ended
      assert_nil present.valid_at.end
      # lower defaulted to now(): the split happened at the current time
      assert_equal past.valid_at.end, present.valid_at.begin
      assert_not past.valid_at.cover?(Time.now)
      assert present.valid_at.cover?(Time.now)
    end

    # Passing only the lower bound leaves the upper bound defaulting to NULL, so
    # everything from the given instant onward is affected.
    def test_delete_for_portion_of_defaults_upper_to_open
      table = Arel::Table.new("postgresql_for_portion_of_tstz")
      manager = Arel::DeleteManager.new(table)
      manager.for_portion_of("valid_at", Arel::Nodes.build_quoted("2020-01-01 00:00:00+00"))
      manager.where(table[:id].eq(1))

      @connection.delete(manager)

      rooms = TstzRoom.all.to_a
      assert_equal ["original"], rooms.map(&:name)
      # only the portion before 2020 survives; it is now closed at 2020
      assert_equal Time.utc(2020, 1, 1), rooms.first.valid_at.end.utc
    end

    private
      def current_rows
        @connection.select_rows(<<~SQL)
          SELECT name, valid_at::text FROM postgresql_for_portion_of ORDER BY valid_at
        SQL
      end
  end
end
