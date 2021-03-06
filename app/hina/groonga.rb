require 'json'

Groonga::Database.open GROONGA_DB_PATH

module Hina

  class Model

    module ModelExtensionMethods
      def entity_map
        @@entity_map ||= {}
      end

      def inherited(subclass)
        super
        table_name = subclass.name.split('::')[-1].to_sym
        table = Groonga[table_name]
        subclass.setup_model(table)
        entity_map[table_name] = subclass
      end

      protected
      def setup_model(table)
        @table = table
        @attributes = table.columns.map do |column|
          attr_name = column.local_name.to_sym
          define_attribute(attr_name)
          attr_name
        end
        extend ClassMethods
        include InstanceMethods
      end

      def define_attribute(name)
        define_method name do
          @values[name]
        end
        define_method "#{name}=" do |value|
          @modified_attributes << name unless @modified_attributes.nil? or @modified_attributes.include? name
          @values[name] = value
        end
      end
    end

    module ClassMethods
      LoadOptions = [:includes, :excludes]
      SelectOptions = [:sort, :offset, :limit]

      attr_reader :table, :attributes

      def [](key, options={})
        record = table[key]
        record.nil? ? nil : new(record, options)
      end

      def select(options={}, &block)
        sort_keys = options.has_key?(:sort) ? options.delete(:sort) : ['_id']
        sort_options = {
          :offset => options.delete(:offset),
          :limit => options.delete(:limit)
        }
        load_options = {
          :includes=>options.delete(:includes),
          :excludes=>options.delete(:excludes)
        }
        resultset = table.select(options, &block)
        resultset.sort(sort_keys, sort_options).map do |record|
          new(record, load_options)
        end
      end
    end

    module InstanceMethods
      attr_reader :key

      def initialize(*args)
        if args.first.is_a? Groonga::Record
          sync(*args)
        else
          @key = args.first
          @values = args[1]
          @storead = false
        end
      end

      def sync(record=nil, options={})
        if @stored and record.nil?
          record = self.class.table[key]
        end
        unless record.nil?
          @key = record._key
          @values = {}
          target_attributes = options[:includes] || self.class.attributes
          target_attributes -= options[:excludes] if options[:excludes]
          target_attributes.each do |attr|
            column = self.class.table.column(attr)
            next if column.index?
            value = record[attr]
            if column.reference?
              entity_class = self.class.entity_map[column.range.name.to_sym]
              if column.vector?
                value = value.map {|subrecord| entity_class.new(subrecord) }
              else
                value = entity_class.new(value)
              end
            end
            @values[attr] = value
          end
          @stored = true
          @modified_attributes = []
        end
      end

      def save
        @stored ? update : create
      end

      def create
        logging.debug("create #{self.class}[#{self.key}]")
        values = {}
        @values.each do |key, value|
          next if value.nil?
          column = self.class.table.column key
          if column.reference?
            if column.vector?
              value = value.map {|item| item.key}
            else
              value = value.key
            end
          end
          values[key] = value
        end
        self.class.table.add @key, values
        @stored = true
      end

      def update
        logging.debug("update #{self.class}[#{self.key}]")
        unless @modified_attributes.nil? or @modified_attributes.empty?
          record = self.class.table[key]
          @modified_attributes.each do |attr|
            value = @values[attr]
            column = self.class.table.column attr
            if not value.nil? and column.reference?
              if column.vector?
                value = value.map {|item| item.key }
              else
                value = value.key
              end
            end
            record[attr] = value
            logging.debug("update #{self.class}[#{self.key}].#{attr}")
          end
        end
      end

      def delete
        self.class.delete(key)
      end

      def to_json(*a)
        values = @values.dup
        values[:key] = key
        values.to_json
      end
    end

    extend ModelExtensionMethods
  end

end


class Time

  def to_json(*a)
    "\"#{strftime('%Y/%m/%d %H:%M:%S.%-2L')}\""
  end

end


