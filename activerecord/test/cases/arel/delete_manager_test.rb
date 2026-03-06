# frozen_string_literal: true

require_relative "helper"
require_relative "support/tree_manager_behavior"

module Arel
  class DeleteManagerTest < Arel::Spec
    include TreeManagerBehavior

    it "handles limit properly" do
      table = Table.new(:users)
      dm = Arel::DeleteManager.new
      dm.take 10
      dm.from table
      dm.key = table[:id]
      assert_match(/LIMIT 10/, dm.to_sql)
    end

    describe "from" do
      it "uses from" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        dm.from table
        _(dm.to_sql).must_be_like %{ DELETE FROM "users" }
      end

      it "chains" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        _(dm.from(table)).must_equal dm
      end
    end

    describe "where" do
      it "uses where values" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        dm.from table
        dm.where table[:id].eq(10)
        _(dm.to_sql).must_be_like %{ DELETE FROM "users" WHERE "users"."id" = 10}
      end

      it "chains" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        _(dm.where(table[:id].eq(10))).must_equal dm
      end
    end

    describe "for_portion_of" do
      it "generates a FOR PORTION OF clause" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        dm.from table
        dm.for_portion_of(:valid_at, Nodes::BindParam.new(1), Nodes::BindParam.new(2))
        _(dm.to_sql).must_be_like %{
          DELETE FROM "users" FOR PORTION OF "valid_at" FROM ? TO ?
        }
      end

      it "chains" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        _(dm.for_portion_of(:valid_at, Nodes::BindParam.new(1), Nodes::BindParam.new(2))).must_equal dm
      end

      it "generates FOR PORTION OF with WHERE" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        dm.from table
        dm.for_portion_of(:valid_at, Nodes::BindParam.new(1), Nodes::BindParam.new(2))
        dm.where Nodes::SqlLiteral.new('"users"."id" = 10')
        _(dm.to_sql).must_be_like %{
          DELETE FROM "users" FOR PORTION OF "valid_at" FROM ? TO ? WHERE "users"."id" = 10
        }
      end

      it "defaults both bounds when only the period is given" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        dm.from table
        dm.for_portion_of(:valid_at)
        _(dm.to_sql).must_be_like %{
          DELETE FROM "users" FOR PORTION OF "valid_at" FROM now() TO NULL
        }
      end

      it "defaults the upper bound when only the lower bound is given" do
        table = Table.new(:users)
        dm = Arel::DeleteManager.new
        dm.from table
        dm.for_portion_of(:valid_at, Nodes::BindParam.new(1))
        _(dm.to_sql).must_be_like %{
          DELETE FROM "users" FOR PORTION OF "valid_at" FROM ? TO NULL
        }
      end
    end

    private
      def build_manager(table = nil)
        Arel::DeleteManager.new(table)
      end
  end
end
