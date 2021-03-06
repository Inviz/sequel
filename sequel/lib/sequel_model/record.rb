module Sequel
  class Model
    attr_reader :values
    attr_reader :changed_columns
    
    # Returns value of attribute.
    def [](column)
      @values[column]
    end
    # Sets value of attribute and marks the column as changed.
    def []=(column, value)
      # If it is new, it doesn't have a value yet, so we should
      # definitely set the new value.
      # If the column isn't in @values, we can't assume it is
      # NULL in the database, so assume it has changed.
      if new? || !@values.include?(column) || value != @values[column]
        @changed_columns << column unless @changed_columns.include?(column)
        @values[column] = value
      end
    end

    # Enumerates through all attributes.
    #
    # === Example:
    #   Ticket.find(7).each { |k, v| puts "#{k} => #{v}" }
    def each(&block)
      @values.each(&block)
    end
    # Returns attribute names.
    def keys
      @values.keys
    end

    # Returns value for <tt>:id</tt> attribute.
    def id
      @values[:id]
    end

    # Compares model instances by values.
    def ==(obj)
      (obj.class == model) && (obj.values == @values)
    end
    alias_method :eql?, :"=="

    # If pk is not nil, true only if the objects have the same class and pk.
    # If pk is nil, false.
    def ===(obj)
      pk.nil? ? false : (obj.class == model) && (obj.pk == pk)
    end

    # Unique for objects with the same class and pk (if pk is not nil), or
    # the same class and values (if pk is nil).
    def hash
      [model, pk.nil? ? @values.sort_by{|k,v| k.to_s} : pk].hash
    end

    # Returns key for primary key.
    def self.primary_key
      :id
    end
    
    # Returns primary key attribute hash.
    def self.primary_key_hash(value)
      {:id => value}
    end
    
    # Sets primary key, regular and composite are possible.
    #
    # == Example:
    #   class Tagging < Sequel::Model
    #     # composite key
    #     set_primary_key :taggable_id, :tag_id
    #   end
    #
    #   class Person < Sequel::Model
    #     # regular key
    #     set_primary_key :person_id
    #   end
    #
    # <i>You can even set it to nil!</i>
    def self.set_primary_key(*key)
      # if k is nil, we go to no_primary_key
      if key.empty? || (key.size == 1 && key.first == nil)
        return no_primary_key
      end
      
      # backwards compat
      key = (key.length == 1) ? key[0] : key.flatten

      # redefine primary_key
      meta_def(:primary_key) {key}
      
      unless key.is_a? Array # regular primary key
        class_def(:this) do
          @this ||= dataset.filter(key => @values[key]).limit(1).naked
        end
        class_def(:pk) do
          @pk ||= @values[key]
        end
        class_def(:pk_hash) do
          @pk ||= {key => @values[key]}
        end
        class_def(:cache_key) do
          pk = @values[key] || (raise Error, 'no primary key for this record')
          @cache_key ||= "#{self.class}:#{pk}"
        end
        meta_def(:primary_key_hash) do |v|
          {key => v}
        end
      else # composite key
        exp_list = key.map {|k| "#{k.inspect} => @values[#{k.inspect}]"}
        block = eval("proc {@this ||= self.class.dataset.filter(#{exp_list.join(',')}).limit(1).naked}")
        class_def(:this, &block)
        
        exp_list = key.map {|k| "@values[#{k.inspect}]"}
        block = eval("proc {@pk ||= [#{exp_list.join(',')}]}")
        class_def(:pk, &block)
        
        exp_list = key.map {|k| "#{k.inspect} => @values[#{k.inspect}]"}
        block = eval("proc {@this ||= {#{exp_list.join(',')}}}")
        class_def(:pk_hash, &block)
        
        exp_list = key.map {|k| '#{@values[%s]}' % k.inspect}.join(',')
        block = eval('proc {@cache_key ||= "#{self.class}:%s"}' % exp_list)
        class_def(:cache_key, &block)

        meta_def(:primary_key_hash) do |v|
          key.inject({}) {|m, i| m[i] = v.shift; m}
        end
      end
    end
    
    def self.no_primary_key #:nodoc:
      meta_def(:primary_key) {nil}
      meta_def(:primary_key_hash) {|v| raise Error, "#{self} does not have a primary key"}
      class_def(:this)      {raise Error, "No primary key is associated with this model"}
      class_def(:pk)        {raise Error, "No primary key is associated with this model"}
      class_def(:pk_hash)   {raise Error, "No primary key is associated with this model"}
      class_def(:cache_key) {raise Error, "No primary key is associated with this model"}
    end
    
    # Creates new instance with values set to passed-in Hash, saves it
    # (running any callbacks), and returns the instance.
    def self.create(values = {}, &block)
      obj = new(values, &block)
      obj.save
      obj
    end
    
    # Updates the instance with the supplied values with support for virtual
    # attributes, ignoring any values for which no setter method is available.
    # Does not save the record.
    def set_with_params(hash)
      meths = setter_methods
      hash.each do |k,v|
        m = "#{k}="
        send(m, v) if meths.include?(m)
      end
    end

    # Runs set_with_params and saves the changes (which runs any callback methods).
    def update_with_params(values)
      set_with_params(values)
      save_changes
    end

    # Returns (naked) dataset bound to current instance.
    def this
      @this ||= self.class.dataset.filter(:id => @values[:id]).limit(1).naked
    end
    
    # Returns a key unique to the underlying record for caching
    def cache_key
      pk = @values[:id] || (raise Error, 'no primary key for this record')
      @cache_key ||= "#{self.class}:#{pk}"
    end

    # Returns primary key column(s) for object's Model class.
    def primary_key
      @primary_key ||= self.class.primary_key
    end
    
    # Returns the primary key value identifying the model instance. If the
    # model's primary key is changed (using #set_primary_key or #no_primary_key)
    # this method is redefined accordingly.
    def pk
      @pk ||= @values[:id]
    end
    
    # Returns a hash identifying the model instance. Stock implementation.
    def pk_hash
      @pk_hash ||= {:id => @values[:id]}
    end
    
    # Creates new instance with values set to passed-in Hash.
    #
    # This method guesses whether the record exists when
    # <tt>new_record</tt> is set to false.
    def initialize(values = nil, from_db = false, &block)
      values ||=  {}
      @changed_columns = []
      if from_db
        @new = false
        @values = values
      else
        @values = {}
        @new = true
        set_with_params(values)
      end
      @changed_columns.clear 
      
      yield self if block
      after_initialize
    end
    
    # Initializes a model instance as an existing record. This constructor is 
    # used by Sequel to initialize model instances when fetching records.
    def self.load(values)
      new(values, true)
    end
    
    # Returns true if the current instance represents a new record.
    def new?
      @new
    end
    
    # Returns true when current instance exists, false otherwise.
    def exists?
      this.count > 0
    end
    
    # Creates or updates the associated record. This method can also
    # accept a list of specific columns to update.
    def save(*columns)
      before_save
      if @new
        before_create
        iid = model.dataset.insert(@values)
        # if we have a regular primary key and it's not set in @values,
        # we assume it's the last inserted id
        if (pk = primary_key) && !(Array === pk) && !@values[pk]
          @values[pk] = iid
        end
        if pk
          @this = nil # remove memoized this dataset
          refresh
        end
        @new = false
        after_create
      else
        before_update
        if columns.empty?
          this.update(@values)
          @changed_columns = []
        else # update only the specified columns
          this.update(@values.reject {|k, v| !columns.include?(k)})
          @changed_columns.reject! {|c| columns.include?(c)}
        end
        after_update
      end
      after_save
      self
    end
    
    # Saves only changed columns or does nothing if no columns are marked as 
    # chanaged.
    def save_changes
      save(*@changed_columns) unless @changed_columns.empty?
    end

    # Sets the value attributes without saving the record.  Returns
    # the values changed.  Raises an error if the keys are not symbols
    # or strings or a string key was passed that was not a valid column.
    # This is a low level method that does not respect virtual attributes.  It
    # should probably be avoided.  Look into using set_with_params instead.
    def set_values(values)
      s = str_columns
      vals = values.inject({}) do |m, kv| 
        k, v = kv
        k = case k
        when Symbol
          k
        when String
          # Prevent denial of service via memory exhaustion by only 
          # calling to_sym if the symbol already exists.
          raise(::Sequel::Error, "all string keys must be a valid columns") unless s.include?(k)
          k.to_sym
        else
          raise(::Sequel::Error, "Only symbols and strings allows as keys")
        end
        m[k] = v
        m
      end
      vals.each {|k, v| @values[k] = v}
      vals
    end

    # Sets the values attributes with set_values and then updates
    # the record in the database using those values.  This is a
    # low level method that does not run the usual save callbacks.
    # It should probably be avoided.  Look into using update_with_params instead.
    def update_values(values)
      this.update(set_values(values))
    end
    
    # Reloads values from database and returns self.
    def refresh
      @values = this.first || raise(Error, "Record not found")
      model.all_association_reflections.each do |r|
        instance_variable_set("@#{r[:name]}", nil)
      end
      self
    end
    alias_method :reload, :refresh

    # Like delete but runs hooks before and after delete.
    def destroy
      db.transaction do
        before_destroy
        delete
        after_destroy
      end
      self
    end
    
    # Deletes and returns self.  Does not run callbacks.
    # Look into using destroy instead.
    def delete
      this.delete
      self
    end
    
    private
      # Returns all methods that can be used for attribute
      # assignment (those that end with =)
      def setter_methods
        methods.grep(/=\z/)
      end
  end
end
