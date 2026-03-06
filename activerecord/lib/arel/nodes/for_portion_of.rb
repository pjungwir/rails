# frozen_string_literal: true

module Arel # :nodoc: all
  module Nodes
    class ForPortionOf < Arel::Nodes::Node
      attr_accessor :period, :lower, :upper

      # +lower+ and +upper+ are optional. When either is +nil+ the visitor
      # substitutes an adapter-specific default: the lower bound defaults to
      # the current time (+now()+), and the upper bound defaults to the end of
      # the period's range (+NULL+ on PostgreSQL, the maximum timestamp on
      # MariaDB).
      def initialize(period, lower = nil, upper = nil)
        super()
        @period = period
        @lower = lower
        @upper = upper
      end

      def hash
        [@period, @lower, @upper].hash
      end

      def eql?(other)
        self.class == other.class &&
          self.period == other.period &&
          self.lower == other.lower &&
          self.upper == other.upper
      end
      alias :== :eql?
    end
  end
end
