# frozen_string_literal: true

module Arel # :nodoc: all
  class DeleteManager < Arel::TreeManager
    include TreeManager::StatementMethods

    def initialize(table = nil)
      super

      @ast = Nodes::DeleteStatement.new(table)
    end

    def from(relation)
      @ast.relation = relation
      self
    end

    def group(columns)
      columns.each do |column|
        column = Nodes::SqlLiteral.new(column) if String === column
        column = Nodes::SqlLiteral.new(column.to_s) if Symbol === column

        @ast.groups.push Nodes::Group.new column
      end

      self
    end

    def having(expr)
      @ast.havings << expr
      self
    end

    def comment(value)
      @ast.comment = value
      self
    end

    # Restrict the DELETE to a slice of an application-time +period+, emitting
    # a <tt>FOR PORTION OF <period> FROM <lower> TO <upper></tt> clause
    # (PostgreSQL 19+ and MariaDB). Rows overlapping the <tt>[lower, upper)</tt>
    # span are split so that only the overlapping portion is deleted.
    #
    #   delete_manager.for_portion_of(:valid_at, lower, upper)
    #
    # +lower+ and +upper+ are optional but positional: to pass +upper+ you must
    # also pass +lower+. When omitted, +lower+ defaults to the current time
    # (+now()+) and +upper+ defaults to the open end of the period (+NULL+ on
    # PostgreSQL, the maximum timestamp on MariaDB).
    def for_portion_of(period, lower = nil, upper = nil)
      @ast.for_portion_of = Nodes::ForPortionOf.new(period, lower, upper)
      self
    end
  end
end
