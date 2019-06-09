module Renderable
  extend ActiveSupport::Concern

  included do
    extend RenderableClassMethods

    rescue_from ActiveRecord::RecordInvalid,
      :with => :renderable_record_invalid
  end

  LOCATION = 'Location'.freeze
  DEFAULT_SORT = { :id => :asc }.freeze

  def renderable_record_invalid(error = nil)
    if !error.nil?
      raise error if !error.respond_to?(:record)

      render_errors error.record.errors, { status: :unprocessable_entity }
    end
  end

  protected
    def filter_collection(collection = [], opts = {})
      collection = collection.all

      meta_param = opts.delete(:meta) || {}
      ignore = opts.delete(:ignore) || {}
      klass = opts.delete(:class) || collection.klass

      controller = self.class.controller_for(klass.name)

      unless ignore.include?(:include)
        collection = controller
          .recordset_apply(:params => include_params, :joins => :includes,
            :recordset => collection)
      end

      unless ignore.include?(:join)
        collection = controller
          .recordset_apply(:params => join_params, :joins => :joins,
            :recordset => collection)
      end

      unless ignore.include?(:filter)
        collection = controller
          .recordset_apply(:params => filter_params,
            :apply => method(:filter_recordset), :joins => :left_joins,
            :recordset => collection)
      end

      unless ignore.include?(:quicksearch)
        if !quicksearch_param.blank? && collection.respond_to?(:quicksearch)
          collection = collection.quicksearch(quicksearch_param)
        end
      end

      unless ignore.include?(:page)
        if !page_params.blank? && collection.respond_to?(:paginate)
          collection = collection.paginate(page_params)
          meta_param.merge!({ :paging => page_details(collection) })
        end
      end

      unless ignore.include?(:sort)
        sort_params.each { |s|
          collection = controller
            .recordset_apply(:params => s, :joins => :joins,
              :apply => :order, :recordset => collection) }
      end

      unless ignore.include?(:distinct)
        collection = collection.distinct if distinct_param
      end

      colllection = yield collection if block_given?

      return collection
    end

    def render_collection(collection = [], opts = {})
      meta_param = opts.delete(:meta) || {}

      if block_given?
        collection = filter_collection(collection,
          opts.merge(:meta => meta_param)) { yield collection }
      else
        collection = filter_collection(collection,
          opts.merge(:meta => meta_param))
      end

      render({ json: collection, include: include_params, meta: meta_param }
        .merge!(opts))
    end

    def render_instance(object = {}, opts = {})
      render({ json: object, include: include_params }.merge!(opts))
    end

    def render_errors(errors = {}, opts = {})
      render({ json: { :errors => errors }}.merge!(opts))
    end

    def render_worker_request(reply_queue_key_name, opts = {})
      queue_id = Worker.reply_queue_id(reply_queue_key_name)

      location = Rails.application.routes.url_helpers.url_for(
        :controller => :workers, :action => :replies, :only_path => true,
        :queue_id => queue_id)

      response.set_header(LOCATION, location) if !location.nil?
      response.status = opts.delete(:status) || :accepted

      render({ json: { :status => :pending,
        :tracking => { :url => location } } }.merge!(opts))
    end

    def render_worker_response(worker_response, opts = {})
      if worker_response.status == Worker::TIMEOUT
        response.status = :gateway_timeout
      elsif worker_response.status == Worker::FAILED
        response.status = :internal_server_error
      else
        response.status = opts.delete(:status) || :ok
      end

      render({ json: worker_response, include: include_params }.merge!(opts))
    end

    module RenderableClassMethods
      def recordset_apply(options)
        apply = options.delete(:apply)
        joins = options.delete(:joins)
        params = options.delete(:params)

        recordset = options.delete(:recordset)
        recordset ||= self.model.all

        apply_params = params.slice(*model_columns)

        result = recordset

        if apply.respond_to?(:call)
          result = apply.call(result, apply_params, model)
        elsif apply.is_a?(Symbol)
          result = result.public_send(apply, apply_params)
        end

        params.slice(*model_associations).keys.each do |k|
          association = self.model.reflections[k.to_s]
          foreign_controller = controller_for(association.class_name)

          if foreign_controller < Renderable
            if joins.respond_to?(:call)
              result = joins.call(result, association.name.to_sym)
            elsif joins.is_a?(Symbol)
              result = result.public_send(joins, association.name.to_sym)
            end

            result = result.merge(foreign_controller.recordset_apply(
              {
                :params => params[association.name],
                :apply => apply,
                :joins => joins
              }))
          end
        end

        return result
      end

      def model
        @model ||= "#{controller_name.camelize.singularize}".constantize
      end

      def model_columns
        @model_columns ||= model.column_names.clone.map(&:to_sym)
      end

      def model_associations
        @model_associations ||= model.reflect_on_all_associations
          .map { |a| a.name.to_sym }
      end

      def controller_for(model_name)
        @controller_for_cache ||= {}
        @controller_for_cache[model_name.underscore.to_sym] ||=
            "#{model_name.pluralize}Controller".constantize
      end
    end

  private
    def include_params
      return {} if params[:include].blank?

      Array(params.fetch(:include)).map { |p|
        p.split('.').reverse.map(&:to_sym).inject({}) { |a, n| { n => a } }
      }.reduce({}, :merge)
    end

    def join_params
      return {} if params[:join].blank?

      Array(params.fetch(:join)).map { |p|
        p.split('.').reverse.map(&:to_sym).inject({}) { |a, n| { n => a } }
      }.reduce({}, :merge)
    end

    def filter_params
      return {} if params[:filter].blank?

      Hash(params.fetch(:filter).to_unsafe_h)
    end

    def distinct_param
      return false if params[:distinct].blank?

      return !!params[:distinct]
    end

    def quicksearch_param
      return if params[:quicksearch].blank?

      params.fetch(:quicksearch)
    end

    def page_params
      return if params[:page].blank?

      params.fetch(:page).permit(:number, :size)
    end

    def sort_params
      return [DEFAULT_SORT] if params[:sort].blank?

      Array(params.fetch(:sort)).map do |p|
        o = p.starts_with?('-') ? :desc : :asc
        p.slice!(0) if o == :desc
        p.split('.').reverse.map(&:to_sym).inject(o) { |a, n| { n => a } }
      end
    end

    def page_details(collection)
      {
        total_count: collection.total_count,
        total_pages: collection.total_pages,
        current_page: collection.current_page,
      }
    end

    def filter_recordset(recordset, filter_hash, model)
      conjunction = nil

      filter_hash.each do |k, v|
        next if !model.columns_hash.include?(k)

        arel = model.arel_table[k]
        type = model.type_for_attribute(k).type

        values = Array(v)
        values.each do |value|
          value = value.to_s
          alternatives = nil

          if type == :string
            alternatives = arel.eq(value)
          else
            predicate = :eq

            value.split(',').each do |v|
              if v.starts_with?('>=')
                predicate = :gteq
                v.slice!(0)
              elsif v.starts_with?('<=')
                predicate = :lteq
                v.slice!(0)
              elsif v.starts_with?('>')
                predicate = :gt
                v.slice!(0)
              elsif v.starts_with?('<')
                predicate = :lt
                v.slice!(0)
              elsif v.starts_with?('!')
                predicate = :is_distinct_from
                v.slice!(0)
              end

              cast_v = model.type_for_attribute(k.to_s).cast(v)
              condition = arel.public_send(predicate, cast_v)

              alternatives = !alternatives.nil? ?
                alternatives.or(condition) : condition
            end
          end

          conjunction = !conjunction.nil? ?
            conjunction.and(alternatives) : alternatives
        end
      end

      recordset.where(conjunction)
    end
end
