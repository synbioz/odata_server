module OData
  module Core
    class Query
      attr_reader :data_services
      attr_reader :segments, :options
      
      def initialize(data_services, segments = [], options = {})
        @data_services = data_services
        
        @segments = segments
        @options = options
      end

      def Segment(*args)
        segment_class = begin
          if args.first.is_a?(Symbol) || args.first.is_a?(String)
            "OData::Core::Segments::#{args.shift.to_s}Segment".constantize
          else
            args.shift
          end
        end
        
        segment = segment_class.new(self, *args)
        
        @segments << segment
        segment
      end
      
      def Option(*args)
        option_class = begin
          if args.first.is_a?(Symbol) || args.first.is_a?(String)
            "OData::Core::Options::#{args.shift.to_s}Option".constantize
          else
            args.shift
          end
        end

        option = option_class.new(self, *args)

        key = option.option_name.underscore.to_sym
        @options[key] = option

        option
      end
      
      def resource_path
        @segments.collect(&:value).join('/')
      end
      
      def query_string
        @options.collect { |o| "#{o.key.to_s}=#{o.value.to_s}" }.join('&')
      end
      
      def to_uri
        [resource_path, query_string].reject(&:blank?).join('?')
      end
      
      def execute!
        _execute!
      end
      
      # def entity_type
      #   return nil if @segments.empty?
      #   return nil unless @segments.last.respond_to?(:entity_type)
      #   @segments.last.entity_type
      # end
      
      protected
      
      def _execute!
        _segments = Array(@segments).compact
        results = __execute!([], nil, _segments.shift, _segments)
        results = with_filter_options(with_skip_and_top_options(with_orderby_option(results)))
        results.respond_to?(:all) ? results.all : results
      end
      
      def __execute!(seen, acc, head, rest)
        return acc if head.blank?
        raise Errors::InvalidSegmentContext.new(self, head) unless seen.empty? || head.can_follow?(seen.last)
        results = head.execute!(acc, @options)
        raise Errors::ExecutionOfSegmentFailedValidation.new(self, head) unless head.valid?(results)

        seen << head
        __execute!(seen, results, rest.shift, rest)
      end
      
      private
      
      def with_filter_options(results)
        filter_option = @options[:$filter]
        if filter_option && (entity_type = filter_option.entity_type)
          results = entity_type.filter(results, filter_option)
        else
          results
        end
      end
      
      def with_orderby_option(results)
        orderby_option = @options[:$orderby]
        
        orderby = orderby_option.blank? ? nil : orderby_option.pairs
        
        if orderby && (entity_type = orderby_option.entity_type)
          results = entity_type.sort(results, orderby)
        else
          results
        end
      end
      
      def with_skip_and_top_options(results)
        opts = @options.slice(:$skip, :$top)
        entity_type = opts.values.find(&:entity_type).try(:entity_type)

        if entity_type
          entity_type.limit(results, opts)
        else
          results
        end
      end
    end
  end
  
  module AbstractSchema
    class Base
      def Query(*args)
        OData::Core::Base.new(self, *args)
      end
    end
  end
end
