require 'enumerator'

module Sequel
  class Dataset
    module Convenience
      # Returns true if no records exists in the dataset
      def empty?
        db.dataset.where(exists).get(1) == nil
      end
      
      # Returns the first record in the dataset.
      def single_record(opts = nil)
        each(opts) {|r| return r}
        nil
      end
      
      NAKED_HASH = {:naked => true}.freeze

      # Returns the first value of the first reecord in the dataset.
      # Returns nil if dataset is empty.
      def single_value(opts = nil)
        opts = opts ? NAKED_HASH.merge(opts) : NAKED_HASH
        # don't cache the columns
        each(opts) {|r| @columns = nil; return r.values.first}
        nil
      end
      
      def get(column)
        select(column).single_value
      end

      # Returns the first record in the dataset. If the num argument is specified,
      # an array is returned with the first <i>num</i> records.
      def first(*args, &block)
        if block
          return filter(&block).single_record(:limit => 1)
        end
        args = args.empty? ? 1 : (args.size == 1) ? args.first : args
        case args
        when 1
          single_record(:limit => 1)
        when Fixnum
          limit(args).all
        else
          filter(args, &block).single_record(:limit => 1)
        end
      end

      # Returns the first record matching the condition.
      def [](*conditions)
        first(*conditions)
      end

      def []=(conditions, values)
        filter(conditions).update(values)
      end

      # Returns the last records in the dataset by inverting the order. If no
      # order is given, an exception is raised. If num is not given, the last
      # record is returned. Otherwise an array is returned with the last 
      # <i>num</i> records.
      def last(*args)
        raise Error, 'No order specified' unless 
          @opts[:order] || (opts && opts[:order])

        args = args.empty? ? 1 : (args.size == 1) ? args.first : args

        case args
        when Fixnum
          l = {:limit => args}
          opts = {:order => invert_order(@opts[:order])}. \
            merge(opts ? opts.merge(l) : l)
          if args == 1
            single_record(opts)
          else
            clone(opts).all
          end
        else
          filter(args).last(1)
        end
      end
      
      # Maps column values for each record in the dataset (if a column name is
      # given), or performs the stock mapping functionality of Enumerable.
      def map(column_name = nil, &block)
        if column_name
          super() {|r| r[column_name]}
        else
          super(&block)
        end
      end

      # Returns a hash with one column used as key and another used as value.
      def to_hash(key_column, value_column)
        inject({}) do |m, r|
          m[r[key_column]] = r[value_column]
          m
        end
      end

      # Returns the minimum value for the given column.
      def min(column)
        single_value(:select => [:min[column].as(:v)])
      end

      # Returns the maximum value for the given column.
      def max(column)
        single_value(:select => [:max[column].as(:v)])
      end

      # Returns the sum for the given column.
      def sum(column)
        single_value(:select => [:sum[column].as(:v)])
      end

      # Returns the average value for the given column.
      def avg(column)
        single_value(:select => [:avg[column].as(:v)])
      end
      
      COUNT_OF_ALL_AS_COUNT = :count['*'.lit].as(:count)
      
      # Returns a dataset grouped by the given column with count by group.
      def group_and_count(*columns)
        group(*columns).select(columns + [COUNT_OF_ALL_AS_COUNT]).order(:count)
      end
      
      # Returns a Range object made from the minimum and maximum values for the
      # given column.
      def range(column)
        if r = select(:min[column].as(:v1), :max[column].as(:v2)).first
          (r[:v1]..r[:v2])
        end
      end
      
      # Returns the interval between minimum and maximum values for the given 
      # column.
      def interval(column)
        if r = select("(max(#{literal(column)}) - min(#{literal(column)})) AS v".lit).first
          r[:v]
        end
      end

      # Pretty prints the records in the dataset as plain-text table.
      def print(*cols)
        Sequel::PrettyTable.print(naked.all, cols.empty? ? columns : cols)
      end
      
      COMMA_SEPARATOR = ', '.freeze
      
      # Returns a string in CSV format containing the dataset records. By 
      # default the CSV representation includes the column titles in the
      # first line. You can turn that off by passing false as the 
      # include_column_titles argument.
      def to_csv(include_column_titles = true)
        n = naked
        cols = n.columns
        csv = ''
        csv << "#{cols.join(COMMA_SEPARATOR)}\r\n" if include_column_titles
        n.each{|r| csv << "#{cols.collect{|c| r[c]}.join(COMMA_SEPARATOR)}\r\n"}
        csv
      end
      
      # Inserts multiple records into the associated table. This method can be
      # to efficiently insert a large amounts of records into a table. Inserts
      # are automatically wrapped in a transaction.
      # 
      # This method can be called either with an array of hashes:
      # 
      #   dataset.multi_insert({:x => 1}, {:x => 2})
      #
      # Or with a columns array and an array of value arrays:
      #
      #   dataset.multi_insert([:x, :y], [[1, 2], [3, 4]])
      #
      # The method also accepts a :slice or :commit_every option that specifies
      # the number of records to insert per transaction. This is useful especially
      # when inserting a large number of records, e.g.:
      #
      #   # this will commit every 50 records
      #   dataset.multi_insert(lots_of_records, :slice => 50)
      def multi_insert(*args)
        if args.empty?
          return
        elsif args[0].is_a?(Array) && args[1].is_a?(Array)
          columns, values, opts = *args
        elsif args[0].is_a?(Array) && args[1].is_a?(Dataset)
          table = @opts[:from].first
          columns, dataset = *args
          sql = "INSERT INTO #{table} (#{literal(columns)}) VALUES (#{dataset.sql})"
          return @db.transaction {@db.execute sql}
        else
          # we assume that an array of hashes is given
          hashes, opts = *args
          return if hashes.empty?
          columns = hashes.first.keys
          # convert the hashes into arrays
          values = hashes.map {|h| columns.map {|c| h[c]}}
        end
        # make sure there's work to do
        return if columns.empty? || values.empty?
        
        slice_size = opts && (opts[:commit_every] || opts[:slice])
        
        if slice_size
          values.each_slice(slice_size) do |slice|
            statements = multi_insert_sql(columns, slice)
            @db.transaction {statements.each {|st| @db.execute(st)}}
          end
        else
          statements = multi_insert_sql(columns, values)
          @db.transaction {statements.each {|st| @db.execute(st)}}
        end
      end
      alias_method :import, :multi_insert
      
      module QueryBlockCopy #:nodoc:
        def each(*args); raise Error, "#each cannot be invoked inside a query block."; end
        def insert(*args); raise Error, "#insert cannot be invoked inside a query block."; end
        def update(*args); raise Error, "#update cannot be invoked inside a query block."; end
        def delete(*args); raise Error, "#delete cannot be invoked inside a query block."; end

        def clone(opts = nil)
          @opts.merge!(opts)
          self
        end
      end
      
      # Translates a query block into a dataset. Query blocks can be useful
      # when expressing complex SELECT statements, e.g.:
      #
      #   dataset = DB[:items].query do
      #     select :x, :y, :z
      #     where {:x > 1 && :y > 2}
      #     order_by :z.DESC
      #   end
      #
      def query(&block)
        copy = clone({})
        copy.extend(QueryBlockCopy)
        copy.instance_eval(&block)
        clone(copy.opts)
      end
      
      def create_view(name)
        @db.create_view(name, self)
      end
      
      def create_or_replace_view(name)
        @db.create_or_replace_view(name, self)
      end
      
      def table_exists?
        if @opts[:sql]
          raise Sequel::Error, "this dataset has fixed SQL"
        end
        
        if @opts[:from].size != 1
          raise Sequel::Error, "this dataset selects from multiple sources"
        end
        
        t = @opts[:from].first
        if t.is_a?(Dataset)
          raise Sequel::Error, "this dataset selects from a sub query"
        end
        
        @db.table_exists?(t.to_sym)
      end
    end
  end
end
